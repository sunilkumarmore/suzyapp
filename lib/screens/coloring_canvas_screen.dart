import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/coloring_page.dart';
import '../utils/asset_path.dart';
import '../utils/dev_log.dart';

class ColoringCanvasArgs {
  final List<ColoringPage> pages;
  final int initialIndex;

  ColoringCanvasArgs(this.pages, {required this.initialIndex});
}

class ColoringCanvasScreen extends StatefulWidget {
  final List<ColoringPage> pages;
  final int initialIndex;

  const ColoringCanvasScreen({
    super.key,
    required this.pages,
    required this.initialIndex,
  });

  @override
  State<ColoringCanvasScreen> createState() => _ColoringCanvasScreenState();
}

class _ColoringCanvasScreenState extends State<ColoringCanvasScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  int _index = 0;

  ui.Image? _outlineImage;
  ui.Image? _fillImage;
  Uint8List? _maskPixels;
  Uint8List? _fillPixels;
  Size _imageSize = Size.zero;
  bool _isSvg = false;
  Size _svgSize = Size.zero;
  List<_SvgRegion> _svgRegions = const [];
  List<_SvgOutline> _svgOutlines = const [];
  Map<String, Color> _svgRegionColors = {};
  final List<Map<String, Color>> _svgUndoStack = [];

  final List<Uint8List> _undoStack = [];
  bool _isFilling = false;
  final AudioPlayer _sfxPlayer = AudioPlayer();
  String? _assetLoadError;

  final List<Color> _palette = [
    const Color(0xFFE35A55),
    const Color(0xFFF6C463),
    const Color(0xFF57B37A),
    const Color(0xFF86C6E6),
    const Color(0xFF7B63E6),
    const Color(0xFFF08FB3),
    const Color(0xFF95C86B),
    const Color(0xFFEF8A54),
  ];
  int _selectedColorIndex = 0;

  Offset? _sparkleOffset;
  late final AnimationController _sparkleController;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.pages.length - 1);
    _pageController = PageController(initialPage: _index);
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadPageAssets();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _sparkleController.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadPageAssets() async {
    final page = widget.pages[_index];
    final outlinePath = AssetPath.normalize(page.imageAsset);
    final maskPath = AssetPath.normalize(page.maskAsset);
    _assetLoadError = null;

    if (outlinePath.toLowerCase().endsWith('.svg')) {
      await _loadSvgAssets(outlinePath);
      return;
    }

    ui.Image? outline;
    ui.Image? mask;
    try {
      outline = await _loadUiImage(outlinePath);
    } catch (e) {
      DevLog.coloring('outline load failed: $outlinePath -> $e');
      outline = null;
    }
    try {
      mask = await _loadUiImage(maskPath);
    } catch (e) {
      DevLog.coloring('mask load failed: $maskPath -> $e');
      mask = null;
    }

    if (outline == null && mask == null) {
      _assetLoadError = 'Could not load outline or mask for this page.';
      DevLog.coloring('asset load failed for page=${page.id}');
    }

    final int imgW = mask?.width ?? outline?.width ?? 1;
    final int imgH = mask?.height ?? outline?.height ?? 1;
    final Size size = Size(imgW.toDouble(), imgH.toDouble());
    final maskPixels = mask != null
        ? await _rgbaBytes(mask)
        : _solidRgba(imgW, imgH, const Color(0xFF000000));

    if (mask != null) {
      DevLog.coloring('mask decoded size: ${mask.width}x${mask.height}, len=${maskPixels.length}');
    }

    if (outline != null) {
      outline = await _extractLineArt(outline);
    }

    if (!mounted) return;
    setState(() {
      _isSvg = false;
      _outlineImage = outline;
      _imageSize = size;
      _maskPixels = maskPixels;
      _fillPixels = Uint8List(maskPixels.length);
      _undoStack.clear();
      _svgSize = Size.zero;
      _svgRegions = const [];
      _svgOutlines = const [];
      _svgRegionColors = {};
      _svgUndoStack.clear();
    });
    await _refreshFillImage();
  }

  Future<void> _loadSvgAssets(String svgPath) async {
    try {
      final raw = await rootBundle.loadString(svgPath);
      final doc = XmlDocument.parse(raw);
      final svg = doc.findAllElements('svg').first;

      final svgSize = _parseSvgSize(svg);
      final regions = _parseSvgRegions(svg);
      final outlines = _parseSvgOutlines(svg);

      if (!mounted) return;
      setState(() {
        _isSvg = true;
        _svgSize = svgSize;
        _svgRegions = regions;
        _svgOutlines = outlines;
        _svgRegionColors = {};
        _svgUndoStack.clear();
        _outlineImage = null;
        _fillImage = null;
        _maskPixels = null;
        _fillPixels = null;
        _imageSize = svgSize;
        _undoStack.clear();
      });
    } catch (e) {
      DevLog.coloring('failed to load SVG: $e');
      if (!mounted) return;
      setState(() {
        _isSvg = false;
      });
    }
  }

  Future<ui.Image> _loadUiImage(String assetPath) async {
    final Uint8List bytes;
    if (AssetPath.isRemote(assetPath)) {
      final uri = Uri.parse(assetPath);
      final resp = await http.get(uri);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Failed to fetch image: ${resp.statusCode} $assetPath');
      }
      bytes = resp.bodyBytes;
    } else {
      final data = await rootBundle.load(assetPath);
      bytes = data.buffer.asUint8List();
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List> _rgbaBytes(ui.Image img) async {
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) {
      DevLog.coloring('failed to read RGBA bytes');
      return Uint8List(0);
    }
    return bytes.buffer.asUint8List();
  }

  Future<ui.Image> _extractLineArt(ui.Image img) async {
    final rgba = await _rgbaBytes(img);
    if (rgba.isEmpty) return img;

    for (int i = 0; i < rgba.length; i += 4) {
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final a = rgba[i + 3];
      if (a == 0) continue;
      // Keep only dark line-art pixels; make everything else transparent.
      final isLine = r <= 90 && g <= 90 && b <= 90;
      if (isLine) {
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
        rgba[i + 3] = 255;
      } else {
        rgba[i + 3] = 0;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      img.width,
      img.height,
      ui.PixelFormat.rgba8888,
      (lineArt) => completer.complete(lineArt),
    );
    return completer.future;
  }

  Uint8List _solidRgba(int w, int h, Color color) {
    final out = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      final o = i * 4;
      out[o] = color.red;
      out[o + 1] = color.green;
      out[o + 2] = color.blue;
      out[o + 3] = color.alpha;
    }
    return out;
  }

  Future<void> _refreshFillImage() async {
    final pixels = _fillPixels;
    if (pixels == null) return;
    final w = _imageSize.width.toInt();
    final h = _imageSize.height.toInt();

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    final img = await completer.future;
    if (!mounted) return;
    setState(() => _fillImage = img);
  }

  Rect _containRect(Size outer, Size inner) {
    if (inner.width == 0 || inner.height == 0) {
      return Rect.fromLTWH(0, 0, outer.width, outer.height);
    }
    final scale = min(outer.width / inner.width, outer.height / inner.height);
    final w = inner.width * scale;
    final h = inner.height * scale;
    final left = (outer.width - w) / 2;
    final top = (outer.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  Future<void> _handleTap(Offset localPos, Rect rect) async {
    if (_isFilling) return;
    if (_isSvg) {
      _handleSvgTap(localPos, rect);
      return;
    }
    if (_maskPixels == null || _fillPixels == null) return;
    if (!rect.contains(localPos)) return;

    final imgW = _imageSize.width.toInt();
    final imgH = _imageSize.height.toInt();
    if (imgW <= 0 || imgH <= 0) return;

    final scale = min(rect.width / imgW, rect.height / imgH);
    if (scale <= 0) return;
    final drawnW = imgW * scale;
    final drawnH = imgH * scale;
    final offsetX = rect.left + (rect.width - drawnW) / 2;
    final offsetY = rect.top + (rect.height - drawnH) / 2;

    final x = ((localPos.dx - offsetX) / scale).round();
    final y = ((localPos.dy - offsetY) / scale).round();
    if (x < 0 || x >= imgW || y < 0 || y >= imgH) return;
    final mask = _maskPixels!;
    int tx = x;
    int ty = y;
    int idx = (ty * imgW + tx) * 4;
    if (idx < 0 || idx + 3 >= mask.length) return;
    int r = mask[idx];
    int g = mask[idx + 1];
    int b = mask[idx + 2];
    int a = mask[idx + 3];

    // If user taps a boundary pixel, search nearby for the nearest fillable region.
    bool isBlocked(int rr, int gg, int bb, int aa) =>
        aa == 0 || (rr == 0 && gg == 0 && bb == 0);
    if (isBlocked(r, g, b, a)) {
      const maxRadius = 12;
      bool found = false;
      for (int radius = 1; radius <= maxRadius && !found; radius++) {
        for (int dy = -radius; dy <= radius && !found; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= imgW || ny >= imgH) continue;
            final nidx = (ny * imgW + nx) * 4;
            final nr = mask[nidx];
            final ng = mask[nidx + 1];
            final nb = mask[nidx + 2];
            final na = mask[nidx + 3];
            if (!isBlocked(nr, ng, nb, na)) {
              tx = nx;
              ty = ny;
              idx = nidx;
              r = nr;
              g = ng;
              b = nb;
              a = na;
              found = true;
              break;
            }
          }
        }
      }
      if (!found) return;
    }

    DevLog.coloring(
      'fill tap: x=$x y=$y -> tx=$tx ty=$ty imgW=$imgW imgH=$imgH '
      'idx=$idx maskLen=${mask.length} rgba=($r,$g,$b,$a)',
    );

    // Ignore fully transparent/background taps after neighbor search.
    if (a == 0) return;
    if (r == 0 && g == 0 && b == 0) return;

    _undoStack.add(Uint8List.fromList(_fillPixels!));
    _isFilling = true;

    final color = _palette[_selectedColorIndex];
    final fill = await compute(_fillRegion, {
      'mask': _maskPixels!,
      'fill': _fillPixels!,
      'width': imgW,
      'height': imgH,
      'x': tx,
      'y': ty,
      'target': [r, g, b],
      'targetAlpha': 255,
      'minAlpha': 1,
      'color': [color.red, color.green, color.blue],
      'tol': 12,
      'ignoreBlack': true,
    });

    if (!mounted) return;
    setState(() {
      _fillPixels = fill;
      _sparkleOffset = localPos;
    });
    await _refreshFillImage();
    _showSparkle();
    _playFillSfx();
    _isFilling = false;
  }

  void _handleSvgTap(Offset localPos, Rect rect) {
    if (!_isSvg) return;
    if (!rect.contains(localPos)) return;
    if (_svgRegions.isEmpty || _svgSize.width <= 0 || _svgSize.height <= 0) {
      return;
    }

    final svgPoint = _mapToSvg(localPos, rect, _svgSize);
    if (svgPoint == null) return;

    _SvgRegion? hit;
    for (final r in _svgRegions) {
      if (r.path.contains(svgPoint)) {
        hit = r;
        break;
      }
    }
    if (hit == null) return;

    _svgUndoStack.add(Map<String, Color>.from(_svgRegionColors));
    final color = _palette[_selectedColorIndex];
    setState(() {
      _svgRegionColors[hit!.id] = color;
      _sparkleOffset = localPos;
    });
    _showSparkle();
    _playFillSfx();
  }

  Offset? _mapToSvg(Offset localPos, Rect rect, Size svgSize) {
    if (rect.width <= 0 ||
        rect.height <= 0 ||
        svgSize.width <= 0 ||
        svgSize.height <= 0) {
      return null;
    }
    final dx = ((localPos.dx - rect.left) / rect.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final dy = ((localPos.dy - rect.top) / rect.height)
        .clamp(0.0, 1.0)
        .toDouble();
    return Offset(dx * svgSize.width, dy * svgSize.height);
  }

  void _showSparkle() {
    _sparkleController.forward(from: 0);
  }

  Future<void> _playFillSfx() async {
    try {
      await _sfxPlayer.setAsset('assets/audio/sfx/color_fill.mp3');
      await _sfxPlayer.setVolume(0.2);
      await _sfxPlayer.seek(Duration.zero);
      await _sfxPlayer.play();
    } catch (e) {
      DevLog.coloring('color_fill sfx error: $e');
    }
  }

  void _undo() {
    if (_isSvg) {
      if (_svgUndoStack.isEmpty) return;
      setState(() => _svgRegionColors = _svgUndoStack.removeLast());
      return;
    }
    if (_undoStack.isEmpty) return;
    setState(() => _fillPixels = _undoStack.removeLast());
    _refreshFillImage();
  }

  void _reset() {
    if (_isSvg) {
      setState(() {
        _svgRegionColors = {};
        _svgUndoStack.clear();
      });
      return;
    }
    if (_fillPixels == null) return;
    setState(() {
      _fillPixels = Uint8List(_fillPixels!.length);
      _undoStack.clear();
    });
    _refreshFillImage();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.pages.length;
    final page = widget.pages[_index];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(page.title),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: total,
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                    _sparkleOffset = null;
                  });
                  _loadPageAssets();
                },
                itemBuilder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final canvasSize = _isSvg ? _svgSize : _imageSize;
                        final rect = _containRect(c.biggest, canvasSize);
                        return GestureDetector(
                          onTapDown: (details) =>
                              _handleTap(details.localPosition, rect),
                          child: Stack(
                            children: [
                              Container(
                                color: Colors.white,
                              ),
                              if (_isSvg)
                                Positioned.fromRect(
                                  rect: rect,
                                  child: CustomPaint(
                                    painter: _SvgColoringPainter(
                                      svgSize: _svgSize,
                                      regions: _svgRegions,
                                      outlines: _svgOutlines,
                                      regionColors: _svgRegionColors,
                                    ),
                                  ),
                                )
                              else if (_fillImage != null)
                                Positioned.fromRect(
                                  rect: rect,
                                  child: RawImage(
                                    image: _fillImage,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.none,
                                  ),
                                ),
                              if (!_isSvg && _outlineImage != null)
                                Positioned.fromRect(
                                  rect: rect,
                                  child: CustomPaint(
                                    painter: _ImageOverlayPainter(
                                      image: _outlineImage!,
                                      blendMode: BlendMode.multiply,
                                    ),
                                  ),
                                ),
                              if (_sparkleOffset != null)
                                Positioned(
                                  left: _sparkleOffset!.dx - 36,
                                  top: _sparkleOffset!.dy - 36,
                                  child: AnimatedBuilder(
                                    animation: _sparkleController,
                                    builder: (context, child) {
                                      final t = Curves.easeOut.transform(
                                        _sparkleController.value,
                                      );
                                      return Opacity(
                                        opacity: (1 - t).clamp(0.0, 1.0),
                                        child: Transform.scale(
                                          scale: 0.8 + t * 0.4,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Icon(
                                      Icons.auto_awesome,
                                      size: 48,
                                      color: Colors.black.withOpacity(0.2),
                                    ),
                                  ),
                                ),
                              if (_assetLoadError != null)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _assetLoadError!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
              child: Wrap(
                spacing: AppSpacing.medium,
                runSpacing: AppSpacing.small,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed:
                            (_isSvg ? _svgUndoStack.isNotEmpty : _undoStack.isNotEmpty)
                                ? _undo
                                : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        onPressed: _reset,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _index > 0
                            ? () => _pageController.previousPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                )
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '${_index + 1} / $total',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        onPressed: _index < total - 1
                            ? () => _pageController.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                )
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.large,
                AppSpacing.small,
                AppSpacing.large,
                AppSpacing.large,
              ),
              child: Wrap(
                spacing: AppSpacing.small,
                runSpacing: AppSpacing.small,
                children: List.generate(_palette.length, (i) {
                  final c = _palette[i];
                  final selected = i == _selectedColorIndex;
                  return InkWell(
                    onTap: () => setState(() => _selectedColorIndex = i),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.black : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Uint8List _fillRegion(Map<String, dynamic> args) {
  final mask = args['mask'] as Uint8List;
  final fill = args['fill'] as Uint8List;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final x = args['x'] as int;
  final y = args['y'] as int;
  final target = args['target'] as List;
  final targetAlpha = (args['targetAlpha'] as int?) ?? 255;
  final minAlpha = (args['minAlpha'] as int?) ?? 0;
  final color = args['color'] as List;
  final tol = (args['tol'] as int?) ?? 0;
  final ignoreBlack = (args['ignoreBlack'] as bool?) ?? false;

  final tr = target[0] as int;
  final tg = target[1] as int;
  final tb = target[2] as int;
  final fr = color[0] as int;
  final fg = color[1] as int;
  final fb = color[2] as int;

  final out = Uint8List.fromList(fill);
  if (width <= 0 || height <= 0) return out;
  if (x < 0 || y < 0 || x >= width || y >= height) return out;

  if (ignoreBlack && tr == 0 && tg == 0 && tb == 0) return out;

  bool matchesAt(int offset, int localTol) {
    final alpha = mask[offset + 3];
    if (alpha < minAlpha) return false;
    final rr = mask[offset];
    final gg = mask[offset + 1];
    final bb = mask[offset + 2];
    // Treat pure black as hard boundary; allow dark colors as valid regions.
    if (ignoreBlack && rr == 0 && gg == 0 && bb == 0) {
      return false;
    }
    final dr = (rr - tr).abs();
    final dg = (gg - tg).abs();
    final db = (bb - tb).abs();
    final da = (alpha - targetAlpha).abs();
    return dr <= localTol && dg <= localTol && db <= localTol && da <= 255;
  }

  final start = y * width + x;
  final startOffset = start * 4;
  if (!matchesAt(startOffset, tol)) return out;

  // First-pass for ID-map masks: recolor all pixels that match tapped region color.
  // This is robust when regions are disconnected or have tiny boundary breaks.
  const regionTol = 32;
  int globalPainted = 0;
  for (int i = 0; i < width * height; i++) {
    final o = i * 4;
    final rr = mask[o];
    final gg = mask[o + 1];
    final bb = mask[o + 2];
    final aa = mask[o + 3];
    if (aa == 0) continue;
    if (ignoreBlack && rr == 0 && gg == 0 && bb == 0) continue;
    if ((rr - tr).abs() <= regionTol &&
        (gg - tg).abs() <= regionTol &&
        (bb - tb).abs() <= regionTol) {
      out[o] = fr;
      out[o + 1] = fg;
      out[o + 2] = fb;
      out[o + 3] = 255;
      globalPainted++;
    }
  }
  DevLog.coloring(
    'fill global match: tol=$regionTol painted=$globalPainted target=($tr,$tg,$tb)',
  );
  if (globalPainted > 0) return out;

  int paintFlood(bool Function(int offset) matcher) {
    final visited = Uint8List(width * height);
    final queue = <int>[start];
    int head = 0;
    int painted = 0;

    while (head < queue.length) {
      final p = queue[head++];
      if (visited[p] == 1) continue;
      visited[p] = 1;

      final o = p * 4;
      if (!matcher(o)) continue;

      out[o] = fr;
      out[o + 1] = fg;
      out[o + 2] = fb;
      out[o + 3] = 255;
      painted++;

      final px = p % width;
      final py = p ~/ width;

      if (px > 0) queue.add(p - 1);
      if (px < width - 1) queue.add(p + 1);
      if (py > 0) queue.add(p - width);
      if (py < height - 1) queue.add(p + width);
    }
    return painted;
  }

  final painted = paintFlood((offset) => matchesAt(offset, tol));
  if (painted <= 16) {
    // Retry with progressively looser tolerance for noisy id-map exports.
    final retryPainted = paintFlood((offset) => matchesAt(offset, 36));
    if (retryPainted <= 16) {
      final retryPainted2 = paintFlood((offset) => matchesAt(offset, 72));
      if (retryPainted2 <= 16) {
        // Last fallback: global near-color replace for this tapped region color.
        // This helps when exported id-maps have slight color drift.
        const globalTol = 8;
        for (int i = 0; i < width * height; i++) {
          final o = i * 4;
          final rr = mask[o];
          final gg = mask[o + 1];
          final bb = mask[o + 2];
          final aa = mask[o + 3];
          if (aa == 0) continue;
          if (ignoreBlack && rr == 0 && gg == 0 && bb == 0) continue;
          if ((rr - tr).abs() <= globalTol &&
              (gg - tg).abs() <= globalTol &&
              (bb - tb).abs() <= globalTol) {
            out[o] = fr;
            out[o + 1] = fg;
            out[o + 2] = fb;
            out[o + 3] = 255;
          }
        }
      }
    }
  }

  return out;
}

Size _parseSvgSize(XmlElement svg) {
  final viewBox = svg.getAttribute('viewBox');
  if (viewBox != null && viewBox.trim().isNotEmpty) {
    final nums = _parseNums(viewBox);
    if (nums.length == 4 && nums[2] > 0 && nums[3] > 0) {
      return Size(nums[2], nums[3]);
    }
  }
  final w = double.tryParse(svg.getAttribute('width') ?? '');
  final h = double.tryParse(svg.getAttribute('height') ?? '');
  if (w != null && h != null && w > 0 && h > 0) {
    return Size(w, h);
  }
  return const Size(1024, 1024);
}

List<_SvgRegion> _parseSvgRegions(XmlElement svg) {
  final regionsGroup = svg
      .findAllElements('g')
      .where((g) => (g.getAttribute('id') ?? '') == 'regions')
      .cast<XmlElement?>()
      .firstWhere((g) => g != null, orElse: () => null);
  if (regionsGroup == null) return const [];

  final regions = <_SvgRegion>[];
  for (final p in regionsGroup.findElements('path')) {
    final id = p.getAttribute('id') ?? '';
    final d = p.getAttribute('d') ?? '';
    if (id.isEmpty || d.isEmpty) continue;
    try {
      regions.add(_SvgRegion(id: id, path: parseSvgPathData(d)));
    } catch (_) {
      // Skip malformed paths.
    }
  }
  return regions;
}

List<_SvgOutline> _parseSvgOutlines(XmlElement svg) {
  final outlineGroup = svg
      .findAllElements('g')
      .where((g) => (g.getAttribute('id') ?? '') == 'outline')
      .cast<XmlElement?>()
      .firstWhere((g) => g != null, orElse: () => null);
  if (outlineGroup == null) return const [];

  final groupStrokeWidth =
      double.tryParse(outlineGroup.getAttribute('stroke-width') ?? '') ?? 18.0;
  final outlines = <_SvgOutline>[];

  for (final p in outlineGroup.findElements('path')) {
    final d = p.getAttribute('d') ?? '';
    if (d.isEmpty) continue;
    final sw = double.tryParse(p.getAttribute('stroke-width') ?? '') ?? groupStrokeWidth;
    try {
      outlines.add(_SvgOutline(path: parseSvgPathData(d), strokeWidth: sw));
    } catch (_) {
      // Skip malformed paths.
    }
  }

  for (final c in outlineGroup.findElements('circle')) {
    final cx = double.tryParse(c.getAttribute('cx') ?? '');
    final cy = double.tryParse(c.getAttribute('cy') ?? '');
    final r = double.tryParse(c.getAttribute('r') ?? '');
    if (cx == null || cy == null || r == null || r <= 0) continue;
    final sw = double.tryParse(c.getAttribute('stroke-width') ?? '') ?? groupStrokeWidth;
    final path = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    outlines.add(_SvgOutline(path: path, strokeWidth: sw));
  }

  return outlines;
}

List<double> _parseNums(String raw) {
  final parts = raw.trim().split(RegExp(r'[ ,]+'));
  final out = <double>[];
  for (final p in parts) {
    final v = double.tryParse(p);
    if (v != null) out.add(v);
  }
  return out;
}

class _SvgRegion {
  final String id;
  final Path path;

  const _SvgRegion({required this.id, required this.path});
}

class _SvgOutline {
  final Path path;
  final double strokeWidth;

  const _SvgOutline({required this.path, required this.strokeWidth});
}

class _SvgColoringPainter extends CustomPainter {
  final Size svgSize;
  final List<_SvgRegion> regions;
  final List<_SvgOutline> outlines;
  final Map<String, Color> regionColors;

  _SvgColoringPainter({
    required this.svgSize,
    required this.regions,
    required this.outlines,
    required this.regionColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (svgSize.width <= 0 || svgSize.height <= 0) return;

    final scale = min(size.width / svgSize.width, size.height / svgSize.height);
    final dx = (size.width - svgSize.width * scale) / 2;
    final dy = (size.height - svgSize.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final fillPaint = Paint()..style = PaintingStyle.fill;
    for (final r in regions) {
      fillPaint.color = regionColors[r.id] ?? Colors.white;
      canvas.drawPath(r.path, fillPaint);
    }

    for (final o in outlines) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black
        ..strokeWidth = o.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(o.path, strokePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgColoringPainter oldDelegate) {
    return oldDelegate.regions != regions ||
        oldDelegate.outlines != outlines ||
        oldDelegate.regionColors != regionColors ||
        oldDelegate.svgSize != svgSize;
  }
}

class _ImageOverlayPainter extends CustomPainter {
  final ui.Image image;
  final BlendMode blendMode;

  const _ImageOverlayPainter({
    required this.image,
    this.blendMode = BlendMode.srcOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..blendMode = blendMode
      ..filterQuality = FilterQuality.none;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageOverlayPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.blendMode != blendMode;
  }
}

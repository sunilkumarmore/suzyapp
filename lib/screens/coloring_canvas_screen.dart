import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/coloring_page.dart';
import '../utils/asset_path.dart';

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

    if (outlinePath.toLowerCase().endsWith('.svg')) {
      await _loadSvgAssets(outlinePath);
      return;
    }

    ui.Image? outline;
    ui.Image? mask;
    try {
      outline = await _loadUiImage(outlinePath);
    } catch (_) {
      outline = null;
    }
    try {
      mask = await _loadUiImage(maskPath);
    } catch (_) {
      mask = null;
    }

    final Size size = mask != null
        ? Size(mask.width.toDouble(), mask.height.toDouble())
        : (outline != null
            ? Size(outline.width.toDouble(), outline.height.toDouble())
            : const Size(1, 1));
    final maskPixels = mask != null
        ? await _rgbaBytes(mask)
        : _solidRgba(size.width.toInt(), size.height.toInt(), const Color(0xFF000000));

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
      if (kDebugMode) {
        debugPrint('Failed to load SVG: $e');
      }
      if (!mounted) return;
      setState(() {
        _isSvg = false;
      });
    }
  }

  Future<ui.Image> _loadUiImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List> _rgbaBytes(ui.Image img) async {
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) {
      if (kDebugMode) {
        debugPrint('Failed to read RGBA bytes.');
      }
      return Uint8List(0);
    }
    return bytes.buffer.asUint8List();
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

    final x = ((localPos.dx - rect.left) / rect.width * _imageSize.width)
        .clamp(0, _imageSize.width - 1)
        .toInt();
    final y = ((localPos.dy - rect.top) / rect.height * _imageSize.height)
        .clamp(0, _imageSize.height - 1)
        .toInt();
    final idx = (y * _imageSize.width.toInt() + x) * 4;
    final mask = _maskPixels!;
    if (idx < 0 || idx + 3 >= mask.length) return;
    final r = mask[idx];
    final g = mask[idx + 1];
    final b = mask[idx + 2];
    final a = mask[idx + 3];

    if (kDebugMode) {
      debugPrint(
        'fill tap: x=$x y=$y idx=$idx maskLen=${mask.length} rgba=($r,$g,$b,$a)',
      );
    }

    if (a < 10) return;

    _undoStack.add(Uint8List.fromList(_fillPixels!));
    _isFilling = true;

    final color = _palette[_selectedColorIndex];
    final fill = await compute(_fillRegion, {
      'mask': _maskPixels!,
      'fill': _fillPixels!,
      'width': _imageSize.width.toInt(),
      'height': _imageSize.height.toInt(),
      'target': [r, g, b],
      'targetAlpha': a,
      // Be strict at edges to avoid coloring outside soft/dirty masks.
      'minAlpha': 200,
      'color': [color.red, color.green, color.blue],
      'tol': 0,
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
      if (kDebugMode) {
        debugPrint('color_fill sfx error: $e');
      }
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
                              if (_outlineImage != null)
                                Positioned.fromRect(
                                  rect: rect,
                                  child: RawImage(
                                    image: _outlineImage,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.none,
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
              child: Row(
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
                  const Spacer(),
                  IconButton(
                    onPressed: _index > 0
                        ? () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            )
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_index + 1} / $total',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  IconButton(
                    onPressed: _index < total - 1
                        ? () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            )
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const Spacer(),
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
  final target = args['target'] as List;
  final targetAlpha = (args['targetAlpha'] as int?) ?? 255;
  final minAlpha = (args['minAlpha'] as int?) ?? 0;
  final color = args['color'] as List;
  final tol = (args['tol'] as int?) ?? 0;

  final tr = target[0] as int;
  final tg = target[1] as int;
  final tb = target[2] as int;
  final fr = color[0] as int;
  final fg = color[1] as int;
  final fb = color[2] as int;

  final out = Uint8List.fromList(fill);
  for (int i = 0; i < width * height; i++) {
    final o = i * 4;
    final alpha = mask[o + 3];
    if (alpha < minAlpha) continue;
    if ((mask[o] - tr).abs() <= tol &&
        (mask[o + 1] - tg).abs() <= tol &&
        (mask[o + 2] - tb).abs() <= tol &&
        (alpha - targetAlpha).abs() <= tol) {
      out[o] = fr;
      out[o + 1] = fg;
      out[o + 2] = fb;
      out[o + 3] = 255;
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

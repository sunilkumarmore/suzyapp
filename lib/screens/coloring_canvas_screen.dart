import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

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

  final List<Uint8List> _undoStack = [];
  bool _isFilling = false;

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
    super.dispose();
  }

  Future<void> _loadPageAssets() async {
    final page = widget.pages[_index];
    final outlinePath = AssetPath.normalize(page.imageAsset);
    final maskPath = AssetPath.normalize(page.maskAsset);

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

    final Size size = outline != null
        ? Size(outline.width.toDouble(), outline.height.toDouble())
        : (mask != null
            ? Size(mask.width.toDouble(), mask.height.toDouble())
            : const Size(1, 1));
    final maskPixels = mask != null
        ? await _rgbaBytes(mask)
        : _solidRgba(size.width.toInt(), size.height.toInt(), const Color(0xFF000000));

    if (!mounted) return;
    setState(() {
      _outlineImage = outline;
      _imageSize = size;
      _maskPixels = maskPixels;
      _fillPixels = Uint8List(maskPixels.length);
      _undoStack.clear();
    });
    await _refreshFillImage();
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
    final r = mask[idx];
    final g = mask[idx + 1];
    final b = mask[idx + 2];

    if (r + g + b < 20) return;

    _undoStack.add(Uint8List.fromList(_fillPixels!));
    _isFilling = true;

    final color = _palette[_selectedColorIndex];
    final fill = await compute(_fillRegion, {
      'mask': _maskPixels!,
      'fill': _fillPixels!,
      'width': _imageSize.width.toInt(),
      'height': _imageSize.height.toInt(),
      'target': [r, g, b],
      'color': [color.red, color.green, color.blue],
      'tol': 8,
    });

    if (!mounted) return;
    setState(() {
      _fillPixels = fill;
      _sparkleOffset = localPos;
    });
    await _refreshFillImage();
    _showSparkle();
    _playWow();
    _isFilling = false;
  }

  void _showSparkle() {
    _sparkleController.forward(from: 0);
  }

  void _playWow() {
    if (kDebugMode) {
      debugPrint('playWow');
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() => _fillPixels = _undoStack.removeLast());
    _refreshFillImage();
  }

  void _reset() {
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
                        final rect = _containRect(c.biggest, _imageSize);
                        return GestureDetector(
                          onTapDown: (details) =>
                              _handleTap(details.localPosition, rect),
                          child: Stack(
                            children: [
                              Container(
                                color: Colors.white,
                              ),
                              if (_fillImage != null)
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
                    onPressed: _undoStack.isNotEmpty ? _undo : null,
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
    if ((mask[o] - tr).abs() <= tol &&
        (mask[o + 1] - tg).abs() <= tol &&
        (mask[o + 2] - tb).abs() <= tol) {
      out[o] = fr;
      out[o + 1] = fg;
      out[o + 2] = fb;
      out[o + 3] = 255;
    }
  }
  return out;
}

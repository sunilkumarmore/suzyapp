import 'dart:math';

import 'package:flutter/material.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';

class ChoiceTile extends StatelessWidget {
  final String label;
  final String? imageAsset;
  final bool selected;
  final bool showSparkle;
  final bool disabled;
  final VoidCallback onTap;

  const ChoiceTile({
    super.key,
    required this.label,
    required this.imageAsset,
    required this.selected,
    required this.showSparkle,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primaryBlue.withOpacity(0.15) : AppColors.surface;
    final border =
        selected ? AppColors.primaryBlue.withOpacity(0.6) : AppColors.outline.withOpacity(0.35);

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 112,
        padding: const EdgeInsets.all(AppSpacing.medium),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 8),
              color: Colors.black.withOpacity(selected ? 0.12 : 0.06),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: _ChoiceImage(asset: imageAsset),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (showSparkle) const Positioned.fill(child: _SparkleBurst()),
          ],
        ),
      ),
    );
  }
}

class _ChoiceImage extends StatelessWidget {
  final String? asset;
  const _ChoiceImage({this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: (asset == null || asset!.trim().isEmpty)
          ? const Center(child: Icon(Icons.image_outlined))
          : ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.large),
              child: Image.asset(
                asset!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
    );
  }
}

class _SparkleBurst extends StatefulWidget {
  const _SparkleBurst();
  @override
  State<_SparkleBurst> createState() => _SparkleBurstState();
}

class _SparkleBurstState extends State<_SparkleBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _SparklePainter(_c.value)),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final alpha = (1.0 - t).clamp(0.0, 1.0);
    final paint = Paint()..color = Colors.white.withOpacity(0.75 * alpha);

    const count = 14;
    final cx = size.width * 0.55;
    final cy = size.height * 0.45;
    final maxR = min(size.width, size.height) * 0.45;

    for (int i = 0; i < count; i++) {
      final ang = rnd.nextDouble() * pi * 2;
      final r = maxR * (0.2 + 0.8 * rnd.nextDouble()) * t;
      final x = cx + cos(ang) * r;
      final y = cy + sin(ang) * r;
      final base = 2.0 + rnd.nextDouble() * 3.5;
      final s = base * (1.0 - 0.4 * t);
      _drawStar(canvas, Offset(x, y), s, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    const points = 6;
    for (int i = 0; i < points * 2; i++) {
      final isOuter = i.isEven;
      final rad = isOuter ? r : r * 0.45;
      final ang = (pi / points) * i;
      final x = center.dx + cos(ang) * rad;
      final y = center.dy + sin(ang) * rad;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.t != t;
}

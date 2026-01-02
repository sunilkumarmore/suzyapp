import 'dart:async';
import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';

class ParentGateScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const ParentGateScreen({super.key, required this.onUnlocked});

  @override
  State<ParentGateScreen> createState() => _ParentGateScreenState();
}

class _ParentGateScreenState extends State<ParentGateScreen> {
  static const _holdDuration = Duration(seconds: 2);
  Timer? _timer;
  double _progress = 0;

  void _startHold() {
    _timer?.cancel();
    final start = DateTime.now();

    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final elapsed = DateTime.now().difference(start);
      final p = elapsed.inMilliseconds / _holdDuration.inMilliseconds;

      if (!mounted) return;
      setState(() => _progress = p.clamp(0, 1).toDouble());

      if (elapsed >= _holdDuration) {
        t.cancel();
        widget.onUnlocked();
      }
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _progress = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Parents Only'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grown-ups only',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.small),
            const Text(
              'Press and hold the button for 2 seconds to continue.',
              style: TextStyle(fontSize: 16, height: 1.3),
            ),
            const SizedBox(height: AppSpacing.large),

            GestureDetector(
              onTapDown: (_) => _startHold(),
              onTapCancel: _cancelHold,
              onTapUp: (_) => _cancelHold(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.large),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Press & Hold',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    LinearProgressIndicator(value: _progress),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

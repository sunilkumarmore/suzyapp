import 'package:flutter/material.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../design_system/app_colors.dart';

class ReadToMeButton extends StatefulWidget {
  final bool enabled; // your _readAloudEnabled
  final bool isPlaying; // _isPlayingAudio || _isSpeakingTts
  final VoidCallback onTap;

  const ReadToMeButton({
    super.key,
    required this.enabled,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<ReadToMeButton> createState() => _ReadToMeButtonState();
}

class _ReadToMeButtonState extends State<ReadToMeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(ReadToMeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.isPlaying != widget.isPlaying) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    // Pulse only when NOT enabled (invites tap).
    // Once enabled or playing, keep stable (calm).
    if (!widget.enabled && !widget.isPlaying) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_pulse.isAnimating) _pulse.stop();
      _pulse.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.enabled ? 'Stop' : 'Read to Me';
    final icon = widget.enabled ? Icons.stop_circle : Icons.volume_up_rounded;

    // Gentle idle pulse: 1.00 -> 1.03 scale
    final scale = 1.0 + (_pulse.value * 0.03);

    // Glow when playing
    final glow = widget.isPlaying;

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 180),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.medium,
        ),
        decoration: BoxDecoration(
          color: AppColors.accentCoral.withOpacity(widget.enabled ? 0.95 : 0.85),
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.large),
          onTap: widget.onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              if (widget.isPlaying) ...[
                const SizedBox(width: 10),
                const _DotWave(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DotWave extends StatefulWidget {
  const _DotWave();

  @override
  State<_DotWave> createState() => _DotWaveState();
}

class _DotWaveState extends State<_DotWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1
        double bump(double phase) {
          final x = (t + phase) % 1.0;
          return 0.6 + (x < 0.5 ? x : (1.0 - x)) * 0.8; // 0.6..1.0
        }

        return Row(
          children: [
            _dot(bump(0.0)),
            _dot(bump(0.2)),
            _dot(bump(0.4)),
          ],
        );
      },
    );
  }

  Widget _dot(double s) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(s),
        shape: BoxShape.circle,
      ),
    );
  }
}

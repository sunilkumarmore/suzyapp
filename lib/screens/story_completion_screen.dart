import 'package:flutter/material.dart';
import 'package:suzyapp/main.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';

class StoryCompletionArgs {
  final String storyId;
  final String storyTitle;

  const StoryCompletionArgs({
    required this.storyId,
    required this.storyTitle,
  });
}

class StoryCompletionScreen extends StatelessWidget {
  final StoryCompletionArgs args;

  const StoryCompletionScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.large),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                      color: Colors.black.withOpacity(0.10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _CelebrationStars(),
                    const SizedBox(height: AppSpacing.large),

                    const Text(
                      'You did it!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),

                    Text(
                      'Finished: ${args.storyTitle}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.large),

                    // Big kid-friendly actions
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.popUntil(context, (r) => r.isFirst); // back to Home
                        },
                        child: const Text('Back to Home'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                       onPressed: () {
  Navigator.pushNamedAndRemoveUntil(
    context,
    '/reader',
    (route) => route.isFirst, // keep Home below
    arguments: StoryReaderArgs(args.storyId, startPageIndex: 0),
  );
},
                        child: const Text('Read Again'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationStars extends StatefulWidget {
  const _CelebrationStars();

  @override
  State<_CelebrationStars> createState() => _CelebrationStarsState();
}

class _CelebrationStarsState extends State<_CelebrationStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value; // 0..1
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, -6 * t),
              child: Icon(Icons.star, size: 42, color: AppColors.primaryYellow),
            ),
            const SizedBox(width: 10),
            Transform.translate(
              offset: Offset(0, -10 * (1 - t)),
              child: Icon(Icons.auto_awesome, size: 54, color: AppColors.accentCoral),
            ),
            const SizedBox(width: 10),
            Transform.translate(
              offset: Offset(0, -6 * t),
              child: Icon(Icons.star, size: 42, color: AppColors.primaryBlue),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../design_system/app_breakpoints.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../design_system/app_typography.dart';
import '../main.dart';
import '../models/reading_progress.dart';
import '../repositories/progress_repository.dart';
import '../repositories/story_repository.dart';

class HomeScreen extends StatefulWidget {
  final StoryRepository storyRepository;
  final ProgressRepository progressRepository;

  const HomeScreen({
    super.key,
    required this.storyRepository,
    required this.progressRepository,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ReadingProgress? _progress;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final p = await widget.progressRepository.getLastProgress();
    if (!mounted) return;
    setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isTablet = w > AppBreakpoints.phoneMaxWidth;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(childName: 'Kiddo'),
              const SizedBox(height: AppSpacing.xlarge),

              // Continue tile only if progress exists
              if (_progress != null) ...[
                _BigTile(
                  title: 'Continue',
                  subtitle: 'Pick up where you left off',
                  color: AppColors.accentCoral,
                  icon: Icons.play_circle_fill,
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/reader',
                      arguments: StoryReaderArgs(
                        _progress!.storyId,
                        startPageIndex: _progress!.pageIndex,
                      ),
                    ).then((_) => _loadProgress());
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
              ],

              if (!isTablet) ...[
                _BigTile(
                  title: 'Story Library',
                  subtitle: 'Pick a new adventure',
                  color: AppColors.primaryBlue,
                  icon: Icons.menu_book,
                  onTap: () => Navigator.pushNamed(context, '/library')
                      .then((_) => _loadProgress()),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _BigTile(
                        title: 'Story Library',
                        subtitle: 'Pick a new adventure',
                        color: AppColors.primaryBlue,
                        icon: Icons.menu_book,
                        onTap: () => Navigator.pushNamed(context, '/library')
                            .then((_) => _loadProgress()),
                      ),
                    ),
                  ],
                ),
                Align(
  alignment: Alignment.centerRight,
  child: TextButton(
    onPressed: () => Navigator.pushNamed(context, '/parents'),
    child: const Text('Parents'),
  ),
),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String childName;
  const _Header({required this.childName});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 420;

        final greeting = Text(
          'Hi, $childName!\nReady for a new adventure?',
          style: AppTypography.headingLarge,
        );

        final mascot = Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.large),
          ),
          child: const Icon(Icons.pets, size: 48, color: AppColors.accentCoral),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              greeting,
              const SizedBox(height: AppSpacing.medium),
              Align(alignment: Alignment.centerRight, child: mascot),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: greeting),
            const SizedBox(width: AppSpacing.medium),
            mascot,
          ],
        );
      },
    );
  }
}

class _BigTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _BigTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: Container(
        height: 120,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.medium,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Row(
          children: [
            Icon(icon, size: 42, color: Colors.white),
            const SizedBox(width: AppSpacing.medium),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.tileTitle),
                  const SizedBox(height: AppSpacing.xsmall),
                  Text(subtitle, style: AppTypography.tileSubtitle),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 34, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

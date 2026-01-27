import 'package:flutter/material.dart';
import 'package:suzyapp/widgets/parent_gate_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/app_breakpoints.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../design_system/app_typography.dart';

import '../models/reading_progress.dart';
import '../repositories/progress_repository.dart';
import '../repositories/story_repository.dart';
import '../main.dart'; // StoryReaderArgs

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
  static const _kHomeTourSeen = 'home_tour_seen_v1';
  ReadingProgress? _progress;
  bool _showHomeTour = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _loadHomeTour();
  }

  Future<void> _loadProgress() async {
    // ✅ Use new API name
    final p = await widget.progressRepository.getReadingProgress();
    if (!mounted) return;
    setState(() => _progress = p);
  }

  Future<void> _loadHomeTour() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kHomeTourSeen) ?? false;
    if (!mounted) return;
    setState(() => _showHomeTour = !seen);
  }

  Future<void> _dismissHomeTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHomeTourSeen, true);
    if (!mounted) return;
    setState(() => _showHomeTour = false);
  }

  Future<void> _openParentSummary() async {
    final allowed = await showParentGate(context);
    if (!allowed) return;

    await Navigator.pushNamed(context, '/parent-summary');
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isTablet = w > AppBreakpoints.phoneMaxWidth;
    final parentBtn = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.large),
      onTap: _openParentSummary,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: AppColors.outline),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.pets, color: AppColors.textPrimary),
            Positioned(
              bottom: 8,
              right: 8,
              child: Icon(Icons.lock, size: 12, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.topRight, child: parentBtn),
                  const SizedBox(height: AppSpacing.small),
                  const _Header(childName: 'Kiddo'),
                  SizedBox(
                    height: isTablet ? AppSpacing.large : AppSpacing.medium,
                  ),

                  _BigTile(
                    title: 'Read Stories',
                    subtitle: '',
                    color: AppColors.tileBlue,
                    icon: Icons.menu_book,
                    onTap: () => Navigator.pushNamed(context, '/library')
                        .then((_) => _loadProgress()),
                  ),
                  const SizedBox(height: AppSpacing.medium),

                  _BigTile(
                    title: 'Make a Story',
                    subtitle: '',
                    color: AppColors.tileYellow,
                    icon: Icons.auto_stories,
                    onTap: () => Navigator.pushNamed(context, '/create'),
                  ),

                  const SizedBox(height: AppSpacing.medium),

                  _BigTile(
                    title: 'Coloring',
                    subtitle: '',
                    color: AppColors.tileBlue,
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFFF8A65),
                        Color(0xFFFFD54F),
                        Color(0xFF9CCC65),
                        Color(0xFF4DD0E1),
                        Color(0xFF9575CD),
                      ],
                    ),
                    icon: Icons.brush,
                    onTap: () => Navigator.pushNamed(context, '/coloring'),
                  ),

                  const SizedBox(height: AppSpacing.medium),

                  if (_progress != null && _progress!.storyId != kMakeAStoryDemoId) ...[
                    _BigTile(
                      title: 'Continue',
                      subtitle: '',
                      color: AppColors.accentCoral.withOpacity(0.18),
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
                  ],
                ],
              ),
            ),
          ),
          if (_showHomeTour)
            Positioned(
              top: AppSpacing.large,
              right: AppSpacing.large,
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 240),
                      padding: const EdgeInsets.all(AppSpacing.medium),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFEFA),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: AppColors.outline),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.record_voice_over,
                                size: 18,
                                color: AppColors.textPrimary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Parent Voice',
                                  style: AppTypography.tileTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xsmall),
                          const Text(
                            'Tap the paw to use Parent Voice for reading.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.small),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _dismissHomeTour,
                              child: const Text('Got it'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: -14,
                      top: 36,
                      child: Column(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFEFA),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.outline),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFEFA),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.outline),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String childName;
  const _Header({required this.childName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hi, $childName!', style: AppTypography.headingLarge),
        const SizedBox(height: AppSpacing.xsmall),
        Text(
          'Pick a story to begin.',
          style: AppTypography.headingSubtitle,
        ),
      ],
    );
  }
}

class _BigTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final Gradient? gradient;
  final IconData icon;
  final VoidCallback onTap;

  const _BigTile({
    required this.title,
    required this.subtitle,
    required this.color,
    this.gradient,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 750;
    final iconSize = isCompact ? 34.0 : 40.0;
    final titleStyle = AppTypography.tileTitle.copyWith(
      fontWeight: FontWeight.w800,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.large),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: isCompact ? AppSpacing.small : AppSpacing.medium,
        ),
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Row(
          children: [
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: Center(
                child: Icon(icon, size: iconSize, color: Colors.white),
              ),
            ),
            const SizedBox(width: AppSpacing.medium),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: titleStyle,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xsmall),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.tileSubtitle,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            const Icon(Icons.chevron_right, size: 30, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SmallTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 750;
    final isNarrow = MediaQuery.of(context).size.width < 360;
    final titleStyle = AppTypography.tileTitle.copyWith(
      fontSize: isNarrow ? 24 : 28,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.large),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: isCompact ? AppSpacing.xsmall : AppSpacing.small,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Center(
                child: Icon(icon, size: 24, color: AppColors.accentCoral),
              ),
            ),
            const SizedBox(width: AppSpacing.medium),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.tileSubtitle,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

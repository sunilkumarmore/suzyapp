import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  String _appVersionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _loadHomeTour();
    _loadVersionLabel();
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

  Future<void> _loadVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersionLabel = 'v${info.version}+${info.buildNumber}');
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
    final tourRight = (w - 300).clamp(8.0, AppSpacing.large + 64).toDouble();
    final tourMaxWidth = (w - tourRight - 16).clamp(190.0, 270.0).toDouble();
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
              top: AppSpacing.large + 6,
              right: tourRight,
              child: _HomeTourCloud(
                onDismiss: _dismissHomeTour,
                maxWidth: tourMaxWidth,
              ),
            ),
          if (_appVersionLabel.isNotEmpty)
            Positioned(
              right: AppSpacing.medium,
              bottom: AppSpacing.medium,
              child: IgnorePointer(
                child: Text(
                  _appVersionLabel,
                  style: AppTypography.tileSubtitle.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary.withOpacity(0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeTourCloud extends StatelessWidget {
  final VoidCallback onDismiss;
  final double maxWidth;

  const _HomeTourCloud({
    required this.onDismiss,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    const cloud = Color(0xFFFFFEFA);
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            decoration: BoxDecoration(
              color: cloud,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.outline),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.record_voice_over, size: 18, color: AppColors.textPrimary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Parent Voice',
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xsmall),
                const Text(
                  'Tap the paw to use Parent Voice for reading.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xsmall),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDismiss,
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            top: -10,
            child: _CloudBump(color: cloud, size: 26),
          ),
          Positioned(
            left: 54,
            top: -14,
            child: _CloudBump(color: cloud, size: 32),
          ),
          Positioned(
            right: 44,
            top: -11,
            child: _CloudBump(color: cloud, size: 28),
          ),
          Positioned(
            right: -16,
            top: 48,
            child: Transform.rotate(
              angle: 0.65,
              child: _CloudBump(color: cloud, size: 20),
            ),
          ),
          Positioned(
            right: -30,
            top: 62,
            child: Transform.rotate(
              angle: 0.65,
              child: _CloudBump(color: cloud, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudBump extends StatelessWidget {
  final Color color;
  final double size;

  const _CloudBump({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outline),
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

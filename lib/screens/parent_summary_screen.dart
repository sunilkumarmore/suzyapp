import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/reading_progress.dart';
import '../models/story_progress.dart';
import '../repositories/progress_repository.dart';

class ParentSummaryScreen extends StatelessWidget {
  final ProgressRepository progressRepository;

  const ParentSummaryScreen({super.key, required this.progressRepository});

  Future<_ParentSummaryVM> _load() async {
    final ReadingProgress? rp = await progressRepository.getReadingProgress();
    final List<StoryProgress> all = await progressRepository.getAllStoryProgress();

    final completed = all.where((p) => p.completed).length;
    final inProgress = all.where((p) => !p.completed).length;

    // Last read: prefer ReadingProgress timestamp if available
    final lastRead = rp?.updatedAt;

    return _ParentSummaryVM(
      completed: completed,
      inProgress: inProgress,
      lastRead: lastRead,
      totalTouched: all.length,
    );
  }

  String _formatDateTime(DateTime dt) {
    // Keep it simple for v1 (no intl dependency)
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d  $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Parent Summary'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: FutureBuilder<_ParentSummaryVM>(
          future: _load(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final vm = snap.data!;

            return ListView(
              children: [
                _Card(
                  title: 'Stories Completed',
                  value: vm.completed.toString(),
                  subtitle: 'Finished stories',
                ),
                const SizedBox(height: AppSpacing.medium),
                _Card(
                  title: 'Stories In Progress',
                  value: vm.inProgress.toString(),
                  subtitle: 'Started but not finished',
                ),
                const SizedBox(height: AppSpacing.medium),
                _Card(
                  title: 'Last Read',
                  value: vm.lastRead == null ? '—' : _formatDateTime(vm.lastRead!),
                  subtitle: 'Most recent reading activity',
                ),
                const SizedBox(height: AppSpacing.medium),
                _Card(
                  title: 'Stories Touched',
                  value: vm.totalTouched.toString(),
                  subtitle: 'Unique stories opened',
                ),
                const SizedBox(height: AppSpacing.large),
                Text(
                  'Note: This is a lightweight v1 summary. No personal data is collected.',
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.9)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ParentSummaryVM {
  final int completed;
  final int inProgress;
  final int totalTouched;
  final DateTime? lastRead;

  _ParentSummaryVM({
    required this.completed,
    required this.inProgress,
    required this.totalTouched,
    required this.lastRead,
  });
}

class _Card extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _Card({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: AppSpacing.xsmall),
              Text(subtitle, style: TextStyle(color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(width: AppSpacing.medium),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

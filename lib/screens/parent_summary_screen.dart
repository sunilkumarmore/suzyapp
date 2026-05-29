import 'package:flutter/material.dart';
import 'package:suzyapp/widgets/parent_gate_dialog.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/reading_progress.dart';
import '../models/story_progress.dart';
import '../repositories/progress_repository.dart';
import '../utils/child_name.dart';

class ParentSummaryScreen extends StatefulWidget {
  final ProgressRepository progressRepository;

  const ParentSummaryScreen({super.key, required this.progressRepository});

  @override
  State<ParentSummaryScreen> createState() => _ParentSummaryScreenState();
}

class _ParentSummaryScreenState extends State<ParentSummaryScreen> {
  late Future<_ParentSummaryVM> _future;
  String _childName = '';

  @override
  void initState() {
    super.initState();
    loadChildName().then((name) {
      if (mounted) setState(() => _childName = name ?? '');
    });

    // 🔐 Hard gate: prevents route deep-link access on web
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final allowed = await showParentGate(context);
      if (!allowed && mounted) {
        Navigator.pop(context);
        return;
      }
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    });

    // placeholder until gate passes
    _future = Future<_ParentSummaryVM>.value(
      _ParentSummaryVM(completed: 0, inProgress: 0, totalTouched: 0, lastRead: null),
    );
  }

  Future<_ParentSummaryVM> _load() async {
    final ReadingProgress? rp = await widget.progressRepository.getReadingProgress();
    final List<StoryProgress> all = await widget.progressRepository.getAllStoryProgress();

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

  Future<void> _editChildName() async {
    final controller = TextEditingController(text: _childName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Child's name"),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: 'e.g. Lily',
            counterText: '',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty) {
      await saveChildName(result);
      if (!mounted) return;
      setState(() => _childName = result);
    }
  }

  Widget _buildChildNameCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.outline),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.child_care, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Child's Name",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _childName.isEmpty ? 'Not set' : _childName,
                  style: TextStyle(
                    color: _childName.isEmpty
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: _editChildName,
            tooltip: 'Edit name',
          ),
        ],
      ),
    );
  }

  Widget _buildParentVoiceCard(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.large),
          onTap: () => Navigator.pushNamed(context, '/parent-voice'),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.large),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(color: AppColors.outline),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.tileBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.record_voice_over,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.medium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Use Parent Voice',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: AppSpacing.xsmall),
                      Text(
                        'Let your child hear you during stories.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
        Positioned(
          top: -10,
          right: 14,
          child: _NewBadge(),
        ),
      ],
    );
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
          future: _future,
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
                _buildChildNameCard(),
                const SizedBox(height: AppSpacing.medium),
                _buildParentVoiceCard(context),
                const SizedBox(height: AppSpacing.large),
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
                const SizedBox(height: AppSpacing.large),
                OutlinedButton(
                  onPressed: () => Navigator.pushNamed(context, '/privacy'),
                  child: const Text('Privacy Policy'),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: AppSpacing.xsmall),
                Text(subtitle, style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
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

class _NewBadge extends StatefulWidget {
  const _NewBadge();

  @override
  State<_NewBadge> createState() => _NewBadgeState();
}

class _NewBadgeState extends State<_NewBadge> {
  bool _pulsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _pulsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedScale(
        scale: _pulsed ? 1.05 : 0.95,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        onEnd: () {
          if (mounted) setState(() => _pulsed = !_pulsed);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.choiceRed,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Text(
            'NEW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

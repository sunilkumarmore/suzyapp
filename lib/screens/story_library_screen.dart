import 'package:flutter/material.dart';
import 'package:suzyapp/models/story_progress.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../main.dart'; // StoryReaderArgs
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../repositories/progress_repository.dart';
import '../repositories/story_repository.dart';

class StoryLibraryScreen extends StatefulWidget {
  final StoryRepository storyRepository;
  final ProgressRepository progressRepository;

  const StoryLibraryScreen({
    super.key,
    required this.storyRepository,
    required this.progressRepository,
  });

  @override
  State<StoryLibraryScreen> createState() => _StoryLibraryScreenState();
}

class _StoryLibraryScreenState extends State<StoryLibraryScreen> {
  String _search = '';
  String? _language;   // null = all
  String? _ageBand; // null = all

Map<String, StoryProgress> _progressByStoryId = {};
  late Future<List<Story>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadProgress();
  }

 Future<void> _loadProgress() async {
  final list = await widget.progressRepository.getAllStoryProgress();
  if (!mounted) return;
  setState(() {
    _progressByStoryId = { for (final p in list) p.storyId : p };
  });
}

  Future<List<Story>> _load() {
    return widget.storyRepository.listStories(
      query: StoryQuery(
         searchText: _search,
    language: _language,
    ageBand: _ageBand,
      ),
    );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  int _columnsForWidth(double w) {
    if (w < 520) return 2;
    if (w < 900) return 3;
    if (w < 1200) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = _columnsForWidth(w);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Story Library'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          children: [
            _SearchBar(
              initial: _search,
              onChanged: (v) {
                _search = v;
                _refresh();
              },
            ),
            const SizedBox(height: AppSpacing.medium),
            _FiltersRow(
              language: _language,
              ageBand: _ageBand,
         onLanguage: (v) {
  setState(() {
    _language = v;
    _future = _load();
  });
},
onAgeband: (v) {
  setState(() {
    _ageBand = v;
    _future = _load();
  });
},

          onClear: () {
  setState(() {
    _search = '';
    _language = null;
    _ageBand = null;
    _future = _load();
  });
},
            ),
            const SizedBox(height: AppSpacing.large),
            Expanded(
              child: FutureBuilder<List<Story>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }

                  final stories = snap.data ?? [];
                  if (stories.isEmpty) {
                    return const Center(child: Text('No stories found.'));
                  }

                  return GridView.builder(
                    itemCount: stories.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: AppSpacing.medium,
                      mainAxisSpacing: AppSpacing.medium,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (context, i) {
                      final s = stories[i];
                    //  final inProgress = _progress != null && _progress!.storyId == s.id;
                    final sp = _progressByStoryId[s.id];
final inProgress = sp != null && !sp.completed;
final startIndex = sp?.lastPageIndex;

                      return _StoryCard(
                        story: s,
                        inProgress: inProgress,
                        onTap: () async {
                        await Navigator.pushNamed(
  context,
  '/reader',
  arguments: StoryReaderArgs(
    s.id,
    startPageIndex: inProgress ? startIndex : null,
  ),
);
await _loadProgress();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.initial, required this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: 'Search stories…',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _FiltersRow extends StatelessWidget {
  final String? language;
  final String? ageBand;
  final ValueChanged<String?> onLanguage;
  final ValueChanged<String?> onAgeband;
  final VoidCallback onClear;

  const _FiltersRow({
    required this.language,
    required this.onLanguage,
    required this.onAgeband,
    required this.onClear,
     required this.ageBand,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.small,
      runSpacing: AppSpacing.small,
      children: [
        _ChipDropdown(
          label: 'Language',
          value: language,
          items: const [
            DropdownMenuItem(value: null, child: Text('All')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'te', child: Text('Telugu')),
            DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
          ],
          onChanged: onLanguage,
        ),
      _ChipDropdown(
  label: 'Age',
  value: ageBand,
  items: const [
    DropdownMenuItem(value: null, child: Text('All')),
    DropdownMenuItem(value: '2-3', child: Text('2–3')),
    DropdownMenuItem(value: '4-5', child: Text('4–5')),
    DropdownMenuItem(value: '6-7', child: Text('6–7')),
  ],
  onChanged: onAgeband,
),

        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset'),
        )
      ],
    );
  }
}

class _ChipDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String?>> items;
  final ValueChanged<String?> onChanged;

  const _ChipDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            offset: const Offset(0, 3),
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          hint: Text(label),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  final Story story;
  final bool inProgress;
  final VoidCallback onTap;

  const _StoryCard({
    required this.story,
    required this.inProgress,
    required this.onTap,
  });

  Color _accentFor(Story s) {
    switch (s.language) {
      case 'te':
        return AppColors.primaryYellow;
      case 'mixed':
        return AppColors.accentCoral;
      default:
        return AppColors.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(story);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.18),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.large),
                  topRight: Radius.circular(AppRadius.large),
                ),
              ),
              child: Stack(
                children: [
                  Center(child: Icon(Icons.image, size: 48, color: accent)),
                 if (inProgress)
  Positioned(
    top: 10,
    left: 10,
    child: _Badge(text: 'Continue', color: AppColors.accentCoral),
  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Wrap(
                    spacing: AppSpacing.small,
                    children: [
                      _Badge(text: story.ageBand, color: accent),
                      _Badge(
                        text: story.language.toUpperCase(),
                        color: AppColors.textSecondary,
                        fill: AppColors.textSecondary.withOpacity(0.12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? fill;

  const _Badge({required this.text, required this.color, this.fill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill ?? color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

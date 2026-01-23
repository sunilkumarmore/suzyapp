import 'package:flutter/material.dart';
import 'package:suzyapp/models/adventure_template.dart';
import 'package:suzyapp/utils/asset_path.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/story.dart';
import '../repositories/adventure_template_repository.dart';
import '../repositories/story_repository.dart';
import '../repositories/progress_repository.dart';
import '../widgets/choice_tile.dart';
import 'story_reader_screen.dart';

class CreateAdventureScreen extends StatefulWidget {
  final AdventureTemplateRepository templateRepository;
  final ProgressRepository progressRepository;

  const CreateAdventureScreen({
    super.key,
    required this.templateRepository,
    required this.progressRepository,
  });

  @override
  State<CreateAdventureScreen> createState() => _CreateAdventureScreenState();
}

class _CreateAdventureScreenState extends State<CreateAdventureScreen> {
  late Future<List<AdventureTemplate>> _future;

  AdventureTemplate? _template;

  @Deprecated('Unused in picker flow')
  int _slotIndex = 0;
  @Deprecated('Unused in picker flow')
  final Map<String, AdventureChoice> _selected = {};

  bool _locked = false;
  @Deprecated('Unused in picker flow')
  int? _selectedIndex;
  @Deprecated('Unused in picker flow')
  int? _sparkleIndex;

  @override
  void initState() {
    super.initState();
    _future = widget.templateRepository.loadTemplates();
  }

  // ---- SLOT ORDER (place first, then hero, etc.) ----
  static const List<String> _preferredSlotOrder = [
    'place',
    'hero',
    'friend',
    'object',
    'feeling',
  ];

  @Deprecated('Unused in picker flow')
  List<String> _orderedSlots(AdventureTemplate t) {
    final slots = List<String>.from(t.slots);

    // Keep only those that exist, in preferred order.
    final ordered = <String>[];
    for (final s in _preferredSlotOrder) {
      if (slots.contains(s)) ordered.add(s);
    }

    // Append any unknown/custom slots at the end (preserve template order).
    for (final s in slots) {
      if (!ordered.contains(s)) ordered.add(s);
    }

    return ordered;
  }

  @Deprecated('Unused in picker flow')
  void _resetFlow(AdventureTemplate t) {
    setState(() {
      _template = t;
      _slotIndex = 0;
      _selected.clear();
      _locked = false;
      _selectedIndex = null;
      _sparkleIndex = null;
    });
  }

  String _tokenValue(String slot) {
    final c = _selected[slot];
    if (c == null) return '';
    // Use label as the token value for the story text
    return c.label;
  }

  String _render(String templateText) {
    final t = _template;
    if (t == null) return templateText;

    var out = templateText;
    for (final slot in t.slots) {
      out = out.replaceAll('{${slot}}', _tokenValue(slot));
    }
    return out;
  }

  Story _buildCreatedStory(AdventureTemplate t) {
    final pages = <StoryPage>[];

    for (var i = 0; i < t.pages.length; i++) {
      final pt = t.pages[i];
      pages.add(
        StoryPage(
          index: i,
          text: _render(pt.text),
          imageAsset: pt.imageAsset,
          choices: pt.choices
              .map((c) => StoryChoice(
                    id: c.id,
                    label: c.label,
                    nextPageIndex: c.nextPageIndex,
                    imageAsset: c.imageAsset,
                  ))
              .toList(),
        ),
      );
    }

    return Story(
      id: 'created_${DateTime.now().millisecondsSinceEpoch}',
      title: t.title,
      language: 'en',
      ageBand: t.ageBand,
      pages: pages,
      coverAsset: t.coverAsset,
    );
  }

  Future<void> _openReader(Story story) async {
    final repo = _InMemoryStoryRepository(story);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryReaderScreen(
          storyRepository: repo,
          progressRepository: widget.progressRepository,
          storyId: story.id,
          startPageIndex: 0,
        ),
      ),
    );
  }

  @Deprecated('Unused in picker flow')
  Future<void> _onPickOption(AdventureChoice option) async {
    if (_locked) return;
    final t = _template;
    if (t == null) return;

    final slots = _orderedSlots(t);
    final currentSlot = slots[_slotIndex];

    setState(() => _selected[currentSlot] = option);

    if (_slotIndex < slots.length - 1) {
      setState(() {
        _slotIndex++;
        _selectedIndex = null;
      });
    } else {
      final story = _buildCreatedStory(t);
      _openReader(story);
    }
  }

  @Deprecated('Unused in picker flow')
  String _slotTitle(String slot) {
    switch (slot) {
      case 'place':
        return 'Pick a place';
      case 'hero':
        return 'Pick a hero';
      case 'friend':
        return 'Pick a friend';
      case 'object':
        return 'Pick a thing';
      case 'feeling':
        return 'Pick a feeling';
      default:
        return 'Pick one';
    }
  }

  // Big preview image at top:
  // - If user already picked something for current slot, preview that
  // - Else preview template cover (if any)
  // - Else show a soft placeholder
  @Deprecated('Unused in picker flow')
  Widget _buildScenePreview({
    required AdventureTemplate t,
    required String currentSlot,
  }) {
    final picked = _selected[currentSlot];
    final pickedImg = AssetPath.normalize(picked?.imageAsset);
    final cover = AssetPath.normalize(t.coverAsset);

    final previewAsset = pickedImg.isNotEmpty ? pickedImg : cover;

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          color: AppColors.surface,
          child: previewAsset.isNotEmpty
              ? Image.asset(
                  previewAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _previewPlaceholder(),
                )
              : _previewPlaceholder(),
        ),
      ),
    );
  }

  @Deprecated('Unused in picker flow')
  Widget _previewPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Text(
          'Scene preview',
          style: TextStyle(
            color: AppColors.textSecondary.withOpacity(0.8),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdventureTemplate>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('Template error: ${snap.error}')));
        }

        final templates = snap.data ?? [];
        if (templates.isEmpty) {
          return const Scaffold(body: Center(child: Text('No templates found.')));
        }

        if (_template == null) {
          return _AdventurePicker(
            templates: templates,
            onPick: (t) async {
              setState(() => _template = t);

              final story = _buildCreatedStory(t);
              await _openReader(story);

              if (mounted) setState(() => _template = null);
            },
          );
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

/// Minimal in-memory StoryRepository for created story reading.
/// Keeps everything local and avoids touching your main repo.
class _InMemoryStoryRepository implements StoryRepository {
  final Story _story;

  _InMemoryStoryRepository(this._story);

  @override
  Future<Story> getStoryById(String id) async {
    if (id == _story.id) return _story;
    throw Exception('Story not found: $id');
  }

  @override
  Future<List<Story>> listStories({required StoryQuery query}) async {
    // Created story does not show in library for v1.
    return const [];
  }
}

class _AdventurePicker extends StatelessWidget {
  final List<AdventureTemplate> templates;
  final ValueChanged<AdventureTemplate> onPick;

  const _AdventurePicker({required this.templates, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pick an Adventure'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: GridView.builder(
          itemCount: templates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.large,
            crossAxisSpacing: AppSpacing.large,
            childAspectRatio: 0.75,
          ),
          itemBuilder: (context, i) {
            final t = templates[i];
            final cover = AssetPath.normalize(t.coverAsset);

            return ChoiceTile(
              label: t.title,
              imageAsset: cover,
              selected: false,
              showSparkle: false,
              disabled: false,
              onTap: () => onPick(t),
            );
          },
        ),
      ),
    );
  }
}

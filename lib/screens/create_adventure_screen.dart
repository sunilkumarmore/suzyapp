import 'package:flutter/material.dart';
import 'package:suzyapp/models/adventure_template.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/story.dart';
import '../repositories/adventure_template_repository.dart';
import '../repositories/story_repository.dart';
import '../repositories/progress_repository.dart';
import 'parent_gate_screen.dart';
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
  bool _unlocked = false;
  late Future<List<AdventureTemplate>> _future;

  AdventureTemplate? _template;
  int _slotIndex = 0;
  final Map<String, AdventureChoice> _selected = {};

  @override
  void initState() {
    super.initState();
    _future = widget.templateRepository.loadTemplates();
  }

  void _resetFlow(AdventureTemplate t) {
    setState(() {
      _template = t;
      _slotIndex = 0;
      _selected.clear();
    });
  }

  String _tokenValue(String slot) {
    final c = _selected[slot];
    if (c == null) return '';
    // Use label as the token value for the story text
    return c.label;
  }

  String _render(String templateText) {
    var out = templateText;
    for (final slot in _template!.slots) {
      out = out.replaceAll('{${slot}}', _tokenValue(slot));
    }
    return out;
  }

  Story _buildCreatedStory(AdventureTemplate t) {
    final pages = <StoryPage>[];
    for (var i = 0; i < t.pages.length; i++) {
      pages.add(StoryPage(
        index: i,
        text: _render(t.pages[i].text),
        choices: const [],
      ));
    }

    return Story(
      id: 'created_${DateTime.now().millisecondsSinceEpoch}',
      title: t.title,
      language: 'en',
      ageBand: t.ageBand,
      pages: pages,
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

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return ParentGateScreen(onUnlocked: () => setState(() => _unlocked = true));
    }

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

        // Pick first template (v1). Later we can add a template picker UI.
        _template ??= templates.first;
        final t = _template!;

        final slots = t.slots;
        final currentSlot = slots[_slotIndex];
        final options = t.choices[currentSlot] ?? const <AdventureChoice>[];

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Create a Story'),
            backgroundColor: AppColors.background,
            elevation: 0,
            actions: [
              TextButton(
                onPressed: () => _resetFlow(t),
                child: const Text('Reset'),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.small),

                Row(
                  children: [
                    Text('Step ${_slotIndex + 1} of ${slots.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: AppSpacing.medium),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (_slotIndex + 1) / slots.length,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.large),

                Text(
                  _slotTitle(currentSlot),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.medium),

                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.medium,
                      crossAxisSpacing: AppSpacing.medium,
                      childAspectRatio: 1.3,
                    ),
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final c = options[i];
                      final selected = _selected[currentSlot]?.id == c.id;

                      return InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.large),
                        onTap: () {
                          setState(() => _selected[currentSlot] = c);

                          // auto-advance
                          if (_slotIndex < slots.length - 1) {
                            setState(() => _slotIndex++);
                          } else {
                            // done -> build story & open reader
                            final story = _buildCreatedStory(t);
                            _openReader(story);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.large),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.surface : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.large),
                            border: Border.all(
                              width: selected ? 3 : 1,
                              color: selected ? Colors.black : Colors.black12,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(c.emoji, style: const TextStyle(fontSize: 42)),
                              const SizedBox(height: AppSpacing.small),
                              Text(
                                c.label,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: AppSpacing.medium),

                // Back button for parents (optional)
                Row(
                  children: [
                    TextButton(
                      onPressed: _slotIndex > 0
                          ? () => setState(() => _slotIndex--)
                          : null,
                      child: const Text('Back'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _openReader(_buildCreatedStory(t)),
                      child: const Text('Preview Now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _slotTitle(String slot) {
    switch (slot) {
      case 'hero':
        return 'Pick a hero';
      case 'place':
        return 'Pick a place';
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

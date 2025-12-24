import 'package:flutter/material.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../models/story_progress.dart';
import '../repositories/progress_repository.dart';
import '../repositories/story_repository.dart';
import 'story_completion_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';

class StoryReaderScreen extends StatefulWidget {
  final StoryRepository storyRepository;
  final ProgressRepository progressRepository;
  final String storyId;
  final int? startPageIndex;

  const StoryReaderScreen({
    super.key,
    required this.storyRepository,
    required this.progressRepository,
    required this.storyId,
    this.startPageIndex,
  });

  @override
  State<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends State<StoryReaderScreen> {
  late Future<Story> _future;
  bool _completionShown = false;
  int _pageIndex = 0;
  Story? _storyCache;
  final FlutterTts _tts = FlutterTts();
bool _isSpeaking = false;

Future<void> _initTts() async {
  // Speaking state callbacks (works on most platforms)
  _tts.setStartHandler(() => setState(() => _isSpeaking = true));
  _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
  _tts.setCancelHandler(() => setState(() => _isSpeaking = false));
  _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));

  await _tts.setSpeechRate(0.45); // slower for kids
  await _tts.setPitch(1.05);
  await _tts.setVolume(1.0);
}

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.startPageIndex ?? 0;
    _future = widget.storyRepository.getStoryById(widget.storyId);
     _initTts();
  }

@override
void dispose() {
  _tts.stop();
  super.dispose();
}
  int _imageFlexFor(String ageBand, String text) {
    final len = text.trim().length;

    int shortMax;
    int mediumMax;

    switch (ageBand) {
      case '2-3':
        shortMax = 45;
        mediumMax = 90;
        break;
      case '4-5':
        shortMax = 90;
        mediumMax = 180;
        break;
      default: // '6-7'
        shortMax = 140;
        mediumMax = 260;
    }

    if (len <= shortMax) return 6; // image dominates
    if (len <= mediumMax) return 5; // balanced
    return 4; // text needs more room
  }

  Future<void> _saveReadingProgress() async {
    final story = _storyCache;
    if (story == null || story.pages.isEmpty) return;

    final int clamped = (_pageIndex.clamp(0, story.pages.length - 1) as int);

    // Keep backward-compat call, since your ProgressRepository supports it
    await widget.progressRepository.saveProgress(
      ReadingProgress(
        storyId: widget.storyId,
        pageIndex: clamped,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _saveStoryProgress() async {
    final story = _storyCache;
    if (story == null || story.pages.isEmpty) return;

    final int clamped = (_pageIndex.clamp(0, story.pages.length - 1) as int);
    final bool isCompleted = clamped == story.pages.length - 1;

    await widget.progressRepository.saveStoryProgress(
      StoryProgress(
        storyId: widget.storyId,
        lastPageIndex: clamped,
        completed: isCompleted,
        lastOpenedAt: DateTime.now(),
      ),
    );

    if (isCompleted && !_completionShown && mounted) {
      _completionShown = true;
      Navigator.pushNamed(
        context,
        '/complete',
        arguments: StoryCompletionArgs(
          storyId: widget.storyId,
          storyTitle: story.title,
        ),
      );
    }
  }

  Future<void> _setPage(int newIndex) async {
    await _tts.stop(); // ✅ important
  setState(() => _pageIndex = newIndex);
  await _saveReadingProgress();
  await _saveStoryProgress();
  }

  Widget _buildPageImage(StoryPage page) {
    final imgAsset = page.imageAsset;
    final imgUrl = page.imageUrl;

    if (imgAsset != null && imgAsset.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Image.asset(
          imgAsset,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    if (imgUrl != null && imgUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Image.network(
          imgUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return const Center(child: Icon(Icons.image, size: 56));
  }

Future<void> _speakCurrentPage(Story story, StoryPage page) async {
  // Stop anything already speaking
  await _tts.stop();

  // Pick a language code (basic)
  final lang = story.language.toLowerCase();
  if (lang == 'te') {
    await _tts.setLanguage('te-IN'); // Telugu
  } else {
    await _tts.setLanguage('en-US'); // English default
  }

  // For mixed, you can keep en-US for v1, or detect script later
  if (lang == 'mixed') {
    await _tts.setLanguage('en-US');
  }

  await _tts.speak(page.text);
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
   appBar: AppBar(
  title: const Text('Read'),
  backgroundColor: AppColors.background,
  elevation: 0,
  actions: [
    IconButton(
      tooltip: _isSpeaking ? 'Stop' : 'Read aloud',
      icon: Icon(_isSpeaking ? Icons.stop_circle : Icons.volume_up),
      onPressed: () async {
        final story = _storyCache;
        if (story == null) return;
        final page = story.pages[_pageIndex];

        if (_isSpeaking) {
          await _tts.stop();
        } else {
          await _speakCurrentPage(story, page);
        }
      },
    ),
  ],
),
      body: FutureBuilder<Story>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final story = snap.data!;
          _storyCache = story;

          final int safeIndex =
              (_pageIndex.clamp(0, story.pages.length - 1) as int);
          if (safeIndex != _pageIndex) _pageIndex = safeIndex;

          final page = story.pages[_pageIndex];

          final imageFlex = _imageFlexFor(story.ageBand, page.text);
          final textFlex = 10 - imageFlex;

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),

                Expanded(
                  flex: imageFlex,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                    ),
                    child: _buildPageImage(page),
                  ),
                ),

                const SizedBox(height: AppSpacing.medium),

                Expanded(
                  flex: textFlex,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.large),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        page.text,
                        style: TextStyle(
                          fontSize: story.ageBand == '2-3' ? 18 : 20,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.medium),

                if (page.hasChoices) ...[
                  const Text(
                    'What should happen next?',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Wrap(
                    spacing: AppSpacing.small,
                    runSpacing: AppSpacing.small,
                    children: page.choices.map((c) {
                      return ElevatedButton(
                        onPressed: () => _setPage(c.nextPageIndex),
                        child: Text(c.label),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.small),
                ],

                Row(
                  children: [
                    IconButton(
                      onPressed:
                          _pageIndex > 0 ? () => _setPage(_pageIndex - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (_pageIndex + 1) / story.pages.length,
                      ),
                    ),
                    IconButton(
                      onPressed: _pageIndex < story.pages.length - 1
                          ? () => _setPage(_pageIndex + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


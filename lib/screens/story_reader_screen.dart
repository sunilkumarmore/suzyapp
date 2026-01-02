import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../models/story_progress.dart';
import '../repositories/progress_repository.dart';
import '../repositories/story_repository.dart';
import '../widgets/adventure_scene.dart';
import 'story_completion_screen.dart';

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
  Story? _storyCache;

  int _pageIndex = 0;
  bool _completionShown = false;

  // Read aloud state
  bool _readAloudEnabled = false;
  bool _isPlayingAudio = false;
  bool _isSpeakingTts = false;

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();

    _pageIndex = widget.startPageIndex ?? 0;
    _future = widget.storyRepository.getStoryById(widget.storyId);

    // Track audio state
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlayingAudio = state.playing);
    });

    // Track TTS state
    _tts.setStartHandler(() => mounted ? setState(() => _isSpeakingTts = true) : null);
    _tts.setCompletionHandler(() => mounted ? setState(() => _isSpeakingTts = false) : null);
    _tts.setCancelHandler(() => mounted ? setState(() => _isSpeakingTts = false) : null);
    _tts.setErrorHandler((_) => mounted ? setState(() => _isSpeakingTts = false) : null);

    // Kid-friendly defaults
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.05);
    _tts.setVolume(1.0);
  }

  @override
  void dispose() {
    _stopAllAudio(); // stop before dispose
    _player.dispose();
    super.dispose();
  }

  // ---------- Audio helpers ----------

  Future<void> _stopAllAudio() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isPlayingAudio = false;
      _isSpeakingTts = false;
    });
  }

  Future<void> _playReadAloud(Story story, StoryPage page) async {
    await _stopAllAudio();

    // 1) URL first (primary)
    final url = page.audioUrl;
    if (url != null && url.trim().isNotEmpty) {
      try {
        if (kIsWeb) {
          await _player.setUrl(url);
        } else {
          final file = await DefaultCacheManager().getSingleFile(url);
          await _player.setFilePath(file.path);
        }
        await _player.play();
        return; // ✅ do not fall through
      } catch (_) {
        // fall through to asset/TTS
      }
    }

    // 2) Asset second (offline pack)
    final asset = page.audioAsset;
    if (asset != null && asset.trim().isNotEmpty) {
      try {
        await _player.setAsset(asset);
        await _player.play();
        return; // ✅ do not fall through
      } catch (_) {
        // fall through to TTS
      }
    }

    // 3) TTS fallback
    final lang = story.language.toLowerCase();
    if (lang == 'te') {
      await _tts.setLanguage('te-IN');
    } else {
      await _tts.setLanguage('en-US');
    }
    // for mixed in v1, keep en-US
    await _tts.speak(page.text);
  }

  // ---------- Progress helpers ----------

  Future<void> _saveReadingProgress() async {
    final story = _storyCache;
    if (story == null || story.pages.isEmpty) return;

    final int clamped = (_pageIndex.clamp(0, story.pages.length - 1) as int);

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
      await _stopAllAudio();
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
    final story = _storyCache;
    if (story == null) return;

    // Stop current audio before switching pages
    await _stopAllAudio();

    setState(() => _pageIndex = newIndex);

    await _saveReadingProgress();
    await _saveStoryProgress();

    // Auto read if enabled
    if (_readAloudEnabled) {
      final page = story.pages[_pageIndex];
      await _playReadAloud(story, page);
    }
  }

  // ---------- Layout helpers ----------

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

    if (len <= shortMax) return 6;
    if (len <= mediumMax) return 5;
    return 4;
  }

  // Basic mapping from existing StoryPage fields (imageAsset/imageUrl) to scene.
  // If you later add heroAsset/backgroundAsset/etc to StoryPage, wire them here.
  Widget _buildSceneOrImage(StoryPage page) {
    // If you only have a single illustration per page, use it as background.
    // For generated adventures, you’ll supply background/hero/friend/object/emotion.
    final bg = page.imageAsset;

    if (bg != null && bg.isNotEmpty) {
      return AdventureScene(
        backgroundAsset: bg,
        // heroAsset/friendAsset/objectAsset/emotionEmoji can be added later
        emotionEmoji: null,
      );
    }

    final url = page.imageUrl;
    if (url != null && url.isNotEmpty) {
      // AdventureScene expects assets; if you want network backgrounds later, we can extend it.
      // For now, fallback to Image.network.
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Image.network(url, fit: BoxFit.cover),
      );
    }

    return const Center(child: Icon(Icons.image, size: 56));
  }

  // ---------- UI ----------

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
            tooltip: _readAloudEnabled ? 'Read aloud: On' : 'Read aloud: Off',
            icon: Icon(_readAloudEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () async {
              final story = _storyCache;
              if (story == null) return;

              final toggledOn = !_readAloudEnabled;
              setState(() => _readAloudEnabled = toggledOn);

              if (toggledOn) {
                final page = story.pages[_pageIndex];
                await _playReadAloud(story, page);
              } else {
                await _stopAllAudio();
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

          final int safeIndex = (_pageIndex.clamp(0, story.pages.length - 1) as int);
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
                  child: AdventureScene(
  backgroundAsset: page.backgroundAsset ?? page.imageAsset,
  heroAsset: page.heroAsset,
  friendAsset: page.friendAsset,
  objectAsset: page.objectAsset,
  emotionEmoji: page.emotionEmoji,
),
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
                      onPressed: _pageIndex > 0 ? () => _setPage(_pageIndex - 1) : null,
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

                if (_isPlayingAudio || _isSpeakingTts) ...[
                  const SizedBox(height: AppSpacing.small),
                  Row(
                    children: const [
                      Icon(Icons.graphic_eq, size: 18),
                      SizedBox(width: 8),
                      Text('Reading aloud…'),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

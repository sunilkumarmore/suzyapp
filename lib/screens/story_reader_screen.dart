import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:suzyapp/Services/parent_voice_service.dart';
import 'package:suzyapp/utils/asset_path.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../models/story_progress.dart';
import '../models/parent_voice_settings.dart';
import '../repositories/progress_repository.dart';
import '../repositories/story_repository.dart';
import '../widgets/adventure_scene.dart';
import '../widgets/choice_tile.dart';
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

  late final ParentVoiceService _parentVoiceService;
  late final PageController _pageController;
  bool _pageControllerReady = false;

  bool _parentVoiceEnabled = false;
  String _parentVoiceId = '';
  Map<String, dynamic> _elevenlabsSettings = ParentVoiceSettings.defaults().elevenlabsSettings;

  int _pageIndex = 0;
  bool _completionShown = false;

  // Runtime path: holds REAL page indices we allow the user to see
  List<int> _path = [];
  int _pathPos = 0;

  // sparkle overlay when a choice is tapped
  bool _showChoiceSparkle = false;

  // Read aloud state
  bool _readAloudEnabled = false;
  bool _isPlayingAudio = false;
  bool _isSpeakingTts = false;

  // Hardening flags (prevents re-entry + repeated failures)
  bool _isReadAloudBusy = false;
  bool _parentVoiceDegraded = false; // once true, skip parent voice for this session

  bool _swipeHintSeen = false; // show hint only once per install/session
  bool _choiceLocked = false;
  int? _selectedChoiceIdx;
  int? _sparkleChoiceIdx;

  final AudioPlayer _player = AudioPlayer();
 // final AudioPlayer _sfxPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();

    _pageIndex = widget.startPageIndex ?? 0;
    _future = widget.storyRepository.getStoryById(widget.storyId);

    _parentVoiceService = ParentVoiceService(
      generateEndpoint: 'https://us-central1-suzyapp.cloudfunctions.net/generateNarration',
    );

    _loadParentVoiceSettings(); // loads toggle + voiceId

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

    _autoDismissSwipeHint();
  }

  @override
  void dispose() {
    _stopAllAudio(); // stop before dispose
    _player.dispose();
   // _sfxPlayer.dispose();
    if (_pageControllerReady) {
      _pageController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadParentVoiceSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (kDebugMode) {
      debugPrint('AUTH user=$user uid=${user?.uid} email=${user?.email}');
    }
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.doc('users/${user.uid}/settings/audio').get();

    if (!mounted) return;

    if (!doc.exists) {
      setState(() {
        _parentVoiceEnabled = false;
        _parentVoiceId = '';
      });
      return;
    }

    final data = doc.data()!;
    setState(() {
      final enabledRaw = data['parentVoiceEnabled'];
      _parentVoiceEnabled = enabledRaw is bool
          ? enabledRaw
          : (enabledRaw is String ? enabledRaw.toLowerCase().trim() == 'true' : false);

      final voiceRaw = data['elevenVoiceId'];
      _parentVoiceId = (voiceRaw is String) ? voiceRaw.trim() : '';

      final rawSettings = data['elevenlabsSettings'];
      _elevenlabsSettings = rawSettings is Map
          ? Map<String, dynamic>.from(rawSettings)
          : ParentVoiceSettings.defaults().elevenlabsSettings;
    });

    if (kDebugMode) {
      debugPrint(
        'ParentVoice settings loaded: enabled=$_parentVoiceEnabled voiceId=$_parentVoiceId',
      );
    }
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

  Future<void> _playUrl(String url) async {
    if (kIsWeb) {
      await _player.setUrl(url);
    } else {
      final file = await DefaultCacheManager().getSingleFile(url);
      await _player.setFilePath(file.path);
    }
    await _player.play();
  }

  String _langForBackend(String storyLang) {
    final l = storyLang.toLowerCase().trim();
    if (l == 'te') return 'te';
    return 'en'; // includes mixed
  }

  Future<void> _playReadAloud(Story story, StoryPage page) async {
    // Prevent overlap from rapid taps / page switches
    if (_isReadAloudBusy) return;
    _isReadAloudBusy = true;

    try {
      await _stopAllAudio();

      // 0) Personalized audio from Firestore (per user)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _parentVoiceEnabled && _parentVoiceId.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance
              .doc('users/${user.uid}/personalized_audio/${story.id}')
              .get();
          final data = doc.data() ?? {};
          final pages = (data['pages'] as Map?) ?? {};
          final entry = pages['${page.index}'];
          final personalizedUrl =
              (entry is Map && entry['audioUrl'] is String) ? entry['audioUrl'] as String : null;
          if (personalizedUrl != null && personalizedUrl.trim().isNotEmpty) {
            if (kDebugMode) {
              debugPrint('Personalized audio hit: ${story.id} page=${page.index}');
            }
            await _playUrl(personalizedUrl.trim());
            return;
          }
        } catch (_) {
          // fall through
        }
      }

      // 1) Generate personalized narration if missing
      if (_parentVoiceEnabled && _parentVoiceId.isNotEmpty) {
        try {
          if (kDebugMode) {
            debugPrint(
              'Generate narration: enabled=$_parentVoiceEnabled voiceId=$_parentVoiceId story=${story.id} page=${page.index}',
            );
          }
          final generatedUrl = await _parentVoiceService.generateNarration(
            voiceId: _parentVoiceId,
            storyId: story.id,
            pageIndex: page.index,
            lang: _langForBackend(story.language),
            text: page.text,
            elevenlabsSettings: _elevenlabsSettings,
          );
          if (generatedUrl != null && generatedUrl.trim().isNotEmpty) {
            if (kDebugMode) {
              debugPrint('Generate narration success: ${story.id} page=${page.index}');
            }
            await _playUrl(generatedUrl.trim());
            return;
          }
          if (kDebugMode) {
            debugPrint('Generate narration returned empty url');
          }
        } catch (_) {
          // fall through
        }
      }
      if (kDebugMode) {
        debugPrint(
          'Narration skipped: enabled=$_parentVoiceEnabled voiceId=$_parentVoiceId',
        );
      }

      // 2) URL first (primary)
      final url = page.audioUrl;
      if (url != null && url.trim().isNotEmpty) {
        try {
          await _playUrl(url.trim());
          return;
        } catch (_) {
          // fall through
        }
      }

      // 3) Asset second (offline pack) (offline pack)
      final asset = AssetPath.normalize(page.audioAsset);
      if (asset.isNotEmpty) {
        try {
          await _player.setAsset(asset);
          await _player.play();
          return;
        } catch (_) {
          // fall through
        }
      }

      // 4) TTS fallback (never crash)
      try {
        final lang = story.language.toLowerCase();
        if (lang == 'te') {
          await _tts.setLanguage('te-IN');
        } else {
          await _tts.setLanguage('en-US');
        }
        await _tts.speak(page.text);
      } catch (_) {
        // swallow; reading should continue even without audio
      }
    } finally {
      _isReadAloudBusy = false;
    }
  }

  // ---------- Progress helpers ----------

  Future<void> _saveReadingProgress() async {
    final story = _storyCache;
    if (story == null || story.pages.isEmpty) return;

    final int clamped = (_pageIndex.clamp(0, story.pages.length - 1) as int);
    try {
      await widget.progressRepository.saveReadingProgress(
        ReadingProgress(
          storyId: widget.storyId,
          pageIndex: clamped,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('saveProgress failed (offline?): $e');
    }
  }

  Future<void> _saveStoryProgress() async {
    final story = _storyCache;
    if (story == null || story.pages.isEmpty) return;

    final int clamped = (_pageIndex.clamp(0, story.pages.length - 1) as int);
    final bool isCompleted = clamped == story.pages.length - 1;
    try {
      await widget.progressRepository.saveStoryProgress(
        StoryProgress(
          storyId: widget.storyId,
          lastPageIndex: clamped,
          completed: isCompleted,
          lastOpenedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('saveStoryProgress failed (offline?): $e');
    }
  }

  Future<void> _showCompletion(Story story) async {
    if (_completionShown || !mounted) return;
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

  Future<void> _setPage(int newIndex) async {
    final story = _storyCache;
    if (story == null) return;

    // Stop current audio before switching pages
    await _stopAllAudio();

    setState(() => _pageIndex = newIndex);

    unawaited(_saveReadingProgress());
    unawaited(_saveStoryProgress());

    // Auto read if enabled
    if (_readAloudEnabled) {
      final page = story.pages[_pageIndex];
      await _playReadAloud(story, page);
    }
  }

  Future<void> _onChoiceTap(StoryChoice c, int idx) async {
    if (_choiceLocked) return;

    setState(() {
      _choiceLocked = true;
      _selectedChoiceIdx = idx;
      _sparkleChoiceIdx = idx;
    });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    setState(() {
      _sparkleChoiceIdx = null;
    });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    setState(() {
      _choiceLocked = false;
      _selectedChoiceIdx = null;
    });

    await _setPage(c.nextPageIndex);
  }

  String? _choiceImageFor(String label) {
    final t = label.toLowerCase();
    if (t.contains('butterfly')) return 'assets/icons/butterfly.png';
    if (t.contains('music') || t.contains('song')) return 'assets/icons/music.png';
    if (t.contains('left')) return 'assets/icons/left.png';
    if (t.contains('right')) return 'assets/icons/right.png';
    if (t.contains('friend') || t.contains('ask')) return 'assets/icons/friends.png';
    return 'assets/icons/star.png';
  }

  void _markSwiped() {
    if (_swipeHintSeen) return;
    setState(() => _swipeHintSeen = true);
  }

  void _autoDismissSwipeHint() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_swipeHintSeen) return;
      setState(() => _swipeHintSeen = true);
    });
  }

  Widget _SwipeHintOverlay({required bool show}) {
    if (!show) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: AnimatedOpacity(
            opacity: show ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Swipe',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ProgressRow({
    required int index,
    required int total,
    VoidCallback? onPrev,
    VoidCallback? onNext,
  }) {
    final pageNum = index + 1;
    final value = total == 0 ? 0.0 : pageNum / total;
    final prev = onPrev ??
        (index > 0
            ? () {
                _markSwiped();
                _setPage(index - 1);
              }
            : null);
    final next = onNext ??
        (index < total - 1
            ? () {
                _markSwiped();
                _setPage(index + 1);
              }
            : null);

    return Row(
      children: [
        IconButton(
          onPressed: prev,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: AppColors.outline.withOpacity(0.35),
              ),
              const SizedBox(height: 6),
              Text(
                'Page $pageNum of $total',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: next,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  int realIndexFor(Story story, bool isCreatedStory) {
    if (!isCreatedStory) return _pageIndex;
    if (_path.isEmpty) return _pageIndex;
    return _path[_pathPos].clamp(0, story.pages.length - 1);
  }

  void _maybeAppendLinear(Story story, int realIndex) {
    if (_path.isEmpty || _pathPos != _path.length - 1) return;
    final p = story.pages[realIndex];
    if (p.hasChoices) return;
    final nextReal = realIndex + 1;
    if (nextReal >= story.pages.length) return;
    if (_path.last == nextReal) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_path.isNotEmpty && _path.last == nextReal) return;
      setState(() => _path.add(nextReal));
    });
  }

  Future<void> _commitChoiceBranch({
    required Story story,
    required StoryPage choicePage,
    required StoryChoice picked,
  }) async {
    final outcomes = choicePage.choices.map((c) => c.nextPageIndex).toList();
    final maxOutcome = outcomes.reduce((a, b) => a > b ? a : b);
    final rejoin = maxOutcome + 1;

    setState(() => _showChoiceSparkle = true);

    try {
      await _playWowSfx();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _showChoiceSparkle = false);

    setState(() {
      _path = _path.sublist(0, _pathPos + 1);
      _path.add(picked.nextPageIndex);
      if (rejoin < story.pages.length) {
        _path.add(rejoin);
      }
    });

    await _pageController.animateToPage(
      _pathPos + 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _playWowSfx() async {
    final bytes = generateWowSound();
   // await _sfxPlayer.setAudioSource(AudioSource.bytes(bytes));
   // await _sfxPlayer.play();
  }

  Uint8List generateWowSound() {
    const sampleRate = 44100;
    const durationSeconds = 0.3;
    final samples = (sampleRate * durationSeconds).toInt();

    final buffer = Float32List(samples);

    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final freq = 600 + (1200 * t);
      buffer[i] = sin(2 * pi * freq * t) * exp(-6 * t);
    }

    return _encodeWav(buffer, sampleRate);
  }

  Uint8List _encodeWav(Float32List samples, int sampleRate) {
    final bytes = ByteData(44 + samples.length * 2);

    void writeString(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    bytes.setUint32(40, samples.length * 2, Endian.little);

    int offset = 44;
    for (final s in samples) {
      final v = (s.clamp(-1, 1) * 32767).toInt();
      bytes.setInt16(offset, v, Endian.little);
      offset += 2;
    }

    return bytes.buffer.asUint8List();
  }

  Widget _buildStoryPageContent({
    required Story story,
    required StoryPage page,
    required int realIndex,
    required bool isCreatedStory,
  }) {
    final imageFlex = _imageFlexFor(story.ageBand, page.text);
    final textFlex = 10 - imageFlex;

    return Stack(
      children: [
        Column(
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
                  backgroundAsset: AssetPath.normalize(page.backgroundAsset ?? page.imageAsset),
                  heroAsset: AssetPath.normalize(page.heroAsset),
                  friendAsset: AssetPath.normalize(page.friendAsset),
                  objectAsset: AssetPath.normalize(page.objectAsset),
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
              const SizedBox(height: AppSpacing.small),
              Text(
                'Tap a picture',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              if (isCreatedStory)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: page.choices.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.medium,
                    crossAxisSpacing: AppSpacing.medium,
                    childAspectRatio: 1.05,
                  ),
                  itemBuilder: (context, i) {
                    final c = page.choices[i];
                    final img = AssetPath.normalize(c.imageAsset);
                    return ChoiceTile(
                      label: c.label,
                      imageAsset: img,
                      selected: false,
                      showSparkle: _showChoiceSparkle,
                      disabled: false,
                      onTap: () => _commitChoiceBranch(
                        story: story,
                        choicePage: page,
                        picked: c,
                      ),
                    );
                  },
                )
              else
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

            _ProgressRow(
              index: isCreatedStory ? _pathPos : _pageIndex,
              total: isCreatedStory ? _path.length : story.pages.length,
              onPrev: isCreatedStory && _pathPos > 0
                  ? () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                      )
                  : null,
              onNext: isCreatedStory && _pathPos < _path.length - 1
                  ? () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                      )
                  : null,
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
        if (_showChoiceSparkle)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showChoiceSparkle ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  color: Colors.white.withOpacity(0.08),
                  child: Center(
                    child: Icon(
                      Icons.auto_awesome,
                      size: 72,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCreatedStoryPager(Story story) {
    return PageView.builder(
      controller: _pageController,
      itemCount: _path.length,
      onPageChanged: (pos) async {
        final real = _path[pos];
        setState(() {
          _pathPos = pos;
          _pageIndex = real;
        });

        final p = story.pages[real];
        if (!p.hasChoices) {
          final nextReal = real + 1;
          if (nextReal < story.pages.length && _path.last != nextReal) {
            setState(() => _path.add(nextReal));
          }
        }

        unawaited(_saveReadingProgress());
        unawaited(_saveStoryProgress());

        if (_readAloudEnabled) {
          await _playReadAloud(story, p);
        }
      },
      itemBuilder: (_, pathPos) {
        final real = _path[pathPos];
        final page = story.pages[real];
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Stack(
            children: [
              _buildStoryPageContent(
                story: story,
                page: page,
                realIndex: real,
                isCreatedStory: true,
              ),
              _SwipeHintOverlay(show: !_swipeHintSeen && _pathPos == 0),
            ],
          ),
        );
      },
    );
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
              final isCreatedStory = story.id.startsWith('created_');
              if (isCreatedStory && _path.isEmpty) return;

              final toggledOn = !_readAloudEnabled;
              setState(() => _readAloudEnabled = toggledOn);

              if (toggledOn) {
                final realIndex = realIndexFor(story, isCreatedStory);
                final page = story.pages[realIndex];
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

          final bool isCreatedStory = story.id.startsWith('created_');
          if (isCreatedStory && _path.isEmpty) {
            final startReal =
                (widget.startPageIndex ?? 0).clamp(0, story.pages.length - 1);
            _path = [startReal];
            _pathPos = 0;
            _pageIndex = startReal;
            _pageController = PageController(initialPage: 0);
            _pageControllerReady = true;
          } else if (!isCreatedStory && !_pageControllerReady) {
            _pageController = PageController(initialPage: 0);
            _pageControllerReady = true;
          }

          final int safeIndex = (_pageIndex.clamp(0, story.pages.length - 1) as int);
          if (safeIndex != _pageIndex) _pageIndex = safeIndex;

          final realIndex = realIndexFor(story, isCreatedStory);
          final page = story.pages[realIndex];

          if (isCreatedStory) {
            _maybeAppendLinear(story, realIndex);
            return _buildCreatedStoryPager(story);
          }

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final vx = details.primaryVelocity ?? 0;

              if (vx < -250) {
                _markSwiped();
                if (_pageIndex < story.pages.length - 1) {
                  _setPage(_pageIndex + 1);
                } else {
                  _showCompletion(story);
                }
              }

              if (vx > 250) {
                _markSwiped();
                if (_pageIndex > 0) {
                  _setPage(_pageIndex - 1);
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Stack(
                children: [
                  _buildStoryPageContent(
                    story: story,
                    page: page,
                    realIndex: realIndex,
                    isCreatedStory: false,
                  ),
                  _SwipeHintOverlay(show: !_swipeHintSeen && _pageIndex == 0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

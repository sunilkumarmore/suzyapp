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
import '../widgets/read_to_me_button.dart';
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
  late final ParentVoiceService _narratorService;
  late final PageController _pageController;
  bool _pageControllerReady = false;

  bool _parentVoiceEnabled = false;
  String _parentVoiceId = '';
  Map<String, dynamic> _elevenlabsSettings = ParentVoiceSettings.defaults().elevenlabsSettings;
  String _narratorVoiceId = '';
  String _narrationMode = 'narrator';
  DateTime? _narratorCooldownUntil;
  DateTime? _parentCooldownUntil;
  final Map<String, String> _narratorUrlCache = {};

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
  bool _showSwipeHint = true;
  bool _userHasSwiped = false;
  bool _choiceLocked = false;
  int? _selectedChoiceIdx;
  int? _sparkleChoiceIdx;

  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();

    _pageIndex = widget.startPageIndex ?? 0;
    _future = widget.storyRepository.getStoryById(widget.storyId);

    _parentVoiceService = ParentVoiceService(
      generateEndpoint: 'https://us-central1-suzyapp.cloudfunctions.net/generateNarration',
      signedUrlEndpoint: 'https://us-central1-suzyapp.cloudfunctions.net/getSignedAudioUrl',
    );
    _narratorService = ParentVoiceService(
      generateEndpoint: 'https://us-central1-suzyapp.cloudfunctions.net/generateNarrationGlobal',
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
    _sfxPlayer.dispose();
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

      final modeRaw = data['narrationMode'];
      _narrationMode = (modeRaw is String && modeRaw.trim().isNotEmpty)
          ? modeRaw.trim()
          : 'narrator';

      final narrRaw = data['narratorVoiceId'];
      _narratorVoiceId = (narrRaw is String) ? narrRaw.trim() : '';
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

  Future<void> _playPageFlipSfx() async {
    try {
      await _sfxPlayer.setAsset('assets/audio/sfx/page_flip.mp3');
      await _sfxPlayer.setVolume(0.18); // very soft
      await _sfxPlayer.seek(Duration.zero);
      await _sfxPlayer.play();
    } catch (_) {
      // ignore if missing/failed
    }
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

  bool _cooldownActive(DateTime? until) =>
      until != null && DateTime.now().isBefore(until);

  String _narratorCacheKey({
    required String storyId,
    required int pageIndex,
    required String lang,
    required String voiceId,
    required String text,
  }) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return '$voiceId|$storyId|$pageIndex|$lang|${t.hashCode}';
  }

  Future<String?> _getNarratorUrl({
    required Story story,
    required StoryPage page,
  }) async {
    if (_narrationMode != 'narrator') return null;
    if (_cooldownActive(_narratorCooldownUntil)) return null;

    final cacheVoiceId = _narratorVoiceId.isNotEmpty ? _narratorVoiceId : 'default';
    final key = _narratorCacheKey(
      storyId: story.id,
      pageIndex: page.index,
      lang: _langForBackend(story.language),
      voiceId: cacheVoiceId,
      text: page.text,
    );

    final cached = _narratorUrlCache[key];
    if (cached != null && cached.isNotEmpty) {
      debugPrint('Narrator cache hit: ${story.id} page=${page.index}');
      return cached;
    }

    try {
      final url = await _narratorService.generateNarration(
        voiceId: _narratorVoiceId,
        storyId: story.id,
        pageIndex: page.index,
        lang: _langForBackend(story.language),
        text: page.text,
        elevenlabsSettings: _elevenlabsSettings,
      );

      if (url != null && url.trim().isNotEmpty) {
        debugPrint('Narrator generated: ${story.id} page=${page.index}');
        _narratorUrlCache[key] = url.trim();
        return url.trim();
      }
      debugPrint('Narrator pending (202): ${story.id} page=${page.index}');
      return null;
    } catch (_) {
      debugPrint('Narrator error; cooldown set: ${story.id} page=${page.index}');
      _narratorCooldownUntil = DateTime.now().add(const Duration(minutes: 3));
      return null;
    }
  }

  void _prefetchNextNarrator(Story story) {
    if (!_readAloudEnabled) return;
    if (_narrationMode != 'narrator') return;
    if (_cooldownActive(_narratorCooldownUntil)) return;

    final nextIndex = (_pageIndex + 1).clamp(0, story.pages.length - 1);
    if (nextIndex == _pageIndex) return;

    final nextPage = story.pages[nextIndex];
    unawaited(_getNarratorUrl(story: story, page: nextPage));
  }

  Future<void> _playReadAloud(Story story, StoryPage page) async {
    if (_isReadAloudBusy) return;
    _isReadAloudBusy = true;

    try {
      await _stopAllAudio();

      final pageUrl = page.audioUrl;
      if (pageUrl != null && pageUrl.trim().isNotEmpty) {
        try {
          await _playUrl(pageUrl.trim());
          _prefetchNextNarrator(story);
          return;
        } catch (_) {}
      }

      final narratorUrl = await _getNarratorUrl(story: story, page: page);
      if (narratorUrl != null && narratorUrl.isNotEmpty) {
        await _playUrl(narratorUrl);
        _prefetchNextNarrator(story);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final parentAllowed =
          _narrationMode == 'parent' || (_narrationMode == 'narrator');
      if (parentAllowed &&
          user != null &&
          _parentVoiceEnabled &&
          _parentVoiceId.isNotEmpty &&
          !_cooldownActive(_parentCooldownUntil) &&
          !_parentVoiceDegraded) {
        try {
          final doc = await FirebaseFirestore.instance
              .doc('users/${user.uid}/personalized_audio/${story.id}')
              .get();
          final data = doc.data() ?? {};
          final pages = (data['pages'] as Map?) ?? {};
          final entry = pages['${page.index}'];
          String? personalizedUrl;
          if (entry is Map) {
            final storagePath = entry['storagePath'];
            if (storagePath is String && storagePath.trim().isNotEmpty) {
              try {
                personalizedUrl = await _parentVoiceService.getSignedUrl(
                  storagePath: storagePath.trim(),
                );
              } catch (_) {
                _parentCooldownUntil = DateTime.now().add(const Duration(minutes: 3));
              }
            }

            if (personalizedUrl == null) {
              final urlRaw = entry['audioUrl'];
              if (urlRaw is String) personalizedUrl = urlRaw;
            }
          }

          if (personalizedUrl != null && personalizedUrl.trim().isNotEmpty) {
            await _playUrl(personalizedUrl.trim());
            _prefetchNextNarrator(story);
            return;
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
            await _playUrl(generatedUrl.trim());
            _prefetchNextNarrator(story);
            return;
          }
        } catch (_) {
          _parentCooldownUntil = DateTime.now().add(const Duration(minutes: 3));
        }
      }

      final asset = AssetPath.normalize(page.audioAsset);
      if (asset.isNotEmpty) {
        try {
          await _player.setAsset(asset);
          await _player.play();
          _prefetchNextNarrator(story);
          return;
        } catch (_) {}
      }

      try {
        if (_narrationMode == 'tts' || true) {
          final lang = story.language.toLowerCase();
          await _tts.setLanguage(lang == 'te' ? 'te-IN' : 'en-US');
          await _tts.speak(page.text);
        }
      } catch (_) {}
    } finally {
      _isReadAloudBusy = false;
    }
  }

  Future<void> _toggleReadAloud() async {
    final story = _storyCache;
    if (story == null) return;

    final nowOn = !_readAloudEnabled;
    setState(() => _readAloudEnabled = nowOn);

    if (nowOn) {
      final page = story.pages[_pageIndex];
      await _playReadAloud(story, page);
    } else {
      await _stopAllAudio();
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
    await _playPageFlipSfx();

    setState(() {
      if (!_userHasSwiped) {
        _userHasSwiped = true;
        _showSwipeHint = false;
      }
      _pageIndex = newIndex;
    });

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
    final barColor = Color.lerp(AppColors.primaryYellow, AppColors.accentCoral, value) ??
        AppColors.primaryYellow;
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
          visualDensity: VisualDensity.compact,
          onPressed: prev,
          icon: Icon(
            Icons.chevron_left,
            color: AppColors.textSecondary.withOpacity(0.7),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, v, _) {
                return LinearProgressIndicator(
                  minHeight: 10,
                  value: v,
                  backgroundColor: AppColors.surface,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                );
              },
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: next,
          icon: Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary.withOpacity(0.7),
          ),
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
    final isLastPage = realIndex >= story.pages.length - 1;
    if (page.hasChoices) {
      return _buildChoicePage(
        story: story,
        page: page,
        isCreatedStory: isCreatedStory,
        isLastPage: isLastPage,
      );
    }

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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) {
                    return FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.985, end: 1.0).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: AdventureScene(
                    key: ValueKey('scene_${page.index}'),
                    backgroundAsset: AssetPath.normalize(page.backgroundAsset ?? page.imageAsset),
                    heroAsset: AssetPath.normalize(page.heroAsset),
                    friendAsset: AssetPath.normalize(page.friendAsset),
                    objectAsset: AssetPath.normalize(page.objectAsset),
                    emotionEmoji: page.emotionEmoji,
                  ),
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        page.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: story.ageBand == '2-3' ? 20 : 22,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.medium),

            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ReadToMeButton(
                  enabled: _readAloudEnabled,
                  isPlaying: _isPlayingAudio || _isSpeakingTts,
                  onTap: _toggleReadAloud,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.medium),

              const SizedBox(height: AppSpacing.medium),

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
                    : (isCreatedStory && isLastPage
                        ? () => _showCompletion(story)
                        : (!isCreatedStory && isLastPage ? () => _showCompletion(story) : null)),
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

  Widget _buildChoicePage({
    required Story story,
    required StoryPage page,
    required bool isCreatedStory,
    required bool isLastPage,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;

        final imageH = (h * 0.34).clamp(160.0, 260.0);
        final promptH = (h * 0.16).clamp(70.0, 120.0);
        final bottomH = 78.0;
        const gap = 12.0;

        final choicesH = (h - imageH - promptH - bottomH - gap * 3)
            .clamp(140.0, 360.0);

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: imageH,
                  child: _buildSceneOrImage(page),
                ),
                const SizedBox(height: gap),
                SizedBox(
                  height: promptH,
                  child: _PromptCard(
                    text: page.text,
                    maxLines: 3,
                    fontSize: story.ageBand == '2-3' ? 20 : 22,
                  ),
                ),
                const SizedBox(height: gap),
                SizedBox(
                  height: choicesH,
                  child: _TwoChoiceTiles(
                    choices: page.choices,
                    showSparkle: _showChoiceSparkle,
                    disabled: false,
                    onPick: (choice) {
                      if (isCreatedStory) {
                        _commitChoiceBranch(
                          story: story,
                          choicePage: page,
                          picked: choice,
                        );
                      } else {
                        _setPage(choice.nextPageIndex);
                      }
                    },
                  ),
                ),
                const SizedBox(height: gap),
                SizedBox(
                  height: bottomH,
                  child: _ProgressRow(
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
                        : (isCreatedStory && isLastPage ? () => _showCompletion(story) : null),
                  ),
                ),
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
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSceneOrImage(StoryPage page) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1.0).animate(anim),
              child: child,
            ),
          );
        },
        child: AdventureScene(
          key: ValueKey('scene_${page.index}'),
          backgroundAsset: AssetPath.normalize(page.backgroundAsset ?? page.imageAsset),
          heroAsset: AssetPath.normalize(page.heroAsset),
          friendAsset: AssetPath.normalize(page.friendAsset),
          objectAsset: AssetPath.normalize(page.objectAsset),
          emotionEmoji: page.emotionEmoji,
        ),
      ),
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

    if (len <= shortMax) return 7;
    if (len <= mediumMax) return 6;
    return 5;
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
        actions: const [],
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

          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: GestureDetector(
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
                  child: _buildStoryPageContent(
                    story: story,
                    page: page,
                    realIndex: realIndex,
                    isCreatedStory: false,
                  ),
                ),
              ),
              if (_showSwipeHint && safeIndex == 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 82,
                  child: const IgnorePointer(
                    child: _SwipeHint(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final String text;
  final int maxLines;
  final double fontSize;

  const _PromptCard({
    required this.text,
    required this.maxLines,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoChoiceTiles extends StatelessWidget {
  final List<StoryChoice> choices;
  final ValueChanged<StoryChoice> onPick;
  final bool showSparkle;
  final bool disabled;

  const _TwoChoiceTiles({
    required this.choices,
    required this.onPick,
    required this.showSparkle,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    final a = choices.isNotEmpty ? choices[0] : null;
    final b = choices.length > 1 ? choices[1] : null;

    return Row(
      children: [
        Expanded(
          child: a == null
              ? const SizedBox()
              : ChoiceTileBig(
                  choice: a,
                  showSparkle: showSparkle,
                  disabled: disabled,
                  onTap: () => onPick(a),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: b == null
              ? const SizedBox()
              : ChoiceTileBig(
                  choice: b,
                  showSparkle: showSparkle,
                  disabled: disabled,
                  onTap: () => onPick(b),
                ),
        ),
      ],
    );
  }
}

class ChoiceTileBig extends StatelessWidget {
  final StoryChoice choice;
  final VoidCallback onTap;
  final bool showSparkle;
  final bool disabled;

  const ChoiceTileBig({
    super.key,
    required this.choice,
    required this.onTap,
    required this.showSparkle,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    final img = AssetPath.normalize(choice.imageAsset);
    return ChoiceTile(
      label: choice.label,
      imageAsset: img,
      selected: false,
      showSparkle: showSparkle,
      disabled: disabled,
      height: double.infinity,
      onTap: onTap,
    );
  }
}

class _SwipeHint extends StatefulWidget {
  const _SwipeHint();

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Opacity(
          opacity: 0.35 + (0.35 * t),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.chevron_left, size: 30),
              SizedBox(width: 8),
              Icon(Icons.swipe, size: 22),
              SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 30),
            ],
          ),
        );
      },
    );
  }
}

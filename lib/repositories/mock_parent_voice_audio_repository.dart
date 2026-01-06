import '../models/parent_voice_audio.dart';
import 'parent_voice_audio_repository.dart';

class MockParentVoiceAudioRepository implements ParentVoiceAudioRepository {
  final Map<String, ParentVoiceAudio> _cache = {};

  @override
  Future<ParentVoiceAudio?> getCachedAudio({
    required String storyId,
    required int pageIndex,
    required String voiceId,
  }) async {
    final key = '${voiceId}__${storyId}__$pageIndex';
    return _cache[key];
  }

  @override
  Future<void> saveCachedAudio(ParentVoiceAudio audio) async {
    _cache[audio.cacheKey] = audio;
  }
}

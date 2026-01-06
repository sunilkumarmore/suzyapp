import '../models/parent_voice_audio.dart';

abstract class ParentVoiceAudioRepository {
  Future<ParentVoiceAudio?> getCachedAudio({
    required String storyId,
    required int pageIndex,
    required String voiceId,
  });

  Future<void> saveCachedAudio(ParentVoiceAudio audio);
}

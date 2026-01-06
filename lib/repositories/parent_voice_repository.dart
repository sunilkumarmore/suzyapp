import '../models/parent_voice_profile.dart';

abstract class ParentVoiceRepository {
  Future<ParentVoiceProfile?> getProfile();
  Future<void> saveProfile(ParentVoiceProfile profile);
}

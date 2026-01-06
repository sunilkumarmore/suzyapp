import '../models/parent_voice_profile.dart';
import 'parent_voice_repository.dart';

class MockParentVoiceRepository implements ParentVoiceRepository {
  ParentVoiceProfile? _profile;

  @override
  Future<ParentVoiceProfile?> getProfile() async => _profile;

  @override
  Future<void> saveProfile(ParentVoiceProfile profile) async {
    _profile = profile;
  }
}

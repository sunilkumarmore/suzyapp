import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParentVoiceSettings {
  final bool enabled;
  final String? voiceId;

  ParentVoiceSettings({required this.enabled, this.voiceId});
}

class FirebaseParentVoiceSettingsRepository {
  final FirebaseFirestore firestore;

  FirebaseParentVoiceSettingsRepository({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  Future<ParentVoiceSettings> getSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return ParentVoiceSettings(enabled: false);

    final doc = await firestore.doc('users/${user.uid}/settings/audio').get();
    if (!doc.exists) return ParentVoiceSettings(enabled: false);

    final data = doc.data()!;
    return ParentVoiceSettings(
      enabled: (data['parentVoiceEnabled'] as bool?) ?? false,
      voiceId: data['elevenVoiceId'] as String?,
    );
  }
}

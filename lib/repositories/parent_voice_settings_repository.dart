import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../models/parent_voice_settings.dart';

class ParentVoiceSettingsRepository {
  ParentVoiceSettingsRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Ensures users/{uid}/settings/audio exists and has correct types.
  /// Safe to call on every app start.
  Future<void> ensureDefaults() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('ensureDefaults() called with no signed-in user.');
    }

    final audioDocRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('settings')
        .doc('audio');

    final snap = await audioDocRef.get();

    // Default values we want to guarantee exist (and with correct types).
    bool parentVoiceEnabled = false;
    String elevenVoiceId = '';
    String narrationMode = 'narrator';
    String narratorVoiceId = '';
    Map<String, dynamic> elevenlabsSettings = ParentVoiceSettings.defaults().elevenlabsSettings;

    if (snap.exists) {
      final data = snap.data() ?? {};

      final rawEnabled = data['parentVoiceEnabled'];
      if (rawEnabled is bool) {
        parentVoiceEnabled = rawEnabled;
      } else if (rawEnabled is String) {
        // Fix common mistake: "true"/"false" stored as string
        final v = rawEnabled.toLowerCase().trim();
        if (v == 'true') parentVoiceEnabled = true;
        if (v == 'false') parentVoiceEnabled = false;
      }

      final rawVoiceId = data['elevenVoiceId'];
      if (rawVoiceId is String) {
        elevenVoiceId = rawVoiceId;
      }

      final rawMode = data['narrationMode'];
      if (rawMode is String && rawMode.trim().isNotEmpty) {
        narrationMode = rawMode.trim();
      }

      final rawNarratorId = data['narratorVoiceId'];
      if (rawNarratorId is String) {
        narratorVoiceId = rawNarratorId;
      }

      final rawSettings = data['elevenlabsSettings'];
      if (rawSettings is Map) {
        elevenlabsSettings = Map<String, dynamic>.from(rawSettings);
      }
    }







    // Write back: create doc if missing, and normalize types.
    await audioDocRef.set(
      {
        'parentVoiceEnabled': parentVoiceEnabled, // MUST be boolean
        'elevenVoiceId': elevenVoiceId,
        'narrationMode': narrationMode,
        'narratorVoiceId': narratorVoiceId,
        'elevenlabsSettings': elevenlabsSettings,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ...keep your existing load/save methods below


Stream<ParentVoiceSettings> watchSettings() {
  final user = _auth.currentUser;
  if (user == null) {
    return Stream.value(ParentVoiceSettings.defaults());
  }

  final docRef = _firestore
      .collection('users')
      .doc(user.uid)
      .collection('settings')
      .doc('audio');

  return docRef.snapshots().map((snap) {
    final data = snap.data() ?? {};

    final rawEnabled = data['parentVoiceEnabled'];
    final enabled = rawEnabled is bool
        ? rawEnabled
        : (rawEnabled is String
            ? rawEnabled.toLowerCase().trim() == 'true'
            : false);

    final voiceId = (data['elevenVoiceId'] is String) ? data['elevenVoiceId'] as String : '';
    final rawSettings = data['elevenlabsSettings'];
    final settings = rawSettings is Map
        ? Map<String, dynamic>.from(rawSettings)
        : ParentVoiceSettings.defaults().elevenlabsSettings;

    return ParentVoiceSettings(
      parentVoiceEnabled: enabled,
      elevenVoiceId: voiceId,
      elevenlabsSettings: settings,
    );
  });
}

Future<void> saveSettings(ParentVoiceSettings settings) async {
  final user = _auth.currentUser;
  if (user == null) {
    throw StateError('saveSettings() called with no signed-in user.');
  }

  final docRef = _firestore
      .collection('users')
      .doc(user.uid)
      .collection('settings')
      .doc('audio');

  await docRef.set(
    {
      'parentVoiceEnabled': settings.parentVoiceEnabled, // ✅ bool
      'elevenVoiceId': settings.elevenVoiceId,
      'elevenlabsSettings': settings.elevenlabsSettings,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

}

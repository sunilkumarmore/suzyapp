import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ParentVoiceService {
  final String? createEndpoint;
  final String? generateEndpoint;
  final String? signedUrlEndpoint;

  ParentVoiceService({
    this.createEndpoint,
    this.generateEndpoint,
    this.signedUrlEndpoint,
  });

  Future<String?> createVoiceFromSample({
    required Uint8List audioBytes,
    required String mimeType,
    String name = 'Parent Voice',
  }) async {
    if (createEndpoint == null || createEndpoint!.isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null) return null;
    debugPrint('ParentVoice create: bytes=${audioBytes.length} mime=$mimeType name=$name');

    final resp = await http.post(
      Uri.parse(createEndpoint!),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'audioBase64': base64Encode(audioBytes),
        'mimeType': mimeType,
        'name': name,
      }),
    );

    debugPrint('ParentVoice create status=${resp.statusCode}');
    debugPrint('ParentVoice create body=${resp.body}');
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    debugPrint('ParentVoice create parsed voiceId=${data['voiceId']}');
    return data['voiceId'] as String?;
  }

  Future<String?> generateNarration({
    required String voiceId,
    required String storyId,
    required int pageIndex,
    required String lang,
    required String text,
    Map<String, dynamic>? elevenlabsSettings,
  }) async {
    if (generateEndpoint == null || generateEndpoint!.isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null) return null;

    final payload = <String, dynamic>{
      'voiceId': voiceId,
      'storyId': storyId,
      'pageIndex': pageIndex,
      'lang': lang,
      'text': text,
    };
    _applyElevenlabsSettings(payload, elevenlabsSettings);

    final resp = await http.post(
      Uri.parse(generateEndpoint!),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 202) return null;

    if (resp.statusCode != 200) {
      throw Exception('generateNarration failed: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    final storagePath = data['storagePath'];
    if (storagePath is String &&
        storagePath.trim().isNotEmpty &&
        signedUrlEndpoint != null &&
        signedUrlEndpoint!.isNotEmpty) {
      try {
        final signed = await getSignedUrl(storagePath: storagePath.trim());
        if (signed != null && signed.trim().isNotEmpty) return signed.trim();
      } catch (_) {
        // Fall back to direct URL parsing below.
      }
    }

    // Support both:
    // { audioUrl: "..." }
    // { status: "READY", audioUrl: "...", storagePath: "..." }
    final url = data['audioUrl'];
    if (url is String && url.trim().isNotEmpty) return url.trim();

    // In case backend returns { status: "GENERATING" } with 200 (not expected, but safe)
    final status = data['status'];
    if (status is String && status.toUpperCase() == 'GENERATING') return null;

    return null;
  }

  Future<String?> getSignedUrl({required String storagePath}) async {
    if (signedUrlEndpoint == null || signedUrlEndpoint!.isEmpty) return null;

    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null) return null;

    final resp = await http.post(
      Uri.parse(signedUrlEndpoint!),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'storagePath': storagePath,
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception('getSignedUrl failed: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = data['audioUrl'];
    if (url is String && url.trim().isNotEmpty) return url.trim();
    return null;
  }
}

void _applyElevenlabsSettings(
  Map<String, dynamic> payload,
  Map<String, dynamic>? settings,
) {
  if (settings == null) return;

  void addNum(String key) {
    final v = settings[key];
    if (v is num) payload[key] = v;
  }

  void addBool(String key) {
    final v = settings[key];
    if (v is bool) payload[key] = v;
  }

  addNum('stability');
  addNum('similarity_boost');
  addNum('style');
  addBool('use_speaker_boost');
  addNum('speed');
}

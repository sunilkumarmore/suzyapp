import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ParentVoiceService {
  final String speakEndpoint;

  

  ParentVoiceService({required this.speakEndpoint});

  Future<String?> getOrCreatePageAudioUrl({
    required String voiceId,
    required String storyId,
    required int pageIndex,
    required String lang,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null) return null;

   // final token = await user.getIdToken();

    final resp = await http.post(
      Uri.parse(speakEndpoint),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'voiceId': voiceId,
        'storyId': storyId,
        'pageIndex': pageIndex,
        'lang': lang,
        'text': text,
      }),
    );

      debugPrint('🌐 parentVoiceSpeak status=${resp.statusCode}');
      debugPrint('🌐 parentVoiceSpeak body=${resp.body}');
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    debugPrint('🌐 parsed keys=${(data as Map).keys.toList()}');
    debugPrint('🌐 parsed audioUrl=${data['audioUrl']}');
    return data['audioUrl'] as String?;
  }
}

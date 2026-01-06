import 'dart:convert';
import 'package:http/http.dart' as http;

class VoiceBackendClient {
  final String baseUrl; // e.g. https://<cloudfunction-url>

  VoiceBackendClient({required this.baseUrl});

  Future<String> speak({
    required String uid,
    required String voiceId,
    required String text,
    required String language, // "en" / "te" / "mixed"
    required String storyId,
    required int pageIndex,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/voice/speak'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uid': uid,
        'voiceId': voiceId,
        'text': text,
        'language': language,
        'storyId': storyId,
        'pageIndex': pageIndex,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('voice/speak failed: ${res.statusCode} ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['audioUrl'] as String;
  }
}

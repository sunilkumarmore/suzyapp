class ParentVoiceAudio {
  final String storyId;
  final int pageIndex;
  final String voiceId;
  final String audioUrl; // URL in storage/CDN
  final DateTime createdAt;

  ParentVoiceAudio({
    required this.storyId,
    required this.pageIndex,
    required this.voiceId,
    required this.audioUrl,
    required this.createdAt,
  });

  String get cacheKey => '${voiceId}__${storyId}__$pageIndex';

  Map<String, dynamic> toJson() => {
        'storyId': storyId,
        'pageIndex': pageIndex,
        'voiceId': voiceId,
        'audioUrl': audioUrl,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ParentVoiceAudio.fromJson(Map<String, dynamic> json) {
    return ParentVoiceAudio(
      storyId: json['storyId'] as String,
      pageIndex: (json['pageIndex'] as num).toInt(),
      voiceId: json['voiceId'] as String,
      audioUrl: json['audioUrl'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

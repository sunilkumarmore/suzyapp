class ParentVoiceProfile {
  final bool enabled;
  final String provider; // "elevenlabs"
  final String voiceId;  // provider voice id
  final DateTime updatedAt;

  ParentVoiceProfile({
    required this.enabled,
    required this.provider,
    required this.voiceId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider,
        'voiceId': voiceId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ParentVoiceProfile.fromJson(Map<String, dynamic> json) {
    return ParentVoiceProfile(
      enabled: (json['enabled'] ?? false) as bool,
      provider: (json['provider'] ?? 'elevenlabs') as String,
      voiceId: (json['voiceId'] ?? '') as String,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String) ?? DateTime.now(),
    );
  }
}

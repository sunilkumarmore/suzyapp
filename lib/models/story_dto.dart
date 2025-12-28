class StoryDto {
  final String id;
  final String title;
  final String language; // en | te | mixed
  final String ageBand;  // 2-3 | 4-5 | 6-7
  final List<PageDto> pages;
    final String? audioUrl;
final String? audioAsset;

  StoryDto({
    required this.id,
    required this.title,
    required this.language,
    required this.ageBand,
    required this.pages,
    required this.audioUrl,
    this.audioAsset,
  });

  factory StoryDto.fromJson(Map<String, dynamic> j) {
    return StoryDto(
      id: j['id'],
      title: j['title'],
      language: j['language'],
      ageBand: j['ageBand'],
      pages: (j['pages'] as List).map((e) => PageDto.fromJson(e)).toList(),
      audioUrl: j['audioUrl'],
      audioAsset: j['audioAsset'],
    );
  }
}

class PageDto {
  final String text;
  final String? imageUrl;
  final String? imageAsset;
  final String? audioUrl;
final String? audioAsset;

  PageDto({required this.text, this.imageUrl, this.imageAsset,this.audioUrl, this.audioAsset});

  factory PageDto.fromJson(Map<String, dynamic> j) {
    return PageDto(
      text: j['text'],
      imageUrl: j['imageUrl'],
      imageAsset: j['imageAsset'],
      audioUrl: j['audioUrl'] as String?,
audioAsset: j['audioAsset'] as String?,
    );
  }
}

class StoryDto {
  final String id;
  final String title;
  final String language; // en | te | mixed
  final String ageBand;  // 2-3 | 4-5 | 6-7
  final List<PageDto> pages;

  StoryDto({
    required this.id,
    required this.title,
    required this.language,
    required this.ageBand,
    required this.pages,
  });

  factory StoryDto.fromJson(Map<String, dynamic> j) {
    return StoryDto(
      id: j['id'],
      title: j['title'],
      language: j['language'],
      ageBand: j['ageBand'],
      pages: (j['pages'] as List).map((e) => PageDto.fromJson(e)).toList(),
    );
  }
}

class PageDto {
  final String text;
  final String? imageUrl;
  final String? imageAsset;

  PageDto({required this.text, this.imageUrl, this.imageAsset});

  factory PageDto.fromJson(Map<String, dynamic> j) {
    return PageDto(
      text: j['text'],
      imageUrl: j['imageUrl'],
      imageAsset: j['imageAsset'],
    );
  }
}

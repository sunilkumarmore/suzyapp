class Story {
  final String id;
  final String title;
  final String language; // 'en' | 'te' | 'mixed'
  //final String difficulty; // 'Easy' | 'Medium' | 'Hard'
  final List<StoryPage> pages;
  final String ageBand; 
  final String? coverAsset;// e.g. '2-3', '4-5', '6-7',

  Story({
    required this.id,
    required this.title,
    required this.language,
    required this.pages,
    required this.ageBand,
    required this.coverAsset
    
  });
}

class StoryPage {
  final int index;
  final String text;
  final String? imageUrl; // Firebase/remote URL (preferred)
  final String? imageAsset; // local asset fallback
  final List<StoryChoice> choices;
  final String? audioUrl;
final String? audioAsset;
final String? backgroundAsset;
final String? heroAsset;
final String? friendAsset;
final String? objectAsset;
final String? emotionEmoji;

  StoryPage({
    required this.index,
  required this.text,
  this.imageUrl,
  this.imageAsset,
  this.audioUrl,
  this.audioAsset,
  this.choices = const [],
  this.backgroundAsset,
  this.emotionEmoji,
  this.friendAsset,
  this.heroAsset,
  this.objectAsset
  });

  bool get hasChoices => choices.isNotEmpty;
}

class StoryChoice {
  final String id;
  final String label;
  final int nextPageIndex;
  final String? imageAsset;

  StoryChoice({
    required this.id,
    required this.label,
    required this.nextPageIndex,
    this.imageAsset,
  });

  factory StoryChoice.fromJson(Map<String, dynamic> json) {
    return StoryChoice(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      nextPageIndex: (json['nextPageIndex'] as num?)?.toInt() ?? 0,
      imageAsset: json['imageAsset'] as String?,
    );
  }
}

class StoryPage {
  final int index;
  final String text;
  final String? imageUrl;
  final String? imageAsset;
  final String? backgroundAsset;
final String? heroAsset;
final String? friendAsset;
final String? objectAsset;
final String? emotionEmoji;
 // final List<StoryChoice> choices;

  StoryPage({
    required this.index,
    required this.text,
    this.imageUrl,
    this.imageAsset,
    this.backgroundAsset,
    this.emotionEmoji,
    this.friendAsset,
    this.heroAsset,
    this.objectAsset
    
   // this.choices = const [],
  });

}
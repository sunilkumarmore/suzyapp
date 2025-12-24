class StoryPage {
  final int index;
  final String text;
  final String? imageUrl;
  final String? imageAsset;
 // final List<StoryChoice> choices;

  StoryPage({
    required this.index,
    required this.text,
    this.imageUrl,
    this.imageAsset,
   // this.choices = const [],
  });

}
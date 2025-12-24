class Story {
  final String id;
  final String title;
  final String language; // 'en' | 'te' | 'mixed'
  //final String difficulty; // 'Easy' | 'Medium' | 'Hard'
  final List<StoryPage> pages;
  final String ageBand; // e.g. '2-3', '4-5', '6-7'

  Story({
    required this.id,
    required this.title,
    required this.language,
    required this.pages,
    required this.ageBand
  });
}

class StoryPage {
  final int index;
  final String text;
  final String? imageUrl;
  final String? imageAsset;
  final List<StoryChoice> choices;

  StoryPage({
    required this.index,
    required this.text,
    this.imageUrl,
    this.imageAsset,
    this.choices = const [],
  });

  bool get hasChoices => choices.isNotEmpty;
}

class StoryChoice {
  final String id;
  final String label;
  final int nextPageIndex;

  StoryChoice({
    required this.id,
    required this.label,
    required this.nextPageIndex,
  });
}

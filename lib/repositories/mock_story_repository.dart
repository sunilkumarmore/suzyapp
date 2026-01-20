import '../models/story.dart';          // contains Story + (maybe) StoryPage
import '../models/story_dto.dart';
import 'asset_story_loader.dart';
import 'story_repository.dart';



class MockStoryRepository implements StoryRepository {
  List<Story>? _cache;

  Future<List<Story>> _ensureLoaded() async {
    if (_cache != null) return _cache!;
    final dtos = await AssetStoryLoader.loadAll();
    _cache = dtos.map(_toDomain).toList();
    return _cache!;
  }

Story _toDomain(StoryDto d) {
  return Story(
    id: d.id,
    title: d.title,
    language: d.language,
    ageBand: d.ageBand,
    coverAsset: (d.coverAsset ?? '').trim(),
   pages: List.generate(d.pages.length, (i) {
  final p = d.pages[i];
 return StoryPage(
  index: i,
  text: p.text,
  imageUrl: p.imageUrl,
  imageAsset: p.imageAsset,
  audioUrl: p.audioUrl,
  audioAsset: p.audioAsset,
  choices: const [],
);
}),

  );
}
  @override
  Future<List<Story>> listStories({required StoryQuery query}) async {
    final stories = await _ensureLoaded();
    final q = query.searchText.trim().toLowerCase();
    final qLang = query.language?.trim().toLowerCase();
    final qAge = query.ageBand?.trim().toLowerCase();
    String norm(String s) => s.trim().toLowerCase();
String normAge(String s) => norm(s).replaceAll('–', '-'); // en-dash → hyphen


    return stories.where((s) {
   final title = norm(s.title);
  final id = norm(s.id);
  final lang = norm(s.language);
  final age = normAge(s.ageBand);

  // Query
  final queryText = norm(q); // q is your searchText already trimmed, ok if empty

  // Search: title OR id (much more usable)
  final matchesSearch =
      queryText.isEmpty || title.contains(queryText) || id.contains(queryText);

  // Language: normalize query too
  final matchesLang =
      qLang == null || qLang.trim().isEmpty || lang == norm(qLang);

  // Age: normalize query too (handles 4–5 vs 4-5)
  final matchesAge =
      qAge == null || qAge.trim().isEmpty || age == normAge(qAge);

  return matchesSearch && matchesLang && matchesAge;
}).toList();
    
  }

  @override
  Future<Story> getStoryById(String id) async {
    if (id == kMakeAStoryDemoId) {
      return _demoMakeAStory();
    }
    final stories = await _ensureLoaded();
    return stories.firstWhere((s) => s.id == id);
  }

  Story _demoMakeAStory() {
    return Story(
      id: kMakeAStoryDemoId,
      title: 'Make a Story',
      language: 'en',
      ageBand: '4-5',
      coverAsset: null,
      pages: [
        StoryPage(
          index: 0,
          text: 'Let us make a story! Who should be the hero?',
          choices: [
            StoryChoice(id: 'hero_bunny', label: 'A brave bunny', nextPageIndex: 1),
            StoryChoice(id: 'hero_bear', label: 'A curious bear', nextPageIndex: 2),
          ],
        ),
        StoryPage(
          index: 1,
          text: 'Great! The bunny loves adventures. Where should we go?',
          choices: [
            StoryChoice(id: 'place_forest', label: 'To the forest', nextPageIndex: 3),
            StoryChoice(id: 'place_beach', label: 'To the beach', nextPageIndex: 3),
          ],
        ),
        StoryPage(
          index: 2,
          text: 'Awesome! The bear is ready. What do we find first?',
          choices: [
            StoryChoice(id: 'find_treasure', label: 'A hidden treasure', nextPageIndex: 3),
            StoryChoice(id: 'find_friend', label: 'A new friend', nextPageIndex: 3),
          ],
        ),
        StoryPage(
          index: 3,
          text: 'Your story is coming to life. Want to make another choice?',
          choices: [
            StoryChoice(id: 'again_yes', label: 'Yes, keep going', nextPageIndex: 0),
          ],
        ),
      ],
    );
  }
}

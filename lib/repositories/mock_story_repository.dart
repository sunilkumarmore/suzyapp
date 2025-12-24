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
   pages: List.generate(d.pages.length, (i) {
  final p = d.pages[i];
  return StoryPage(
    index: i,
    text: p.text,
    imageUrl: p.imageUrl,
    imageAsset: p.imageAsset,
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

    return stories.where((s) {
      final t = s.title.toLowerCase();
      final l = s.language.toLowerCase();
      final a = s.ageBand.toLowerCase();
      return (q.isEmpty || t.contains(q)) &&
             (qLang == null || l == qLang) &&
             (qAge == null || a == qAge);
    }).toList();
  }

  @override
  Future<Story> getStoryById(String id) async {
    final stories = await _ensureLoaded();
    return stories.firstWhere((s) => s.id == id);
  }
}

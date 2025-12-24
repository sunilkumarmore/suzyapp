import '../models/story.dart';

class StoryQuery {
  final String searchText;
  final String? language; // 'en'|'te'|'mixed'
  final String? ageBand;  // '2-3'|'4-5'|'6-7'

 const StoryQuery({
    this.searchText = '',
    this.language,
    this.ageBand,
  });
}




abstract class StoryRepository {
  Future<List<Story>> listStories({required StoryQuery query});
  Future<Story> getStoryById(String id);
}
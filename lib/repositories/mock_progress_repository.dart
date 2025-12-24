import '../models/reading_progress.dart';
import '../models/story_progress.dart';
import 'progress_repository.dart';

class MockProgressRepository implements ProgressRepository {
  // GLOBAL reading progress (Continue)
  ReadingProgress? _readingProgress;

  // PER-STORY progress (history / completion)
  final Map<String, StoryProgress> _storyProgressMap = {};

  // ===== New API =====

  @override
  Future<ReadingProgress?> getReadingProgress() async {
    return _readingProgress;
  }

  @override
  Future<void> saveReadingProgress(ReadingProgress progress) async {
    _readingProgress = progress;
  }

  @override
  Future<void> clearReadingProgress() async {
    _readingProgress = null;
  }

  @override
  Future<StoryProgress?> getStoryProgress(String storyId) async {
    return _storyProgressMap[storyId];
  }

  @override
  Future<List<StoryProgress>> getAllStoryProgress() async {
    return _storyProgressMap.values.toList();
  }

  @override
  Future<void> saveStoryProgress(StoryProgress progress) async {
    _storyProgressMap[progress.storyId] = progress;
  }

  // ===== Backward compatibility (old code) =====

  @override
  Future<ReadingProgress?> getLastProgress() async {
    return getReadingProgress();
  }

  @override
  Future<void> saveProgress(ReadingProgress progress) async {
    await saveReadingProgress(progress);
  }

  @override
  Future<void> clearProgress() async {
    await clearReadingProgress();
  }
}

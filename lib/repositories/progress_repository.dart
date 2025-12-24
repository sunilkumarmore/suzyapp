import '../models/reading_progress.dart';
import '../models/story_progress.dart';

abstract class ProgressRepository {
  // ===== NEW (clear naming) =====
  Future<ReadingProgress?> getReadingProgress();
  Future<void> saveReadingProgress(ReadingProgress progress);
  Future<void> clearReadingProgress();

  Future<StoryProgress?> getStoryProgress(String storyId);
  Future<List<StoryProgress>> getAllStoryProgress();
  Future<void> saveStoryProgress(StoryProgress progress);

  // ===== OLD (compatibility) =====
  @Deprecated('Use getReadingProgress()')
  Future<ReadingProgress?> getLastProgress() => getReadingProgress();

  @Deprecated('Use saveReadingProgress()')
  Future<void> saveProgress(ReadingProgress progress) => saveReadingProgress(progress);

  @Deprecated('Use clearReadingProgress()')
  Future<void> clearProgress() => clearReadingProgress();
}

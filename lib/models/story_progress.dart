class StoryProgress {
  final String storyId;
  final int lastPageIndex;
  final bool completed;
  final DateTime lastOpenedAt;

  StoryProgress({
    required this.storyId,
    required this.lastPageIndex,
    required this.completed,
    required this.lastOpenedAt,
  });

  StoryProgress copyWith({
    int? lastPageIndex,
    bool? completed,
    DateTime? lastOpenedAt,
  }) {
    return StoryProgress(
      storyId: storyId,
      lastPageIndex: lastPageIndex ?? this.lastPageIndex,
      completed: completed ?? this.completed,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }
}

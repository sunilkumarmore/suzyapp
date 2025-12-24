class ReadingProgress {
  final String storyId;
  final int pageIndex;
  final DateTime updatedAt;

  ReadingProgress({
    required this.storyId,
    required this.pageIndex,
    required this.updatedAt,
  });

  ReadingProgress copyWith({int? pageIndex, DateTime? updatedAt}) {
    return ReadingProgress(
      storyId: storyId,
      pageIndex: pageIndex ?? this.pageIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

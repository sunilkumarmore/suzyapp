class ColoringPage {
  final String id;
  final String title;
  final String ageBand;
  final String imageAsset;
  final String maskAsset;

  ColoringPage({
    required this.id,
    required this.title,
    required this.ageBand,
    required this.imageAsset,
    required this.maskAsset,
  });

  factory ColoringPage.fromJson(Map<String, dynamic> json) {
    return ColoringPage(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      ageBand: (json['ageBand'] as String? ?? '').replaceAll('–', '-'),
      imageAsset: json['imageAsset'] as String? ?? '',
      maskAsset: json['maskAsset'] as String? ?? '',
    );
  }
}

class AdventureTemplateBundle {
  final List<AdventureTemplate> templates;

  AdventureTemplateBundle({required this.templates});

  factory AdventureTemplateBundle.fromJson(Map<String, dynamic> json) {
    final list = (json['templates'] as List<dynamic>? ?? [])
        .map((e) => AdventureTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
    return AdventureTemplateBundle(templates: list);
  }
}

class AdventureTemplate {
  final String id;
  final String title;
  final String ageBand; // "2-3"
  final List<String> slots; // ["hero","place",...]
  final Map<String, List<AdventureChoice>> choices; // slot -> choices
  final List<AdventurePageTemplate> pages; // text with {tokens}
  final String? coverAsset;

  AdventureTemplate({
    required this.id,
    required this.title,
    required this.ageBand,
    required this.slots,
    required this.choices,
    required this.pages,
    required this.coverAsset,
  });

  factory AdventureTemplate.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as List<dynamic>? ?? []).cast<String>();

    final cover = _string(json['coverAsset']) ??
        _string(json['coverUrl']) ??
        _string(json['cover_url']) ??
        _string(json['coverPath']) ??
        _string(json['cover_path']);

    final rawChoices = (json['choices'] as Map<String, dynamic>? ?? {});
    final parsedChoices = <String, List<AdventureChoice>>{};
    for (final entry in rawChoices.entries) {
      final arr = (entry.value as List<dynamic>? ?? [])
          .map((e) => AdventureChoice.fromJson(e as Map<String, dynamic>))
          .toList();
      parsedChoices[entry.key] = arr;
    }

    final pages = (json['pages'] as List<dynamic>? ?? [])
        .map((e) => AdventurePageTemplate.fromJson(e as Map<String, dynamic>))
        .toList();

    return AdventureTemplate(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Adventure',
      ageBand: (json['ageBand'] as String? ?? '2-3').replaceAll('–', '-'),
      slots: slots,
      choices: parsedChoices,
      pages: pages,
      coverAsset: cover,
    );
  }

}

class AdventureChoice {
  final String id;
  final String label;
  final String emoji;
  final String? imageAsset;

  AdventureChoice({
    required this.id,
    required this.label,
    required this.emoji,
    this.imageAsset,
  });

  factory AdventureChoice.fromJson(Map<String, dynamic> json) {
    return AdventureChoice(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '?o"',
      imageAsset: _string(json['imageAsset']) ??
          _string(json['imageUrl']) ??
          _string(json['image_url']) ??
          _string(json['image']) ??
          _string(json['imagePath']) ??
          _string(json['image_path']),
    );
  }
}

class AdventurePageTemplate {
  final String text;
  final String? imageAsset;
  final List<AdventurePageChoice> choices;

  AdventurePageTemplate({
    required this.text,
    this.imageAsset,
    this.choices = const [],
  });

  bool get hasChoices => choices.isNotEmpty;

  factory AdventurePageTemplate.fromJson(Map<String, dynamic> json) {
    return AdventurePageTemplate(
      text: json['text'] as String? ?? '',
      imageAsset: _string(json['imageAsset']) ??
          _string(json['imageUrl']) ??
          _string(json['image_url']) ??
          _string(json['image']) ??
          _string(json['imagePath']) ??
          _string(json['image_path']),
      choices: (json['choices'] as List? ?? const [])
          .map((e) => AdventurePageChoice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AdventurePageChoice {
  final String id;
  final String label;
  final int nextPageIndex;
  final String? imageAsset;

  AdventurePageChoice({
    required this.id,
    required this.label,
    required this.nextPageIndex,
    this.imageAsset,
  });

  factory AdventurePageChoice.fromJson(Map<String, dynamic> json) {
    return AdventurePageChoice(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      nextPageIndex: (json['nextPageIndex'] as num?)?.toInt() ?? 0,
      imageAsset: _string(json['imageAsset']) ??
          _string(json['imageUrl']) ??
          _string(json['image_url']) ??
          _string(json['image']) ??
          _string(json['imagePath']) ??
          _string(json['image_path']),
    );
  }
}

String? _string(dynamic v) {
  if (v is String) return v.trim();
  return null;
}

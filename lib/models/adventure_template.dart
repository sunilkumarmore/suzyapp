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

  AdventureTemplate({
    required this.id,
    required this.title,
    required this.ageBand,
    required this.slots,
    required this.choices,
    required this.pages,
  });

  factory AdventureTemplate.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as List<dynamic>? ?? []).cast<String>();

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
    );
  }
}

class AdventureChoice {
  final String id;
  final String label;
  final String emoji;

  AdventureChoice({
    required this.id,
    required this.label,
    required this.emoji,
  });

  factory AdventureChoice.fromJson(Map<String, dynamic> json) {
    return AdventureChoice(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '✨',
    );
  }
}

class AdventurePageTemplate {
  final String text;

  AdventurePageTemplate({required this.text});

  factory AdventurePageTemplate.fromJson(Map<String, dynamic> json) {
    return AdventurePageTemplate(text: json['text'] as String? ?? '');
    }
}

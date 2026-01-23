import 'package:flutter/foundation.dart';

import '../models/adventure_template.dart';
import 'adventure_template_repository.dart';

class CompositeAdventureTemplateRepository implements AdventureTemplateRepository {
  final AdventureTemplateRepository primary;
  final AdventureTemplateRepository fallback;

  CompositeAdventureTemplateRepository({
    required this.primary,
    required this.fallback,
  });

  @override
  Future<List<AdventureTemplate>> loadTemplates() async {
    List<AdventureTemplate> remote = [];
    try {
      remote = await primary.loadTemplates();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CompositeAdventureTemplateRepository primary failed: $e');
      }
    }

    List<AdventureTemplate> local = [];
    try {
      local = await fallback.loadTemplates();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CompositeAdventureTemplateRepository fallback failed: $e');
      }
    }

    if (remote.isEmpty) return local;
    if (local.isEmpty) return remote;

    final merged = <String, AdventureTemplate>{};
    for (final t in local) {
      merged[t.id] = t;
    }
    for (final t in remote) {
      merged[t.id] = t; // remote overrides local on id clash
    }
    return merged.values.toList();
  }
}

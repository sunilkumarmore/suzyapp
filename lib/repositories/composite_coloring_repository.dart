import 'package:flutter/foundation.dart';

import '../models/coloring_page.dart';
import 'coloring_repository.dart';

class CompositeColoringRepository implements ColoringRepository {
  final ColoringRepository primary;
  final ColoringRepository fallback;

  CompositeColoringRepository({
    required this.primary,
    required this.fallback,
  });

  @override
  Future<List<ColoringPage>> listPages({String? ageBand, String searchText = ''}) async {
    List<ColoringPage> remote = [];
    try {
      remote = await primary.listPages(ageBand: ageBand, searchText: searchText);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CompositeColoringRepository primary list failed: $e');
      }
    }

    List<ColoringPage> local = [];
    try {
      local = await fallback.listPages(ageBand: ageBand, searchText: searchText);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CompositeColoringRepository fallback list failed: $e');
      }
    }

    if (remote.isEmpty) return local;
    if (local.isEmpty) return remote;

    final merged = <String, ColoringPage>{};
    for (final p in local) {
      merged[p.id] = p;
    }
    for (final p in remote) {
      merged[p.id] = p; // remote overrides local on id clash
    }
    return merged.values.toList();
  }

  @override
  Future<ColoringPage> getById(String id) async {
    try {
      return await primary.getById(id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CompositeColoringRepository primary get failed: $e');
      }
    }
    return fallback.getById(id);
  }
}


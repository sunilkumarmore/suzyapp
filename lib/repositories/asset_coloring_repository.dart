import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/coloring_page.dart';
import 'coloring_repository.dart';

class AssetColoringRepository implements ColoringRepository {
  final String assetPath;

  AssetColoringRepository({
    this.assetPath = 'assets/coloring/coloring_pages.json',
  });

  Future<List<ColoringPage>> _loadAll() async {
    final raw = await rootBundle.loadString(assetPath);
    final jsonMap = json.decode(raw) as Map<String, dynamic>;
    final list = (jsonMap['pages'] as List<dynamic>? ?? []);
    return list.map((e) => ColoringPage.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ColoringPage>> listPages({String? ageBand, String searchText = ''}) async {
    final pages = await _loadAll();
    final q = searchText.trim().toLowerCase();
    final age = ageBand?.trim();

    return pages.where((p) {
      final title = p.title.trim().toLowerCase();
      final matchesSearch = q.isEmpty || title.contains(q);
      final matchesAge = age == null || age.isEmpty || p.ageBand == age;
      return matchesSearch && matchesAge;
    }).toList();
  }

  @override
  Future<ColoringPage> getById(String id) async {
    final pages = await _loadAll();
    return pages.firstWhere((p) => p.id == id);
  }
}

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:suzyapp/models/adventure_template.dart';
import 'adventure_template_repository.dart';

class AssetAdventureTemplateRepository implements AdventureTemplateRepository {
  final String assetPath;

  AssetAdventureTemplateRepository({
    this.assetPath = 'assets/templates/adventure_templates.json',
  });

  @override
  Future<List<AdventureTemplate>> loadTemplates() async {
    final raw = await rootBundle.loadString(assetPath);
    final jsonMap = json.decode(raw) as Map<String, dynamic>;
    return AdventureTemplateBundle.fromJson(jsonMap).templates;
  }
}

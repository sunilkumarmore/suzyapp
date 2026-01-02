import 'package:suzyapp/models/adventure_template.dart';



abstract class AdventureTemplateRepository {
  Future<List<AdventureTemplate>> loadTemplates();
}

import '../models/coloring_page.dart';

abstract class ColoringRepository {
  Future<List<ColoringPage>> listPages({String? ageBand, String searchText = ''});
  Future<ColoringPage> getById(String id);
}

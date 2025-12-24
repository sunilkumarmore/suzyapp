import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/story_dto.dart';

class AssetStoryLoader {
  static Future<List<StoryDto>> loadAll() async {
    final indexStr = await rootBundle.loadString('assets/stories/index.json');
    final files = (jsonDecode(indexStr)['stories'] as List).cast<String>();

    final List<StoryDto> out = [];
    for (final f in files) {
      final s = await rootBundle.loadString('assets/stories/$f');
      out.add(StoryDto.fromJson(jsonDecode(s)));
    }
    return out;
  }
}

import 'package:shared_preferences/shared_preferences.dart';

const _kChildName = 'child_name_v1';

Future<String?> loadChildName() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_kChildName);
  return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
}

Future<void> saveChildName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kChildName, name.trim());
}

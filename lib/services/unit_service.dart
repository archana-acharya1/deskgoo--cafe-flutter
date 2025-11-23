import 'package:shared_preferences/shared_preferences.dart';

class UnitService {
  static const String _key = "custom_units";

  static Future<List<String>> getSavedUnits() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> saveUnit(String unit) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing = prefs.getStringList(_key) ?? [];

    if (!existing.contains(unit.toLowerCase())) {
      existing.add(unit.toLowerCase());
      await prefs.setStringList(_key, existing);
    }
  }
}

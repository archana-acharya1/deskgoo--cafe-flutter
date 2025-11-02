import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/restaurant_settings_service.dart';

// Provider for restaurant settings
final restaurantSettingsProvider =
StateNotifierProvider<RestaurantSettingsNotifier, Map<String, dynamic>>(
      (ref) => RestaurantSettingsNotifier(''), // pass token later
);

class RestaurantSettingsNotifier extends StateNotifier<Map<String, dynamic>> {
  final String token;

  RestaurantSettingsNotifier(this.token) : super({}) {
    fetchSettings();
  }

  Future<void> fetchSettings() async {
    final service = RestaurantSettingsService(token);
    final settings = await service.getSettings();
    if (settings != null) {
      state = settings;
    }
  }

  void updateSettings(Map<String, dynamic> newSettings) {
    state = newSettings;
  }
}

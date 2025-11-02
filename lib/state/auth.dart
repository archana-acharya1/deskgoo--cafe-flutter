import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AuthState {
  final String token;
  final String roleName;
  final String restaurantId;

  const AuthState({
    required this.token,
    required this.roleName,
    required this.restaurantId,
  });

  AuthState copyWith({
    String? token,
    String? roleName,
    String? restaurantId,
  }) {
    return AuthState(
      token: token ?? this.token,
      roleName: roleName ?? this.roleName,
      restaurantId: restaurantId ?? this.restaurantId,
    );
  }
}

final authStateProvider = StateProvider<AuthState?>((ref) => null);

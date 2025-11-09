import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config.dart';
import 'auth.dart';

class SocketService {
  late final IO.Socket _socket;

  IO.Socket get instance => _socket;

  void init(String token) {
    _socket = IO.io(
      AppConfig.socketBase,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket.connect();
  }

  void dispose() {
    _socket.dispose();
  }
}

final socketProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  final token = ref.read(authStateProvider)?.token ?? '';
  service.init(token);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

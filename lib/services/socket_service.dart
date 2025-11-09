import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  late IO.Socket socket;

  void connect(String baseUrl, String restaurantId) {
    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    socket.connect();

    socket.onConnect((_) {
      print(' Socket connected: ${socket.id}');
      socket.emit('joinRestaurant', restaurantId);
      print(' Joined restaurant: $restaurantId');
    });

    socket.onDisconnect((_) => print(' Socket disconnected'));
    socket.onConnectError((err) => print(' Socket connect error: $err'));
    socket.onError((err) => print(' Socket general error: $err'));
  }

  void onAreaCreated(Function(Map<String, dynamic>) callback) {
    socket.on('areaCreated', (data) {
      print('Area Created Event: $data');
      final area = _extractMap(data, 'area');
      if (area != null) callback(area);
    });
  }

  void onAreaUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('areaUpdated', (data) {
      print('Area Updated Event: $data');
      final area = _extractMap(data, 'area');
      if (area != null) callback(area);
    });
  }

  void onAreaDeleted(Function(String) callback) {
    socket.on('areaDeleted', (data) {
      print('Area Deleted Event: $data');
      if (data is Map && data.containsKey('areaId')) callback(data['areaId']);
    });
  }

  void onCategoryCreated(Function(Map<String, dynamic>) callback) {
    socket.on('categoryCreated', (data) {
      print('Category Created Event: $data');
      final category = _extractMap(data, 'category');
      if (category != null) callback(category);
    });
  }

  void onCategoryUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('categoryUpdated', (data) {
      print('Category Updated Event: $data');
      final category = _extractMap(data, 'category');
      if (category != null) callback(category);
    });
  }

  void onCategoryDeleted(Function(String) callback) {
    socket.on('categoryDeleted', (data) {
      print('Category Deleted Event: $data');
      if (data is Map && data.containsKey('categoryId')) callback(data['categoryId']);
    });
  }

  void onItemCreated(Function(Map<String, dynamic>) callback) {
    socket.on('itemCreated', (data) {
      print('Item Created Event: $data');
      final item = _extractMap(data, 'item');
      if (item != null) callback(item);
    });
  }

  void onItemUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('itemUpdated', (data) {
      print('Item Updated Event: $data');
      final item = _extractMap(data, 'item');
      if (item != null) callback(item);
    });
  }

  void onItemDeleted(Function(String) callback) {
    socket.on('itemDeleted', (data) {
      print('Item Deleted Event: $data');
      if (data is Map && data.containsKey('itemId')) callback(data['itemId']);
    });
  }

  void onTableCreated(Function(Map<String, dynamic>) callback) {
    socket.on('tableCreated', (data) {
      print('Table Created Event: $data');
      final table = _extractMap(data, 'table');
      if (table != null) callback(table);
    });
  }

  void onTableUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('tableUpdated', (data) {
      print('Table Updated Event: $data');
      final table = _extractMap(data, 'table');
      if (table != null) callback(table);
    });
  }

  void onTableDeleted(Function(String) callback) {
    socket.on('tableDeleted', (data) {
      print('Table Deleted Event: $data');
      if (data is Map && data.containsKey('tableId')) {
        callback(data['tableId']);
      } else if (data is String) {
        callback(data);
      }
    });
  }

  void disconnect() {
    try {
      socket.disconnect();
    } catch (_) {}
  }

  Map<String, dynamic>? _extractMap(dynamic data, String key) {
    if (data is Map<String, dynamic> && data.containsKey(key)) {
      final v = data[key];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } else if (data is Map && data.containsKey(key)) {
      return Map<String, dynamic>.from(data[key]);
    }
    return null;
  }
}

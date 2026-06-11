import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

typedef EventCallback = void Function(dynamic data);

class WebSocketService {
  io.Socket? _socket;
  final Map<String, List<EventCallback>> _listeners = {};

  void connect(String accessToken) {
    _socket = io.io(
      AppConfig.wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'token': accessToken})
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _notifyListeners('connected', null);
      })
      ..onDisconnect((_) {
        _notifyListeners('disconnected', null);
      })
      ..on('attendance.clock_in',
          (d) => _notifyListeners('attendance.clock_in', d))
      ..on('attendance.clock_out',
          (d) => _notifyListeners('attendance.clock_out', d))
      ..on('attendance.alert',
          (d) => _notifyListeners('attendance.alert', d))
      ..on('notification.new',
          (d) => _notifyListeners('notification.new', d));
  }

  void on(String event, EventCallback callback) {
    _listeners[event] = [...(_listeners[event] ?? []), callback];
  }

  void off(String event, EventCallback callback) {
    _listeners[event]?.remove(callback);
  }

  void _notifyListeners(String event, dynamic data) {
    for (final cb in _listeners[event] ?? []) {
      cb(data);
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _listeners.clear();
  }

  bool get isConnected => _socket?.connected ?? false;
}

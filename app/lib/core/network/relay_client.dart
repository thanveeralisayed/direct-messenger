import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

enum RelayConnectionState { disconnected, connecting, connected }

class RelayClient {
  String baseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  RelayConnectionState _state = RelayConnectionState.disconnected;
  RelayConnectionState get state => _state;

  final _stateController = StreamController<RelayConnectionState>.broadcast();
  Stream<RelayConnectionState> get onStateChanged => _stateController.stream;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived => _messageController.stream;

  final _ackController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onServerAck => _ackController.stream;

  final _deliveryReceiptController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onDeliveryReceipt => _deliveryReceiptController.stream;

  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  String? _currentToken;
  bool _intentionalClose = false;

  RelayClient({required this.baseUrl});

  // --- REST Endpoints ---

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String identityPublicKey,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/auth/register');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'identityPublicKey': identityPublicKey,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201) {
      throw Exception(data['error'] ?? 'Registration failed');
    }
    return data;
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/auth/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Login failed');
    }
    return data;
  }

  Future<Map<String, dynamic>> getPublicKey(String username) async {
    final uri = Uri.parse('$baseUrl/api/v1/users/$username/key');
    final response = await http.get(uri);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to retrieve public key');
    }
    return data;
  }

  // --- WebSocket Connection ---

  void connect(String token) {
    _currentToken = token;
    _intentionalClose = false;
    _establishWebSocket();
  }

  void _establishWebSocket() {
    if (_currentToken == null || _intentionalClose) return;

    _updateState(RelayConnectionState.connecting);

    try {
      final wsUri = Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/ws?token=$_currentToken',
      );

      _channel = WebSocketChannel.connect(wsUri);

      _sub = _channel!.stream.listen(
        (data) {
          _handleIncoming(data.toString());
        },
        onDone: () {
          _handleDisconnect();
        },
        onError: (err) {
          _handleDisconnect();
        },
      );

      _updateState(RelayConnectionState.connected);
      _startHeartbeat();
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleIncoming(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String?;

      switch (type) {
        case 'auth_success':
          _updateState(RelayConnectionState.connected);
          break;
        case 'message':
          _messageController.add(map);
          break;
        case 'server_ack':
          _ackController.add(map);
          break;
        case 'delivery_receipt':
          _deliveryReceiptController.add(map);
          break;
        case 'typing':
          _typingController.add(map);
          break;
        case 'pong':
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _sub?.cancel();
    _updateState(RelayConnectionState.disconnected);

    if (!_intentionalClose) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        _establishWebSocket();
      });
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_state == RelayConnectionState.connected) {
        sendRaw({'type': 'ping'});
      }
    });
  }

  void _updateState(RelayConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  void sendRaw(Map<String, dynamic> data) {
    if (_channel != null && _state == RelayConnectionState.connected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void sendMessagePacket({
    required String id,
    required String to,
    required int timestamp,
    required String ephemeralPublicKey,
    required String iv,
    required String ciphertext,
  }) {
    sendRaw({
      'type': 'message',
      'id': id,
      'to': to,
      'timestamp': timestamp,
      'ephemeralPublicKey': ephemeralPublicKey,
      'iv': iv,
      'ciphertext': ciphertext,
    });
  }

  void sendDeliveryAck({required String messageId, required String sender}) {
    sendRaw({
      'type': 'delivery_ack',
      'id': messageId,
      'sender': sender,
    });
  }

  void sendTyping({required String to, required bool isTyping}) {
    sendRaw({
      'type': 'typing',
      'to': to,
      'isTyping': isTyping,
    });
  }

  void disconnect() {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _updateState(RelayConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
    _ackController.close();
    _deliveryReceiptController.close();
    _typingController.close();
  }
}

import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/key_storage.dart';
import '../core/network/relay_client.dart';

class AuthProvider extends ChangeNotifier {
  final CryptoService _crypto = CryptoService();
  final KeyStorage _keyStorage = KeyStorage();
  late RelayClient _relayClient;

  String? _username;
  String? _token;
  SimpleKeyPair? _identityKeyPair;
  String? _publicKeyBase64;
  String? _safetyNumber;
  String _serverUrl = 'http://10.0.2.2:8080';
  bool _isLoading = true;
  String? _errorMessage;

  String? get username => _username;
  String? get token => _token;
  SimpleKeyPair? get identityKeyPair => _identityKeyPair;
  String? get publicKeyBase64 => _publicKeyBase64;
  String? get safetyNumber => _safetyNumber;
  String get serverUrl => _serverUrl;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null && _username != null && _identityKeyPair != null;
  String? get errorMessage => _errorMessage;
  RelayClient get relayClient => _relayClient;
  CryptoService get crypto => _crypto;

  AuthProvider() {
    _relayClient = RelayClient(baseUrl: _serverUrl);
    _initialize();
  }

  Future<void> _initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _serverUrl = await _keyStorage.getServerUrl();
      _relayClient = RelayClient(baseUrl: _serverUrl);

      final savedToken = await _keyStorage.getToken();
      final savedUser = await _keyStorage.getUsername();
      final savedPrivKey = await _keyStorage.getPrivateKey();
      final savedPubKey = await _keyStorage.getPublicKey();

      if (savedToken != null && savedUser != null && savedPrivKey != null) {
        _token = savedToken;
        _username = savedUser;
        _publicKeyBase64 = savedPubKey;
        _identityKeyPair = await _crypto.importPrivateKey(savedPrivKey);

        if (_publicKeyBase64 != null) {
          _safetyNumber = await _crypto.generateFingerprint(_publicKeyBase64!);
        }

        // Connect WebSocket
        _relayClient.connect(_token!);
      }
    } catch (e) {
      _errorMessage = 'Failed to restore session: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateServerUrl(String newUrl) async {
    _serverUrl = newUrl.trim();
    await _keyStorage.setServerUrl(_serverUrl);
    _relayClient.disconnect();
    _relayClient = RelayClient(baseUrl: _serverUrl);
    if (isLoggedIn) {
      _relayClient.connect(_token!);
    }
    notifyListeners();
  }

  Future<bool> register({required String username, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Generate identity key pair locally on device
      final keyPair = await _crypto.generateIdentityKeyPair();
      final pubKeyStr = await _crypto.exportPublicKey(keyPair);
      final privKeyStr = await _crypto.exportPrivateKey(keyPair);

      // 2. Register user on server with identity public key
      final result = await _relayClient.register(
        username: username,
        password: password,
        identityPublicKey: pubKeyStr,
      );

      final token = result['token'] as String;
      final savedUsername = (result['username'] as String).toLowerCase();

      // 3. Save locally to secure storage
      await _keyStorage.saveAuthSession(
        token: token,
        username: savedUsername,
        privateKeyBase64: privKeyStr,
        publicKeyBase64: pubKeyStr,
      );

      _username = savedUsername;
      _token = token;
      _identityKeyPair = keyPair;
      _publicKeyBase64 = pubKeyStr;
      _safetyNumber = await _crypto.generateFingerprint(pubKeyStr);

      // Connect WebSocket
      _relayClient.connect(token);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({required String username, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _relayClient.login(
        username: username,
        password: password,
      );

      final token = result['token'] as String;
      final serverUsername = (result['username'] as String).toLowerCase();
      final serverPubKey = result['identityPublicKey'] as String;

      // Check if this device already holds the private key for this user
      final savedUser = await _keyStorage.getUsername();
      final savedPrivKey = await _keyStorage.getPrivateKey();

      SimpleKeyPair keyPair;
      if (savedUser == serverUsername && savedPrivKey != null) {
        keyPair = await _crypto.importPrivateKey(savedPrivKey);
      } else {
        // If logging in on a new device where private key does not exist yet:
        // In a zero-knowledge E2EE system, generate a new device keypair or prompt.
        // For initial stage, generate new keypair and use for new messages.
        keyPair = await _crypto.generateIdentityKeyPair();
        final newPrivStr = await _crypto.exportPrivateKey(keyPair);
        await _keyStorage.saveAuthSession(
          token: token,
          username: serverUsername,
          privateKeyBase64: newPrivStr,
          publicKeyBase64: serverPubKey,
        );
      }

      _username = serverUsername;
      _token = token;
      _identityKeyPair = keyPair;
      _publicKeyBase64 = serverPubKey;
      _safetyNumber = await _crypto.generateFingerprint(serverPubKey);

      _relayClient.connect(token);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _relayClient.disconnect();
    await _keyStorage.clearSession();
    _username = null;
    _token = null;
    _identityKeyPair = null;
    _publicKeyBase64 = null;
    _safetyNumber = null;
    notifyListeners();
  }
}

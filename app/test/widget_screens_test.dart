import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:direct/core/crypto/crypto_service.dart';
import 'package:direct/core/network/relay_client.dart';
import 'package:direct/ui/dialogs/safety_number_dialog.dart';
import 'package:direct/ui/dialogs/security_settings_dialog.dart';
import 'package:direct/ui/screens/login_screen.dart';
import 'package:direct/providers/auth_provider.dart';

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  String? username;
  @override
  String? token;
  @override
  SimpleKeyPair? identityKeyPair;
  @override
  String? publicKeyBase64;
  @override
  String? safetyNumber;
  @override
  String serverUrl = 'http://localhost:8080';
  @override
  bool isLoading = false;
  @override
  bool isLoggedIn = false;
  @override
  String? errorMessage;
  @override
  late RelayClient relayClient = RelayClient(baseUrl: 'http://localhost:8080');
  @override
  late CryptoService crypto = CryptoService();

  @override
  Future<bool> register({required String username, required String password}) async {
    return true;
  }

  @override
  Future<bool> login({required String username, required String password}) async {
    return true;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> updateServerUrl(String newUrl) async {
    serverUrl = newUrl;
    notifyListeners();
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (MethodCall call) async {
        if (call.method == 'isDeviceSupported') return true;
        if (call.method == 'canCheckBiometrics') return true;
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.direct.chat/security'),
      (MethodCall call) async {
        return null;
      },
    );
  });

  group('UI Screens & Dialogs Comprehensive Widget Tests', () {
    testWidgets('SafetyNumberDialog renders fingerprint and peer verification elements', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafetyNumberDialog(
              username: 'bob',
              publicKey: 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA-test-key',
              safetyNumber: '1111 2222 3333 4444 5555 6666',
              isVerified: false,
              isPeer: true,
            ),
          ),
        ),
      );

      // Verify title shows peer username
      expect(find.text('Verify @bob'), findsOneWidget);

      // Verify safety number is displayed
      expect(find.text('1111 2222 3333 4444 5555 6666'), findsOneWidget);

      // Verify "Mark Verified" action button exists
      expect(find.text('Mark Verified'), findsOneWidget);

      // Verify "Scan @bob's Code" button exists for peers
      expect(find.text("Scan @bob's Code"), findsOneWidget);
    });

    testWidgets('SecuritySettingsDialog renders Screenshot and Biometric protection switches', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecuritySettingsDialog(),
          ),
        ),
      );

      // Let async loadSettings complete
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Privacy & App Security'), findsOneWidget);
      expect(find.text('Screenshot Protection'), findsOneWidget);
      expect(find.text('Biometric / PIN Lock'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('LoginScreen renders branding, inputs, and toggles between Sign In and Register', (tester) async {
      final mockAuth = MockAuthProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuth,
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Check header branding
      expect(find.text('DIRECT'), findsOneWidget);
      expect(find.text('Zero-Knowledge • End-to-End Encrypted'), findsOneWidget);

      // Check fields
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Default is Sign In
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text("Don't have an account? Create One"), findsOneWidget);

      // Tap toggle to switch to Register mode
      await tester.tap(find.text("Don't have an account? Create One"));
      await tester.pumpAndSettle();

      // Mode changed to Register
      expect(find.text('Generate Key & Register'), findsOneWidget);
      expect(find.text('Already have an account? Sign In'), findsOneWidget);

      // Empty submission triggers SnackBar
      await tester.tap(find.text('Generate Key & Register'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter username and password'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/security/security_service.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'ui/screens/app_lock_screen.dart';
import 'ui/screens/conversations_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DirectApp());
}

class DirectApp extends StatelessWidget {
  const DirectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (context) => ChatProvider(
            authProvider: context.read<AuthProvider>(),
          ),
          update: (context, auth, previous) =>
              previous ?? ChatProvider(authProvider: auth),
        ),
      ],
      child: MaterialApp(
        title: 'Direct',
        debugShowCheckedModeBanner: false,
        theme: DirectTheme.darkTheme,
        home: const AppRootRouter(),
      ),
    );
  }
}

class AppRootRouter extends StatefulWidget {
  const AppRootRouter({super.key});

  @override
  State<AppRootRouter> createState() => _AppRootRouterState();
}

class _AppRootRouterState extends State<AppRootRouter> with WidgetsBindingObserver {
  final SecurityService _security = SecurityService();
  bool _isUnlocked = false;
  bool _isLockChecking = true;
  bool _isAppLockEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAppLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAppLockEnabled) {
      // Re-lock when returning from background
      setState(() {
        _isUnlocked = false;
      });
    }
  }

  Future<void> _checkAppLock() async {
    final enabled = await _security.isAppLockEnabled();
    if (mounted) {
      setState(() {
        _isAppLockEnabled = enabled;
        _isUnlocked = !enabled; // Automatically unlocked if lock is not enabled
        _isLockChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading || _isLockChecking) {
      return const Scaffold(
        backgroundColor: DirectTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 56, color: DirectTheme.primary),
              SizedBox(height: 20),
              CircularProgressIndicator(color: DirectTheme.primary),
            ],
          ),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    // If app lock is active and locked, show lock screen
    if (_isAppLockEnabled && !_isUnlocked) {
      return AppLockScreen(
        onUnlocked: () {
          setState(() {
            _isUnlocked = true;
          });
        },
      );
    }

    return const ConversationsScreen();
  }
}

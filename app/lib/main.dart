import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
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

class AppRootRouter extends StatelessWidget {
  const AppRootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
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

    if (auth.isLoggedIn) {
      return const ConversationsScreen();
    }

    return const LoginScreen();
  }
}

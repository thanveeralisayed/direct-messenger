import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../theme.dart';
import '../../core/config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showServerSettings(BuildContext context, AuthProvider auth) {
    final controller = TextEditingController(text: auth.serverUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DirectTheme.surface,
        title: const Text('Relay Server Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the backend relay URL:\n• Android Emulator: http://10.0.2.2:8080\n• Local / Windows: http://localhost:8080\n• Physical Phone: http://<YOUR_PC_IP>:8080',
              style: TextStyle(color: DirectTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                prefixIcon: Icon(Icons.dns_outlined, color: DirectTheme.primary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              auth.updateServerUrl(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(AuthProvider auth) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter username and password')),
      );
      return;
    }

    bool success;
    if (_isRegister) {
      success = await auth.register(username: username, password: password);
    } else {
      success = await auth.login(username: username, password: password);
    }

    if (!success && mounted && auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DirectTheme.error,
          content: Text(auth.errorMessage!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (AppConfig.enableServerConfigUI)
            IconButton(
              tooltip: 'Server Settings',
              icon: const Icon(Icons.settings_outlined, color: DirectTheme.textSecondary),
              onPressed: () => _showServerSettings(context, auth),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo & Shield
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: DirectTheme.surfaceLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: DirectTheme.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: DirectTheme.primary.withValues(alpha: 0.2),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 38,
                      color: DirectTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'DIRECT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: DirectTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Zero-Knowledge • End-to-End Encrypted',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: DirectTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 36),

                // Username field
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: DirectTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline, color: DirectTheme.primary),
                  ),
                ),
                const SizedBox(height: 16),

                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: DirectTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: DirectTheme.primary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: DirectTheme.textMuted,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Button
                ElevatedButton(
                  onPressed: auth.isLoading ? null : () => _submit(auth),
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DirectTheme.background,
                          ),
                        )
                      : Text(_isRegister ? 'Generate Key & Register' : 'Sign In'),
                ),
                const SizedBox(height: 16),

                // Switch between Login and Register
                TextButton(
                  onPressed: auth.isLoading
                      ? null
                      : () {
                          setState(() {
                            _isRegister = !_isRegister;
                          });
                        },
                  child: Text(
                    _isRegister
                        ? 'Already have an account? Sign In'
                        : "Don't have an account? Create One",
                    style: const TextStyle(color: DirectTheme.primary),
                  ),
                ),
                const SizedBox(height: 20),

                // Privacy Note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DirectTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF243245)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_clock_outlined, size: 20, color: DirectTheme.accent),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No chat logs or messages are stored on any server. History is kept strictly on your local device.',
                          style: TextStyle(color: DirectTheme.textMuted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

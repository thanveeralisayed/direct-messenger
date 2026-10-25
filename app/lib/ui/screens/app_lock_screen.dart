import 'package:flutter/material.dart';
import '../../core/security/security_service.dart';
import '../theme.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final SecurityService _security = SecurityService();
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptAuth();
    });
  }

  Future<void> _promptAuth() async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);

    final success = await _security.authenticate(reason: 'Authenticate to unlock Direct Chat');
    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (success) {
        widget.onUnlocked();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DirectTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
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
                    Icons.fingerprint,
                    size: 44,
                    color: DirectTheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Direct is Locked',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: DirectTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Biometric or device passcode authentication is required to access your encrypted conversations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DirectTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 36),
                ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open, size: 20),
                  label: const Text('Unlock with Biometrics'),
                  onPressed: _isAuthenticating ? null : _promptAuth,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

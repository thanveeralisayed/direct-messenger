import 'package:flutter/material.dart';
import '../../core/security/security_service.dart';
import '../theme.dart';

class SecuritySettingsDialog extends StatefulWidget {
  const SecuritySettingsDialog({super.key});

  @override
  State<SecuritySettingsDialog> createState() => _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends State<SecuritySettingsDialog> {
  final SecurityService _security = SecurityService();
  bool _screenshotBlocked = true;
  bool _appLockEnabled = false;
  bool _canBiometric = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final screenshot = await _security.isScreenshotProtectionEnabled();
    final appLock = await _security.isAppLockEnabled();
    final canBio = await _security.canAuthenticate();

    if (mounted) {
      setState(() {
        _screenshotBlocked = screenshot;
        _appLockEnabled = appLock;
        _canBiometric = canBio;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DirectTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF243245)),
      ),
      title: const Row(
        children: [
          Icon(Icons.security, color: DirectTheme.primary),
          SizedBox(width: 10),
          Text('Privacy & App Security', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(color: DirectTheme.primary)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: DirectTheme.primary,
                  title: const Text('Screenshot Protection', style: TextStyle(fontSize: 15)),
                  subtitle: const Text(
                    'Prevents Android screenshots, screen recording, and task switcher preview leaks.',
                    style: TextStyle(color: DirectTheme.textSecondary, fontSize: 12),
                  ),
                  value: _screenshotBlocked,
                  onChanged: (val) async {
                    setState(() => _screenshotBlocked = val);
                    await _security.setScreenshotProtection(val);
                  },
                ),
                const Divider(color: Color(0xFF243245), height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: DirectTheme.primary,
                  title: const Text('Biometric / PIN Lock', style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                    _canBiometric
                        ? 'Require fingerprint, face unlock, or device PIN to access Direct.'
                        : 'Biometrics not available on this device.',
                    style: const TextStyle(color: DirectTheme.textSecondary, fontSize: 12),
                  ),
                  value: _appLockEnabled,
                  onChanged: !_canBiometric
                      ? null
                      : (val) async {
                          if (val) {
                            // Test authentication before turning on
                            final success = await _security.authenticate(reason: 'Confirm biometrics to enable App Lock');
                            if (!success) return;
                          }
                          setState(() => _appLockEnabled = val);
                          await _security.setAppLockEnabled(val);
                        },
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done', style: TextStyle(color: DirectTheme.primary)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme.dart';

class SafetyNumberDialog extends StatelessWidget {
  final String username;
  final String publicKey;
  final String safetyNumber;

  const SafetyNumberDialog({
    super.key,
    required this.username,
    required this.publicKey,
    required this.safetyNumber,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DirectTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF243245)),
      ),
      title: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: DirectTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verify @$username',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Compare this safety number or scan the QR code to ensure your end-to-end encryption is not intercepted.',
              style: TextStyle(color: DirectTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // QR Code
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: 'direct:key:$username:$publicKey',
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            // Formatted Safety Number
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: DirectTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF243245)),
              ),
              child: Text(
                safetyNumber,
                style: const TextStyle(
                  color: DirectTheme.primary,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: DirectTheme.textSecondary)),
        ),
      ],
    );
  }
}

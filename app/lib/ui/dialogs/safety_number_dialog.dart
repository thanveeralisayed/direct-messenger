import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/chat_provider.dart';
import '../screens/qr_scan_screen.dart';
import '../theme.dart';

class SafetyNumberDialog extends StatefulWidget {
  final String username;
  final String publicKey;
  final String safetyNumber;
  final bool isVerified;
  final bool isPeer;

  const SafetyNumberDialog({
    super.key,
    required this.username,
    required this.publicKey,
    required this.safetyNumber,
    this.isVerified = false,
    this.isPeer = false,
  });

  @override
  State<SafetyNumberDialog> createState() => _SafetyNumberDialogState();
}

class _SafetyNumberDialogState extends State<SafetyNumberDialog> {
  late bool _verified;

  @override
  void initState() {
    super.initState();
    _verified = widget.isVerified;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DirectTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _verified ? DirectTheme.success.withValues(alpha: 0.6) : const Color(0xFF243245),
        ),
      ),
      title: Row(
        children: [
          Icon(
            _verified ? Icons.verified : Icons.verified_user_outlined,
            color: _verified ? DirectTheme.success : DirectTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isPeer ? 'Verify @${widget.username}' : 'My Safety Code',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_verified) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: DirectTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: DirectTheme.success),
                      SizedBox(width: 6),
                      Text(
                        'Verified Identity',
                        style: TextStyle(
                          color: DirectTheme.success,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                widget.isPeer
                    ? 'Compare this number with @${widget.username}\'s device, or scan their QR code to verify their identity.'
                    : 'Show this QR code or safety number to contacts to prove your key authenticity.',
                style: const TextStyle(color: DirectTheme.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              // QR Code
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: 'direct:key:${widget.username}:${widget.publicKey}',
                  version: QrVersions.auto,
                  size: 170,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              // Formatted Safety Number
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: DirectTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF243245)),
                ),
                child: Text(
                  widget.safetyNumber,
                  style: const TextStyle(
                    color: DirectTheme.primary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (widget.isPeer) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text('Scan @${widget.username}\'s Code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DirectTheme.primary,
                    side: const BorderSide(color: DirectTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QrScanScreen(targetUsername: widget.username),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.isPeer)
          TextButton(
            onPressed: () {
              final newStatus = !_verified;
              setState(() => _verified = newStatus);
              context.read<ChatProvider>().setContactVerified(widget.username, newStatus);
            },
            child: Text(
              _verified ? 'Mark Unverified' : 'Mark Verified',
              style: TextStyle(color: _verified ? DirectTheme.error : DirectTheme.success),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: DirectTheme.textSecondary)),
        ),
      ],
    );
  }
}

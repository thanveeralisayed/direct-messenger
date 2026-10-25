import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../theme.dart';

class QrScanScreen extends StatefulWidget {
  final String targetUsername;

  const QrScanScreen({super.key, required this.targetUsername});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _hasScanned = true);
    final rawValue = barcode.rawValue!;

    final chat = context.read<ChatProvider>();
    final result = chat.verifyScannedQr(rawValue, widget.targetUsername);

    if (result.isValid) {
      chat.setContactVerified(widget.targetUsername, true);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: DirectTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.verified, color: DirectTheme.success, size: 28),
              SizedBox(width: 8),
              Text('Identity Verified!'),
            ],
          ),
          content: Text(
            'The cryptographic safety key for @${widget.targetUsername} has been matched and verified.',
            style: const TextStyle(color: DirectTheme.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else if (result.isMismatch) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: DirectTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: DirectTheme.error, width: 2),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: DirectTheme.error, size: 30),
              SizedBox(width: 8),
              Text('KEY MISMATCH!', style: TextStyle(color: DirectTheme.error)),
            ],
          ),
          content: Text(
            result.errorMessage ?? 'Key mismatch detected!',
            style: const TextStyle(color: DirectTheme.textPrimary),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: DirectTheme.error),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, false);
              },
              child: const Text('Back to Safety'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DirectTheme.error,
          content: Text(result.errorMessage ?? 'Invalid QR Code'),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _hasScanned = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan @${widget.targetUsername} QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Viewfinder overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: DirectTheme.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: DirectTheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Point camera at the Safety QR code on @${widget.targetUsername}\'s screen',
                textAlign: TextAlign.center,
                style: const TextStyle(color: DirectTheme.textPrimary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

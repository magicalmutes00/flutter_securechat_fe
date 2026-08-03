import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/e2ee/e2ee_service.dart';
import '../../data/services/websocket_service.dart';

/// Bottom sheet showing the end-to-end security code (safety number) for a
/// conversation so two users can verify each other's identity out-of-band.
class SecurityCodeSheet extends StatefulWidget {
  const SecurityCodeSheet({super.key, required this.peerUserId});

  final String peerUserId;

  @override
  State<SecurityCodeSheet> createState() => _SecurityCodeSheetState();
}

class _SecurityCodeSheetState extends State<SecurityCodeSheet> {
  String? _number;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = WebSocketService().currentUserId;
    if (me == null) return;
    final number = await E2eeService.instance.computeSecurityNumber(
        currentUserId: me, peerUserId: widget.peerUserId);
    if (mounted) setState(() => _number = number);
  }

  void _copy() {
    if (_number == null) return;
    Clipboard.setData(ClipboardData(text: _number!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Security code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user,
                size: 48, color: AppTheme.primaryColor),
            const SizedBox(height: 12),
            const Text(
              'Security code',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Compare this number with the one shown on your contact\'s screen. '
              'A match confirms the conversation is end-to-end encrypted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _number == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                : _numberedText(_number!),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _number == null ? null : _copy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy code'),
            ),
            const SizedBox(height: 8),
            if (_number == null)
              const Text(
                'No key bundle available for this contact yet.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  /// Groups the 60-digit number into 12 blocks of 5 digits for readability.
  Widget _numberedText(String digits) {
    final groups = <String>[];
    for (var i = 0; i < digits.length; i += 5) {
      groups.add(digits.substring(i, i + 5));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var col = 0; col < 4; col++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      groups[row * 4 + col],
                      style: const TextStyle(
                        fontSize: 16,
                        letterSpacing: 2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

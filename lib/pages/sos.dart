import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database/db_helper.dart';

class SosPage extends StatefulWidget {
  const SosPage({super.key});

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  late final DBHelper _dbHelper = DBHelper();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                'Emergency',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              _BigCircleButton(
                label: 'SOS\nCall',
                color: colorScheme.error,
                onColor: colorScheme.onError,
                icon: Icons.phone_in_talk,
                onPressed: _isProcessing ? null : () => _handleAction(_callEmergencyContact),
              ),
              _BigCircleButton(
                label: 'SMS\nAlert',
                color: colorScheme.primary,
                onColor: colorScheme.onPrimary,
                icon: Icons.message,
                onPressed: _isProcessing ? null : () => _handleAction(_sendTextsToContacts),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(Future<void> Function() action) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final contacts = await _dbHelper.getContacts();
      if (!mounted) return;
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Add emergency contacts first."),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
        return;
      }
      final confirmed = await _showConfirmation();
      if (!mounted) return;
      if (confirmed == true) await action();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool?> _showConfirmation() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm'),
          content: const Text('Send an emergency alert now?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, send'),
            ),
          ],
        ),
      );

  Future<void> _callEmergencyContact() async {
    final contacts = await _dbHelper.getContacts();
    await FlutterPhoneDirectCaller.callNumber(contacts.first.contactNo);
  }

  Future<void> _sendTextsToContacts() async {
    final contacts = await _dbHelper.getContacts();
    final snap = await FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get();
    final data = snap.data();
    final lat = data?['latitude'] ?? '?';
    final lng = data?['longitude'] ?? '?';
    final message =
        'I need help, please find me: https://maps.google.com/?q=$lat,$lng';
    final recipients = contacts.map((c) => c.contactNo).toList();
    await sendSMS(message: message, recipients: recipients);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('SMS compose opened — tap Send to alert your contacts'),
    ));
  }
}

class _BigCircleButton extends StatelessWidget {
  const _BigCircleButton({
    required this.label,
    required this.color,
    required this.onColor,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final Color onColor;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        fixedSize: const Size(160, 160),
        shape: const CircleBorder(),
        backgroundColor: color,
        foregroundColor: onColor,
        elevation: 6,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

Future<void> _requestPermission() async {
  for (int attempt = 0; attempt < 2; attempt++) {
    final status = await Permission.location.request();
    if (status.isGranted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
  }
}

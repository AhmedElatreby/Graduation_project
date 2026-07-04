// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Guardians (contacts tab)
//  Replaces:  lib/contact/personal_emergency_contacts.dart
//  Returns CONTENT only. Keeps DBHelper add/update/delete + the editor sheet.
//  ★ Restores the separate SMS button alongside Call (Message + Call + ⋯).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:url_launcher/url_launcher.dart';

import './personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';
import '../theme/lumi_theme.dart';
import '../widgets/lumi_widgets.dart';

class PersonalEmergencyContacts extends StatefulWidget {
  const PersonalEmergencyContacts({super.key});
  @override
  State<PersonalEmergencyContacts> createState() =>
      _PersonalEmergencyContactsState();
}

class _PersonalEmergencyContactsState extends State<PersonalEmergencyContacts> {
  final DBHelper _dbHelper = DBHelper();
  late Future<List<PersonalEmergency>> _contactsFuture;

  // a small palette to vary the avatar tiles
  static const _avatarColors = [
    [Color(0xFFFF6B81), Color(0xFFD81B33)],
    [Color(0xFF5B8DEF), Color(0xFF2E5BD8)],
    [Color(0xFF3FD9A4), Color(0xFF159E72)],
    [Color(0xFFFFB02E), Color(0xFFE08600)],
  ];

  @override
  void initState() {
    super.initState();
    _contactsFuture = _dbHelper.getContacts();
  }

  void _refresh() {
    setState(() {
      _contactsFuture = _dbHelper.getContacts();
    });
  }

  Future<void> _sms(String number) async {
    final uri = Uri(scheme: 'sms', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Messages')),
      );
    }
  }

  Future<void> _showSheet({PersonalEmergency? existing}) async {
    final result = await showModalBottomSheet<PersonalEmergency>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LumiColors.bgTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _ContactSheet(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await _dbHelper.add(result);
    } else {
      await _dbHelper.update(result);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Guardians', style: LumiText.display(24)),
                const Spacer(),
                FutureBuilder<List<PersonalEmergency>>(
                  future: _contactsFuture,
                  builder: (_, s) => Text('${s.data?.length ?? 0} people',
                      style: LumiText.body(13,
                          weight: FontWeight.w600, color: LumiColors.textSub)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Alerted instantly when you trigger SOS.',
                style: LumiText.body(13, color: LumiColors.textSub)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<PersonalEmergency>>(
              future: _contactsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: LumiColors.accent));
                }
                final contacts = snapshot.data ?? [];
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: contacts.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 11),
                  itemBuilder: (context, i) {
                    if (i == contacts.length) {
                      return _AddTile(onTap: () => _showSheet());
                    }
                    final c = contacts[i];
                    final colors = _avatarColors[i % _avatarColors.length];
                    return _ContactTile(
                      contact: c,
                      colors: colors,
                      onSms: () => _sms(c.contactNo),
                      onCall: () =>
                          FlutterPhoneDirectCaller.callNumber(c.contactNo),
                      onEdit: () => _showSheet(existing: c),
                      onDelete: () => _confirmDelete(c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(PersonalEmergency c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiColors.surface,
        title: Text('Remove guardian', style: LumiText.display(18)),
        content: Text('Remove ${c.name}?',
            style: LumiText.body(14, color: LumiColors.textSub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: LumiText.body(14, color: LumiColors.textSub))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: LumiText.body(14,
                      weight: FontWeight.w700, color: LumiColors.accent))),
        ],
      ),
    );
    if (ok == true) {
      await _dbHelper.delete(c.id);
      _refresh();
    }
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.colors,
    required this.onSms,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
  });
  final PersonalEmergency contact;
  final List<Color> colors;
  final VoidCallback onSms, onCall, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final initial =
        contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?';
    return LumiCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child:
                Text(initial, style: LumiText.display(17, color: Colors.white)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name,
                    style: LumiText.body(15, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(contact.contactNo,
                    style: LumiText.body(12.5, color: LumiColors.textSub)),
              ],
            ),
          ),
          _RoundIcon(
              icon: Icons.sms_outlined,
              color: const Color(0xFF5B8DEF),
              onTap: onSms),
          const SizedBox(width: 8),
          _RoundIcon(
              icon: Icons.call_outlined,
              color: LumiColors.green,
              onTap: onCall),
          const SizedBox(width: 8),
          _RoundIcon(
              icon: Icons.more_horiz,
              color: LumiColors.textSub,
              onTap: () => _menu(context)),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LumiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: LumiColors.text),
              title: Text('Edit', style: LumiText.body(15)),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: LumiColors.accent),
              title: Text('Delete',
                  style: LumiText.body(15, color: LumiColors.accent)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withOpacity(0.16),
              width: 1.5,
              style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: LumiColors.accent, size: 20),
            const SizedBox(width: 9),
            Text('Add guardian',
                style: LumiText.body(14.5,
                    weight: FontWeight.w700, color: const Color(0xFFB9C2D6))),
          ],
        ),
      ),
    );
  }
}

// Editor sheet — owns its controllers so they outlive the pop animation.
class _ContactSheet extends StatefulWidget {
  const _ContactSheet({this.existing});
  final PersonalEmergency? existing;
  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.contactNo ?? '');
  final _formKey = GlobalKey<FormState>();
  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(_editing ? 'Edit guardian' : 'Add guardian',
                style: LumiText.display(20)),
            const SizedBox(height: 18),
            LumiField(
              hint: 'Name',
              icon: Icons.person_outline,
              controller: _name,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            LumiField(
              hint: 'Phone number',
              icon: Icons.phone_outlined,
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a number';
                if (v.trim().length < 7) return 'Number too short';
                return null;
              },
            ),
            const SizedBox(height: 22),
            LumiPrimaryButton(
              label: _editing ? 'Save' : 'Add guardian',
              onPressed: () {
                if (_formKey.currentState?.validate() != true) return;
                final c =
                    PersonalEmergency(_name.text.trim(), _phone.text.trim());
                if (_editing) c.id = widget.existing!.id;
                Navigator.pop(context, c);
              },
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

import './personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';

class PersonalEmergencyContacts extends StatefulWidget {
  const PersonalEmergencyContacts({super.key});

  @override
  State<PersonalEmergencyContacts> createState() =>
      _PersonalEmergencyContactsState();
}

class _PersonalEmergencyContactsState
    extends State<PersonalEmergencyContacts> {
  late final DBHelper _dbHelper = DBHelper();
  late Future<List<PersonalEmergency>> _contactsFuture;

  @override
  void initState() {
    super.initState();
    _contactsFuture = _dbHelper.getContacts();
  }

  void _refresh() => setState(() { _contactsFuture = _dbHelper.getContacts(); });

  Future<void> _deleteContact(int id) async {
    await _dbHelper.delete(id);
    _refresh();
  }

  Future<void> _showAddSheet() async {
    final contact = await showModalBottomSheet<PersonalEmergency>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ContactSheet(),
    );
    if (contact != null) {
      await _dbHelper.add(contact);
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact added')),
      );
    }
  }

  Future<void> _showEditSheet(PersonalEmergency existing) async {
    final updated = await showModalBottomSheet<PersonalEmergency>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContactSheet(existing: existing),
    );
    if (updated != null) {
      await _dbHelper.update(updated);
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<PersonalEmergency>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load contacts',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            );
          }
          final contacts = snapshot.data ?? [];
          if (contacts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.contact_phone_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No emergency contacts yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Tap + to add one',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final contact = contacts[i];
              final initials = contact.name.isNotEmpty
                  ? contact.name[0].toUpperCase()
                  : '?';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: Text(initials),
                  ),
                  title: Text(contact.name),
                  subtitle: Text(contact.contactNo),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.phone_outlined),
                        onPressed: () => FlutterPhoneDirectCaller.callNumber(
                            contact.contactNo),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showEditSheet(contact),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: () => _confirmDelete(contact),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add contact'),
      ),
    );
  }

  Future<void> _confirmDelete(PersonalEmergency contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact'),
        content: Text('Remove ${contact.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _deleteContact(contact.id);
  }
}

// Owns its own controllers so Flutter disposes them after the exit animation,
// not immediately when the sheet is popped (which would crash mid-animation).
class _ContactSheet extends StatefulWidget {
  const _ContactSheet({this.existing});
  final PersonalEmergency? existing;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.existing?.contactNo ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEditing ? 'Edit contact' : 'Add contact',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a number';
                if (v.trim().length < 7) return 'Number too short';
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (_formKey.currentState?.validate() != true) return;
                final contact = PersonalEmergency(
                    _nameCtrl.text.trim(), _phoneCtrl.text.trim());
                if (_isEditing) contact.id = widget.existing!.id;
                Navigator.pop(context, contact);
              },
              child: Text(_isEditing ? 'Save' : 'Add'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

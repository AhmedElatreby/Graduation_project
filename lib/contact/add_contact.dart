import 'dart:math';
import 'package:flutter/material.dart';
import 'list.dart';
import 'db_helper.dart';
import 'personal_contacts.dart';

class AddContact extends StatefulWidget {
  @override
  _AddContactState createState() => _AddContactState();
}

class _AddContactState extends State<AddContact> {
  final _formKey = GlobalKey<FormState>();
  String name = "";
  String contactNo = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Scrollbar(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              TextFormField(
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter name';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'Name',
                ),
                onChanged: (value) {
                  setState(() {
                    name = value;
                  });
                },
              ),
              TextFormField(
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter phone number';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'Phone number',
                ),
                onChanged: (value) {
                  setState(() {
                    contactNo = value;
                  });
                },
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    await DBHelper()
                        .add(AddContact())
                        .whenComplete(() => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ListScreen()),
                    ));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Processing Data')),
                    );
                  }
                },
                child: const Text(
                  'Add Contact',
                  style: TextStyle(
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
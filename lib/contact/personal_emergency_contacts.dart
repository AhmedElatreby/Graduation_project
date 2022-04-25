import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import './personal_emergency_contacts_model.dart';
import './contact_list.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

class PersonalEmergencyContacts extends StatefulWidget {
  final Function deleteFunction;
  const PersonalEmergencyContacts({required this.deleteFunction, Key? key})
      : super(key: key);

  @override
  _PersonalEmergencyContactsState createState() =>
      _PersonalEmergencyContactsState();
}

class _PersonalEmergencyContactsState extends State<PersonalEmergencyContacts> {
  final GlobalKey<FormState> _formStateKey = GlobalKey<FormState>();
  static Future<List<PersonalEmergency>>? contacts;

  late DBHelper dbHelper;

  final ContactList cl = ContactList();

  final TextEditingController _textFieldController1 = TextEditingController();
  final TextEditingController _textFieldController2 = TextEditingController();

  void getInitial(String name) {
    var nameParts = name.split(" ");
    if (nameParts.length > 1) {
      cl.emergencyContactsInitials
          .add(nameParts[0][0].toUpperCase() + nameParts[1][0].toUpperCase());
    } else {
      cl.emergencyContactsInitials.add(nameParts[0][0].toUpperCase());
    }
  }

  void _addContact(String name, String no) {
    dbHelper.add(PersonalEmergency(name, no));
    _textFieldController1.clear();
    _textFieldController2.clear();
  }

  void deleteFunction(int id) async {
    await dbHelper.delete(id);
    refreshContacts();
  }

  @override
  void initState() {
    super.initState();
    dbHelper = DBHelper();
    resetContactListValues();
    refreshContacts();
  }

  void resetContactListValues() {
    cl.emergencyContactsName = [];
    cl.emergencyContactsInitials = [];
    cl.emergencyContactsNo = [];
    cl.emergencyContactsId = [];
  }

  void getData(List<PersonalEmergency> contacts) {
    contacts.forEach((contact) {
      print(contact.contactNo);
      getInitial(contact.name.toString());
      cl.emergencyContactsName.add(contact.name.toString());
      cl.emergencyContactsNo.add(contact.contactNo.toString());
      cl.emergencyContactsId.add(contact.id);
    });
  }

  refreshContacts() {
    setState(() {
      resetContactListValues();
      contacts = dbHelper.getContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
          future: contacts,
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return (const Center(child: CircularProgressIndicator()));
            } else {
              getData(snapshot.data);
              return Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  title: const Text('Emergency Contacts'),
                ),
                body: Scrollbar(
                    child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: cl.emergencyContactsName.length,
                        itemBuilder: (BuildContext context, index) {
                          return SizedBox(
                            height: 100,
                            child: Card(
                              elevation: 4,
                              child: InkWell(
                                onTap: () async {
                                  var phoneNo = cl.emergencyContactsNo[index];
                                  await FlutterPhoneDirectCaller.callNumber(
                                      phoneNo);
                                },
                                child: ListTile(
                                  title: Text(cl.emergencyContactsName[index]),
                                  subtitle: Text(cl.emergencyContactsNo[index]),
                                  dense: true,
                                  trailing: GestureDetector(
                                    child: const Icon(
                                      Icons.delete,
                                      color: Colors.grey,
                                    ),
                                    onTap: () async {
                                      deleteFunction(cl.emergencyContactsId[index]);
                                    },
                                  ),
                                  leading: CircleAvatar(
                                    child: Text(
                                      cl.emergencyContactsInitials[index],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        })),
              );
            }
          }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<String>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Add Contact Details'),
            content: SizedBox(
                width: 300,
                height: 200,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _textFieldController1,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Enter Contact Name",
                      ),
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    TextFormField(
                      controller: _textFieldController2,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Enter Phone No.",
                      ),
                    ),
                  ],
                )),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, 'Cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => {
                  _addContact(
                      _textFieldController1.text, _textFieldController2.text),
                  Navigator.pop(context, 'Add'),
                  refreshContacts()
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        tooltip: 'Add Contacts',
        child: const Icon(Icons.add),
      ),
    );
  }
}

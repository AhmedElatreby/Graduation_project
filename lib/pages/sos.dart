import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

import '../contact/contact_list.dart';
import '../contact/personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';
import '../oauth/auth_controller.dart';

class SosPage extends StatefulWidget {
  const SosPage({Key? key}) : super(key: key);

  @override
  _SosPageState createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final textController = TextEditingController();
  late DBHelper dbHelper;
  late List<String> recipients = [];
  List<String> number = [];

  final ContactList cl = ContactList();

  void getData(List<PersonalEmergency> contacts) {
    contacts.forEach((contact) {
      print(contact.contactNo);
      getInitial(contact.name.toString());
      cl.emergencyContactsName.add(contact.name.toString());
      cl.emergencyContactsNo.add(contact.contactNo.toString());
      cl.emergencyContactsId.add(contact.id);
    });
  }

  void getInitial(String name) {
    var nameParts = name.split(" ");
    if (nameParts.length > 1) {
      cl.emergencyContactsInitials
          .add(nameParts[0][0].toUpperCase() + nameParts[0][0].toUpperCase());
    } else {
      cl.emergencyContactsInitials.add(nameParts[0][0].toUpperCase());
    }
  }

  @override
  void initState() {
    super.initState();
    dbHelper = DBHelper();
    _requestPermission();
    // _getUserLongitude();
    // _getUserLatitude();
    number = recipients;
  }

  void setRecipientList() async {
    List<PersonalEmergency> contacts;
    contacts = await dbHelper.getContacts();
    contacts.forEach((contact) {
      recipients.add(contact.contactNo);
    });
  }

  @override
  Widget build(BuildContext context) {
    CollectionReference location =
        FirebaseFirestore.instance.collection('location');
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('SOS'),
        backgroundColor: Colors.cyan,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: () {
                AuthController.instance.logOut();
              },
              child: Container(
                width: width * 0.2,
                height: height * 0.05,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.cyan),
                child: const Center(
                  child: Text(
                    "Sign out",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                AuthController.instance.logOut();
              },
              child: Column(
                children: [
                  const SizedBox(
                    height: 40,
                  ),
                  Center(
                    child: ElevatedButton(
                        onPressed: () async {
                          _handleAllMethodsIfNoContacts(_callEmergencyContact);
                        },
                        style: ElevatedButton.styleFrom(
                            fixedSize: const Size(150, 150),
                            shape: const CircleBorder(),
                            primary: Colors.red),
                        child: const Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 100,
            ),
            Center(
              child: GestureDetector(
                child: Column(
                  children: [
                    ElevatedButton(
                        onPressed: () async {
                          _handleAllMethodsIfNoContacts(_sendTextsToContacts);
                        },
                        style: ElevatedButton.styleFrom(
                            fixedSize: const Size(150, 150),
                            shape: const CircleBorder(),
                            primary: Colors.cyan),
                        child: const Text(
                          'SMS',
                          style: TextStyle(
                            fontSize: 50,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                AuthController.instance.logOut();
              },
              child: Center(
                child: Column(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void recipientList() async {
    List<PersonalEmergency> contacts;
    contacts = await dbHelper.getContacts();
    contacts.forEach((contact) {
      recipients.add(contact.contactNo);
    });
  }

  void sendMessageToContacts(List<String> recipients, String message) {
    recipients.forEach((number) {
      _sendSingleText(number, message);
    });
  }

  void _handleAllMethodsIfNoContacts(Function method) async {
    recipientList();
    List<PersonalEmergency> contacts = await dbHelper.getContacts();
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "You don't have any contacts in your contact list...",
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } else {
      return method();
    }
  }

  void _sendTextsToContacts() async {
    recipientList();
    var lat = await FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get();
    var location = lat.data()?.values;
    var longitude = location?.toList().last;
    var latitude = location?.toList().first;
    var userLoaction = "$latitude,$longitude";
    print("test user location $userLoaction");

    String message =
        "I need help, please find me with the following link: https://maps.google.com/?q=${userLoaction}";
    sendMessageToContacts(recipients, message);
    print(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A message sent to your emergency contact',
        ),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  void _callEmergencyContact() async {
    List<PersonalEmergency> contacts = await dbHelper.getContacts();
    FlutterPhoneDirectCaller.callNumber(contacts.toList()[0].contactNo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'You are calling your emergency contact',
        ),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }
}

_requestPermission() async {
  var status = await Permission.location.request();
  if (status.isGranted) {
    print('done');
  } else if (status.isDenied) {
    _requestPermission();
  } else if (status.isPermanentlyDenied) {
    openAppSettings();
  }
}

void _sendSingleText(String number, String message) async {
  final Telephony telephony = Telephony.instance;
  bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

  telephony.sendSms(to: number, message: message);
}

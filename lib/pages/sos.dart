import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

import '../contact/personal_emergency_contacts_model.dart';
import '../database/db_helper.dart';
import '../oauth/auth_controller.dart';

class SosPage extends StatefulWidget {
  const SosPage({Key? key}) : super(key: key);

  @override
  _SosPageState createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  TextEditingController textEditingController = TextEditingController();
  late DBHelper dbHelper;
  late List<String> recipients = [];
  List<String> number = [];

  @override
  void initState() {
    super.initState();
    dbHelper = DBHelper();
    _requestPermission();
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
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('SOS'),
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
                  image: const DecorationImage(
                      image: AssetImage("assets/images/loginbtn.png"),
                      fit: BoxFit.cover),
                ),
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
                          controller: textEditingController;

                          _callNumber(textEditingController.text);
                          _launchPhoneURL(textEditingController.text);
                          // FlutterPhoneDirectCaller.callNumber('+447562596358');
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
            GestureDetector(
              onTap: () {
                AuthController.instance.logOut();
              },
              child: Center(
                child: Column(
                  children: [
                    ElevatedButton(
                        onPressed: () async {
                          recipientList();
                          String message =
                              "I need help, please find me with the following link: https://maps.google.com/?q=.";
                          sendMessageToContacts(recipients, message);
                        },
                        style: ElevatedButton.styleFrom(
                            fixedSize: const Size(150, 150),
                            shape: const CircleBorder()),
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


_callNumber(String recipients ) async {
  String number = recipients;
  await FlutterPhoneDirectCaller.callNumber(number);
}

_launchPhoneURL(String recipients) async {
  String url = 'tel:' + recipients;
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}
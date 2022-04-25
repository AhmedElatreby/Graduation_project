import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:safetyproject/contact/emergency_contacts.dart';
import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/db_helper.dart';
import 'package:telephony/telephony.dart';
import '../oauth/auth_controller.dart';

class SosPage extends StatefulWidget {
  const SosPage({Key? key})
      : super(key: key);

  @override
  _SosPageState createState() =>
      _SosPageState();
}

class _SosPageState extends State<SosPage> {
  _MapActivityState createState() => _MapActivityState();

  late DBHelper dbHelper;

  late List<String> recipients = [];

  @override
  void initState() {
    super.initState();
      dbHelper = DBHelper();
    }

  void setRecipientList() async {
    List<PersonalEmergency> contacts;
    contacts = await dbHelper.getContacts();
    contacts.forEach((contact) {
      recipients.add(contact.contactNo);
    });
  }

  void sendMessageToContacts() {
    setRecipientList();
    recipients.forEach((number) {
      _sendSingleText(number);
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
                      image: AssetImage("assests/images/loginbtn.png"),
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
                          FlutterPhoneDirectCaller.callNumber('+447562596358');
                        },
                        style: ElevatedButton.styleFrom(
                          fixedSize: const Size(150, 150),
                          shape: const CircleBorder(),primary: Colors.red
                        ),
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
                          sendMessageToContacts();
                        },
                        style: ElevatedButton.styleFrom(
                          fixedSize: const Size(150, 150),
                          shape: const CircleBorder()
                        ),
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
}

class _MapActivityState {}

void _sendSingleText(String number) async {
  final Telephony telephony = Telephony.instance;

  telephony.sendSms(
      to: number,
      message: "May the force be with you!",
  );
}
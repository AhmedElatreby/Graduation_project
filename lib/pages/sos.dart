import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:stream_chat_flutter/stream_chat_flutter.dart';

import '../oauth/auth_controller.dart';

class SosPage extends StatelessWidget {
  SosPage({Key? key}) : super(key: key);

  _MapActivityState createState() => _MapActivityState();
  List<String> recipents = ["+447562596358", "+447562596358"];

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('SOS'),
      ),
      body: Padding(
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
                    height: 150,
                  ),
                  Center(
                    child: ElevatedButton(
                        onPressed: () async {
                          FlutterPhoneDirectCaller.callNumber('+447562596358');
                        },
                        child: const Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 90,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 50,
            ),
            GestureDetector(
              onTap: () {
                AuthController.instance.logOut();
              },
              child: Column(
                children: [
                  TextButton(
                      onPressed: () async {
                        String message = "This is a test message!";
                        _sendSMS(message, recipents);
                      },
                      child: const Text(
                        'SMS',
                        style: TextStyle(
                          fontSize: 50,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      )),
                  const Center(
                    child: Text(
                      "SOS",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapActivityState {}

void _sendSMS(String message, List<String> recipents) async {
  String _result = await sendSMS(message: message, recipients: recipents)
      .catchError((onError) {
    print(onError);
  });
  print(_result);
}


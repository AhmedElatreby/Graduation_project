
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oauth/auth_controller.dart';

class SosPage extends StatelessWidget {
  SosPage({Key? key}) : super(key: key);

  _MapActivityState createState() => _MapActivityState();
  List<String> recipents = ["+447562596358", "+447562596358"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          GestureDetector(
            onTap: () {
              AuthController.instance.logOut();
            },
            child: Column(
              children: [
                TextButton(
                    onPressed: () async {
                      if (!await launch('tel:+447562596358')) {
                        throw 'Could not launch';
                      }
                    },
                    child: const Text(
                      'Call',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
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
    );
  }
}

class _MapActivityState {
}


void _sendSMS(String message, List<String> recipents) async {
  String _result = await sendSMS(message: message, recipients: recipents)
      .catchError((onError) {
    print(onError);
  });
  print(_result);
}
// class MapActivity extends StatefulWidget {
//   @override
//   _MapActivityState createState() => _MapActivityState();
// }

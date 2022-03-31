import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:safetyproject/oauth/auth_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sms/flutter_sms.dart';

import 'location_page.dart';

class WelcomePage extends StatelessWidget {
  _MapActivityState createState() => _MapActivityState();
  List<String> recipents = ["+447562596358", "+447562596358"];
  String email;
  WelcomePage({Key? key, required this.email}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: width,
            height: height * 0.3,
            decoration: const BoxDecoration(
              image: DecorationImage(
                  image: AssetImage("assests/images/signup.png"),
                  fit: BoxFit.cover),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: height * 0.18,
                ),
                const CircleAvatar(
                  backgroundColor: Colors.white38,
                  radius: 40,
                  backgroundImage:
                      AssetImage("assests/images/profile1.png"),
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 70,
          ),
          GestureDetector(
            onTap: () {
              AuthController.instance.logOut();
            },
            child: Container(
              width: width,
              margin: const EdgeInsets.only(left: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Welcome",
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54),
                  ),
                  Text(
                    email,
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
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
          const SizedBox(
            height: 10,
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
          const SizedBox(
            height: 50,
          ),
          GestureDetector(
            onTap: () {
              AuthController.instance.logOut();
            },
            child: Container(
              width: width * 0.4,
              height: height * 0.07,
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
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


void _sendSMS(String message, List<String> recipents) async {
  String _result = await sendSMS(message: message, recipients: recipents)
      .catchError((onError) {
    print(onError);
  });
  print(_result);
}
class MapActivity extends StatefulWidget {
  @override
  _MapActivityState createState() => _MapActivityState();
}

class _MapActivityState extends State<MapActivity> {
  late LatLng _center ;
  late Position currentLocation;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getUserLocation();
  }

  Future<Position> locateUser() async {
    return Geolocator
        .getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  getUserLocation() async {
    currentLocation = await locateUser();
    setState(() {
      _center = LatLng(currentLocation.latitude, currentLocation.longitude);
    });
    print('center $_center');
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}

class LatLng {
  LatLng(double latitude, double longitude);
}
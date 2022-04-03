import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safetyproject/oauth/auth_controller.dart';
import 'package:safetyproject/pages/sos.dart';
import 'package:url_launcher/url_launcher.dart';

import 'location_page.dart';

class WelcomePage extends StatefulWidget {
  String email;
  WelcomePage({Key? key, required this.email}) : super(key: key);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  _MapActivityState createState() => _MapActivityState();

  final screens = [
    LocationPage(),
    SosPage(),
    LocationPage(),
    LocationPage(),
  ];

  int currentIndex = 0;
  void onTap(int index){
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: screens[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black54,
        unselectedItemColor: Colors.grey.withOpacity(0.5),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
        iconSize: 30,
        currentIndex: currentIndex,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
            // backgroundColor: Colors.blue,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.call),
            label: 'SOS',
            // backgroundColor: Colors.grey,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mail),
            label: 'Mail',
            // backgroundColor: Colors.deepPurpleAccent,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
            // backgroundColor: Colors.deepPurpleAccent,
          ),
        ],
      ),
    );
  }
}

class _MapActivityState {
}






import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:safetyproject/contact/contact_page.dart';
import 'package:safetyproject/location/googlemap_page.dart';
import 'package:safetyproject/pages/sos.dart';

import '../pages/location_page.dart';

class NavBarPage extends StatefulWidget {
  String email;
  NavBarPage({Key? key, required this.email}) : super(key: key);

  @override
  State<NavBarPage> createState() => _NavBarPageState();
}

class _NavBarPageState extends State<NavBarPage> {
  _MapActivityState createState() => _MapActivityState();

  final screens = [
    const LocationPage(),
    SosPage(),
    const ContactPage(),
    GoogleMapPage(),
  ];

  int currentIndex = 1;
  void onTap(int index) {
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
            icon: Icon(Icons.emergency),
            label: 'SOS',
            // backgroundColor: Colors.grey,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contact_page),
            label: 'Contact',
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

class _MapActivityState {}

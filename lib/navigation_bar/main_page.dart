import 'package:flutter/material.dart';
import 'package:safetyproject/contact/personal_emergency_contacts.dart';
import 'package:safetyproject/location/googlemap_page.dart';
import 'package:safetyproject/pages/sos.dart';

import '../oauth/auth_controller.dart';
import '../pages/location_page.dart';

class NavBarPage extends StatefulWidget {
  const NavBarPage({Key? key, required this.email}) : super(key: key);

  final String email;

  @override
  State<NavBarPage> createState() => _NavBarPageState();
}

class _NavBarPageState extends State<NavBarPage> {
  int _currentIndex = 1;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.location_on_outlined),
      selectedIcon: Icon(Icons.location_on),
      label: 'Track',
    ),
    NavigationDestination(
      icon: Icon(Icons.emergency_outlined),
      selectedIcon: Icon(Icons.emergency),
      label: 'SOS',
    ),
    NavigationDestination(
      icon: Icon(Icons.contacts_outlined),
      selectedIcon: Icon(Icons.contacts),
      label: 'Contacts',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: 'Map',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screens = [
      LocationPage(),
      const SosPage(),
      const PersonalEmergencyContacts(deleteFunction: _delete),
      GoogleMapPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => AuthController.instance.logOut(),
          ),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _destinations,
      ),
    );
  }
}

void _delete(int id) {}

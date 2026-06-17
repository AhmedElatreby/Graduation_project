import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:flutter_sms/flutter_sms.dart';

import '../database/db_helper.dart';
import '../location/mymap.dart';

class LocationPage extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<LocationPage> {
  final loc.Location location = loc.Location();
  final audioPlayer = AudioPlayer();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  late DBHelper dbHelper;

  bool sendMessageOkay = true;

  late List<String> recipients = [];

  @override
  void initState() {
    super.initState();
    dbHelper = DBHelper();
    _requestPermission();
    _getUserLocationFromFirebase();
    location.changeSettings(interval: 300, accuracy: loc.LocationAccuracy.high);
    location.enableBackgroundMode(enable: true);
  }

  void recipientList() async {
    List<PersonalEmergency> contacts;
    contacts = await dbHelper.getContacts();
    contacts.forEach((contact) {
      recipients.add(contact.contactNo);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(
            height: 40,
          ),
          Center(
            child: ElevatedButton(
              onPressed: () async {
                await audioPlayer.play(AssetSource('alarm.mp3'));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Alarm activated!'),
                    backgroundColor: Colors.red.shade600,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                  fixedSize: const Size(110, 110),
                  shape: const CircleBorder(),
                  backgroundColor: Colors.yellow),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign, size: 36, color: Colors.black),
                  Text('Alarm',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 50,
          ),
          Center(
            child: GestureDetector(
              onLongPressUp: () async {
                if (sendMessageOkay) {
                  _handleAllMethodsIfNoContacts(
                      _sendEmergencyMessageOnLongPress);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Emergency message send has been cancelled.",
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                sendMessageOkay = true;
              },
              child: Column(
                children: [
                  ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                          fixedSize: const Size(150, 150),
                          shape: const CircleBorder(),
                          backgroundColor: Colors.cyan),
                      child: const Text(
                        'Long Press\nRelease',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )),
                ],
              ),
              onLongPressMoveUpdate: (details) async {
                if (details.offsetFromOrigin.dy < -20) {
                  sendMessageOkay = false;
                }
              },
            ),
          ),
          const SizedBox(
            height: 50,
          ),
          // Center(
          //   child: GestureDetector(
          //     child: Column(
          //       children: [
          //         ElevatedButton(
          //             onPressed: () {
          //               _handleAllMethodsIfNoContacts(
          //                   _sendCancelMessageToRecipients);
          //             },
          //             style: ElevatedButton.styleFrom(
          //                 fixedSize: const Size(80, 80),
          //                 shape: const CircleBorder(),
          //                 primary: Colors.green),
          //             child: const Text(
          //               'Cancel',
          //               style: TextStyle(
          //                 fontSize: 15,
          //                 fontWeight: FontWeight.bold,
          //                 color: Colors.white,
          //               ),
          //             )),
          //       ],
          //     ),
          //   ),
          // ),
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                    onPressed: () {
                      _addLocation();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Your location added to the database.',
                          ),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                    },
                    child: Text('Add my location')),
                TextButton(
                    onPressed: () {
                      _listenLocation();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Your location enabled on the database.',
                          ),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                    },
                    child: Text('Enable live location')),
                TextButton(
                    onPressed: () {
                      _stopListening();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'You stopped sharing your location on the database.',
                          ),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                    },
                    child: Text('Stop live location')),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream:
                  FirebaseFirestore.instance.collection('location').snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text('No locations shared yet',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final lat = doc['latitude'];
                    final lng = doc['longitude'];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.location_pin,
                            color: Theme.of(context).colorScheme.primary),
                        title: Text(doc.id),
                        subtitle: Text('$lat, $lng'),
                        trailing: IconButton(
                          icon: const Icon(Icons.directions),
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (context) => MyMap(doc.id)));
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  _getUserLocationFromFirebase() {
    FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get()
        .then((value) {
      setState(() {});
    });
  }

  Future<void> _addLocation() async {
    try {
      final loc.LocationData _locationResult = await location.getLocation();
      await FirebaseFirestore.instance.collection('location').doc('user1').set({
        'latitude': _locationResult.latitude,
        'longitude': _locationResult.longitude,
      }, SetOptions(merge: true));
      _locationSubscription?.pause(Future.delayed(const Duration(seconds: 10),
          () => _locationSubscription?.resume()));
    } catch (e) {
      print(e);
    }
  }

  Future<void> _listenLocation() async {
    _locationSubscription = location.onLocationChanged.handleError((onError) {
      print(onError);
      _locationSubscription?.cancel();
      setState(() {
        _locationSubscription = null;
      });
    }).listen((loc.LocationData currentlocation) async {
      await FirebaseFirestore.instance.collection('location').doc('user1').set({
        'latitude': currentlocation.latitude,
        'longitude': currentlocation.longitude,
      }, SetOptions(merge: true));
      _locationSubscription?.pause(Future.delayed(const Duration(seconds: 10),
          () => _locationSubscription?.resume()));
    });
  }

  _stopListening() {
    _locationSubscription?.cancel();
    setState(() {
      _locationSubscription = null;
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    audioPlayer.dispose();
    super.dispose();
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

  void _handleAllMethodsIfNoContacts(VoidCallback method) async {
    recipientList();
    List<PersonalEmergency> contacts = await dbHelper.getContacts();
    if (!mounted) return;
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

  // void _sendCancelMessageToRecipients() {
  //   recipientList();
  //   String message = "Please ignore my last message. I'm safe now!";
  //   sendMessageToContacts(recipients, message);
  //   print("on long press up!");
  //   print(message);
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       content: Text(
  //         'A message sent to your contact',
  //       ),
  //       backgroundColor: Colors.green.shade600,
  //     ),
  //   );
  // }

  void _sendEmergencyMessageOnLongPress() async {
    recipientList();
    final snap = await FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get();
    final latitude = snap.data()?['latitude'] ?? '?';
    final longitude = snap.data()?['longitude'] ?? '?';
    var userLoaction = "$latitude,$longitude";
    print("test user location $userLoaction");

    String message =
        "I need help, please find me with the following link: https://maps.google.com/?q=${userLoaction}";
    await sendSMS(message: message, recipients: recipients);

    print(message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'SMS compose opened — tap Send to alert your contacts',
        ),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }
}


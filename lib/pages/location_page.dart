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
    final colorScheme = Theme.of(context).colorScheme;
    final isLive = _locationSubscription != null;

    return Scaffold(
      body: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 28),

            // Alarm — compact pill (secondary action)
            FilledButton.tonal(
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
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign, size: 22),
                  SizedBox(width: 8),
                  Text('Alarm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Long Press — hero button (primary action)
            GestureDetector(
              onLongPressUp: () async {
                if (sendMessageOkay) {
                  _handleAllMethodsIfNoContacts(_sendEmergencyMessageOnLongPress);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Emergency message send has been cancelled.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                sendMessageOkay = true;
              },
              onLongPressMoveUpdate: (details) {
                if (details.offsetFromOrigin.dy < -20) {
                  sendMessageOkay = false;
                }
              },
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  fixedSize: const Size(170, 170),
                  shape: const CircleBorder(),
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  elevation: 6,
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_to_mobile, size: 36),
                    SizedBox(height: 6),
                    Text(
                      'Long Press\n& Release',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Location sharing controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      _addLocation();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Your location added to the database.'),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(minimumSize: Size.zero),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_location_alt_outlined, size: 20),
                        SizedBox(height: 2),
                        Text('Add', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      _listenLocation();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Live location enabled.'),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      backgroundColor: isLive ? colorScheme.primaryContainer : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location, size: 20,
                            color: isLive ? colorScheme.primary : null),
                        const SizedBox(height: 2),
                        Text(
                          isLive ? 'Live ●' : 'Live',
                          style: TextStyle(
                            fontSize: 11,
                            color: isLive ? colorScheme.primary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      _stopListening();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('You stopped sharing your location.'),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(minimumSize: Size.zero),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_outlined, size: 20),
                        SizedBox(height: 2),
                        Text('Stop', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Shared Locations',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),

            const SizedBox(height: 6),

            Expanded(
              child: StreamBuilder(
                stream: FirebaseFirestore.instance.collection('location').snapshots(),
                builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text('No locations shared yet',
                          style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final lat = doc['latitude'];
                      final lng = doc['longitude'];
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.location_pin, color: colorScheme.primary),
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


import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:telephony/telephony.dart';

import '../database/db_helper.dart';
import '../location/mymap.dart';

import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';

class LocationPage extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<LocationPage> {
  final loc.Location location = loc.Location();
  final audioPlayer = AudioCache();
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
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Track Location'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [

          const SizedBox(
            height: 40,
          ),
          Center(
            child: ElevatedButton(
              onPressed: () {
                AudioCache player = AudioCache(prefix: 'assets/');
                player.play('alarm.mp3');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Alarm activated! Police have been informed and on their way.',
                    ),
                    backgroundColor: Colors.red.shade600,
                  ),
                );
              },
              child: const Text('Alarm',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  )),
              style: ElevatedButton.styleFrom(
                  fixedSize: const Size(80, 80),
                  shape: const CircleBorder(),
                  primary: Colors.yellow),
            ),
          ),
          const SizedBox(
            height: 30,
          ),
          Center(
            child: GestureDetector(
              onLongPressUp: () async {
                if (sendMessageOkay){
                  _handleAllMethodsIfNoContacts(_sendEmergencyMessageOnLongPress);
                }
                else {
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
                          primary: Colors.cyan),
                      child: const Text(
                        'Long press release',
                        style: TextStyle(
                          fontSize: 20,
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
            height: 30,
          ),
          Center(
            child: GestureDetector(
              child: Column(
                children: [
                  ElevatedButton(
                      onPressed: () {
                        _handleAllMethodsIfNoContacts(_sendCancelMessageToRecipients);
                      },
                      style: ElevatedButton.styleFrom(
                          fixedSize: const Size(80, 80),
                          shape: const CircleBorder(),
                          primary: Colors.green),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )),
                ],
              ),
            ),
          ),
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
                return ListView.builder(
                  itemCount: snapshot.data?.docs.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      subtitle: Row(
                        children: [
                          Text(snapshot.data!.docs[index]['latitude']
                              .toString()),
                          const SizedBox(
                            width: 20,
                          ),
                          Text(snapshot.data!.docs[index]['longitude']
                              .toString()),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.directions),
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) =>
                                  MyMap(snapshot.data!.docs[index].id)));
                        },
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
          () => {_locationSubscription?.resume()}));
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
          () => {_locationSubscription?.resume()}));
    });
  }

  _stopListening() {
    _locationSubscription?.cancel();
    setState(() {
      _locationSubscription = null;
    });
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

  void _handleAllMethodsIfNoContacts(Function method) async {
    recipientList();
    List<PersonalEmergency> contacts = await dbHelper.getContacts();
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "You don't have any contacts in your contact list...",
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
    else {
      return method();
    }
  }

  void _sendCancelMessageToRecipients() {
    recipientList();
    String message =
        "Please ignore my last message. I'm safe now!";
    sendMessageToContacts(recipients, message);
    print("on long press up!");
    print(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A message sent to your contact',
        ),
        backgroundColor: Colors.green.shade600,
      ),
    );
  }

  void _sendEmergencyMessageOnLongPress() async {
    recipientList();
    var lat = await FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get();
    var location = lat.data()?.values;
    var longitude = location?.toList().last;
    var latitude = location?.toList().first;
    var userLoaction = "$latitude,$longitude";
    print("test user location $userLoaction");

    String message =
        "I need help, please find me with the following link: https://maps.google.com/?q=${userLoaction}";
    sendMessageToContacts(recipients, message);

    print(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A message sent to your emergency contact with your location',
        ),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }
}

void sendMessageToContacts(List<String> recipients, String message) {
  recipients.forEach((number) {
    _sendSingleText(number, message);
  });
}

void _sendSingleText(String number, String message) async {
  final Telephony telephony = Telephony.instance;
  bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

  telephony.sendSms(to: number, message: message);
}

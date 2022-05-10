import 'dart:async';

import 'package:characters/characters.dart';

import 'package:audioplayers/audioplayers.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:telephony/telephony.dart';

import '../database/db_helper.dart';
import '../oauth/auth_controller.dart';
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

  String? _linkMessage;
  bool _isCreatingLink = false;

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Track Location'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(
            height: 20,
          ),
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
                    image: AssetImage("assets/images/loginbtn.png"),
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
          const SizedBox(
            height: 20,
          ),
          Center(
            child: ElevatedButton(
              onPressed: () {
                AudioCache player = AudioCache(prefix: 'assets/');
                player.play('alarm.mp3');
              },
              child: const Text('Alarm'),
            ),
          ),
          Center(
            child: GestureDetector(
              onLongPressUp: () async {
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
                print("on long press up!");
                print(message);
              },
              child: Column(
                children: [
                  ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                          fixedSize: const Size(150, 150),
                          shape: const CircleBorder(),
                          primary: Colors.redAccent),
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
          TextButton(
              onPressed: () {
                _addLocation();
              },
              child: Text('add my location')),
          TextButton(
              onPressed: () {
                _listenLocation();
              },
              child: Text('enable live location')),
          TextButton(
              onPressed: () {
                _stopListening();
              },
              child: Text('stop live location')),
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


  // _getUserLocation() async {
  //   var lat = await FirebaseFirestore.instance
  //       .collection('location')
  //       .doc('user1')
  //       .get();
  //   var location = lat.data()?.values;
  //   var longitude = location?.toList().last;
  //   var latitude = location?.toList().first;
  //   var userLoaction = "$latitude,$longitude";
  //   print("test user location $userLoaction");
  // }

  // _getUserLocation() async {
  //   var lat = await FirebaseFirestore.instance
  //       .collection('location')
  //       .doc('user1')
  //       .get();
  //   print(lat.data()?.values);
  // }

  _getUserLongitude() async {
    var lat1 = await FirebaseFirestore.instance
        .collection('location')
        .doc('user1')
        .get();
    print(lat1['longitude']);
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
      _locationSubscription?.pause(Future.delayed(
          const Duration(milliseconds: 10000),
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
      _locationSubscription?.pause(Future.delayed(
          const Duration(milliseconds: 10000),
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

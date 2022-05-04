import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:telephony/telephony.dart';

import '../database/db_helper.dart';
import '../oauth/auth_controller.dart';
import '../location/mymap.dart';

import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:share_plus/share_plus.dart';

class LocationPage extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<LocationPage> {
  dynamic lat;
  dynamic lng;
  final loc.Location location = loc.Location();
  final audioPlayer = AudioCache();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  late DBHelper dbHelper;
  FirebaseDynamicLinks dynamicLinks = FirebaseDynamicLinks.instance;

  String? _linkMessage;
  bool _isCreatingLink = false;

  late List<String> recipients = [];

  get message =>
      "I need help, please find me with the following code: $_linkMessage.";

  // get url => "https://ahmedelatreby.page.link";

  void initDynamicLinks() async {
    FirebaseDynamicLinks.instance.onLink(
        onSuccess: (PendingDynamicLinkData? dynamicLink) async {
      final Uri? deeplink = dynamicLink!.link;

      if (deeplink != null) {
        handleMyLink(deeplink);
      }
    }, onError: (OnLinkErrorException e) async {
      print("We got error $e");
    });
  }

  void handleMyLink(Uri url) {
    List<String> sepeatedLink = [];

    /// https://ahmedelatreby.page.link/?link=http://com.example.app --> ahmedelatreby.page. and Hellow
    sepeatedLink.addAll(url.path.split('/'));

    print("The Token that i'm interesed in is ${sepeatedLink[1]}");
    Get.to(() => MyMap(sepeatedLink[1]));
  }

  buildDynamicLinks(String message) async {
    String url = "https://ahmedelatreby.page.link";
    final DynamicLinkParameters parameters = DynamicLinkParameters(
      uriPrefix: url,
      link: Uri.parse('$url'),
      androidParameters: AndroidParameters(
        packageName: "com.example.safetyproject",
        minimumVersion: 0,
      ),
      iosParameters: IosParameters(
        bundleId: "Bundle-ID",
        minimumVersion: '0',
      ),
    );
    final ShortDynamicLink dynamicUrl = await parameters.buildShortLink();

    String? desc = '${dynamicUrl.shortUrl.toString()}';

    await Share.share(
      desc,
      subject: message,
    );
  }

  @override
  void initState() {
    super.initState();
    dbHelper = DBHelper();
    _requestPermission();
    initDynamicLinks();
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

  Future<void> _createDynamicLink(bool short) async {
    setState(() {
      _isCreatingLink = true;
    });

    setState(() {
      // _linkMessage = url.toString();
      _isCreatingLink = false;
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
          GestureDetector(
            onLongPressUp: () async {
              recipientList();
              await _createDynamicLink(false);
              print(_linkMessage);
              String message =
                  "I need help, please find me with the following link: https://maps.google.com/?q=$lng.";
              sendMessageToContacts(recipients, message);
            },
            child: Center(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      AudioCache player = AudioCache(prefix: 'assets/');
                      player.play('alarm.mp3');
                    },

                    child: const Text('Alarm'),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
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
                _getLocation();
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text(
                "Share Location",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                  onPressed: () {
                    buildDynamicLinks(message);
                  },
                  icon: Icon(Icons.share)),
            ],
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
                      title:
                          Text(snapshot.data!.docs[index]['name'].toString()),
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

  Stream<List> getLatitude() => FirebaseFirestore.instance
      .collection('location')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());

  _getLocation() async {
    try {
      final loc.LocationData _locationResult = await location.getLocation();
      await FirebaseFirestore.instance.collection('location').doc('user1').set({
        'latitude': _locationResult.latitude,
        'longitude': _locationResult.longitude,
        'name': 'PersonalEmergencyContacts'
      }, SetOptions(merge: true));
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
        'name': 'PersonalEmergencyContacts'
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

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:safetyproject/contact/personal_emergency_contacts_model.dart';
import 'package:telephony/telephony.dart';

import '../database/db_helper.dart';
import '../oauth/auth_controller.dart';
import '../location/mymap.dart';

import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';

import 'package:hypertrack_plugin/hypertrack.dart';
import '../database/network_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

const String publishableKey = 'ljI6s3JPB5eCMzVzdnbvbB3UzCd4oG7NNk6ptdfejhOprahOZG-RaD3WSffWVCKFXoNQoJLL1eU759JBtASLFQ';

class LocationPage extends StatefulWidget {
  const LocationPage({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<LocationPage> {
  final loc.Location location = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  DBHelper? dbHelper;

  late HyperTrack sdk;
  late String deviceId;
  late NetworkHelper helper;
  String result = '';
  bool isLink = false;
  bool isLoading = false;

  late List<String> recipients = [];

  List<String> recipents = ["+447562596358", "+447562596358"];

  void recipientList() async {
    List<PersonalEmergency>? contacts;
    contacts = await dbHelper?.getContacts();
    for (var contact in contacts!) {

      recipients.add(contact.contactNo);
    }
  }

  @override
  void initState() {
    super.initState();
    _requestPermission();
    initializeSdk();
    location.changeSettings(interval: 300, accuracy: loc.LocationAccuracy.high);
    location.enableBackgroundMode(enable: true);
  }

  Future<void> initializeSdk() async {
    sdk = await HyperTrack.initialize(publishableKey);
    deviceId = await sdk.getDeviceId();
    sdk.setDeviceName('Eman');
    helper = NetworkHelper(
      url: 'https://v3.api.hypertrack.com',
      auth:
      'Basic Rzl4VnQ1TVR6anBsQ2FhTnktckRqVTk5UUlZOmdhMG5hamZyMHR2dU9zdUxWZS1oMUFXRk9RcVkzM01xc09scHJlbU1GdGtRV1JfM1AyLUtIZw==',
      id: deviceId,
    );
    print(deviceId);
  }

  void shareLink() async {
    setState(() {
      isLoading = true;
      result = '';
    });
    var data = await helper.getData();
    setState(() {
      result = data['views']['share_url'];
      isLink = true;
      isLoading = false;
    });
  }

  void startTracking() async {
    setState(() {
      isLoading = true;
      result = '';
    });
    var startTrack = await helper.startTracing();
    setState(() {
      result = (startTrack['message']);
      isLink = false;
      isLoading = false;
    });
  }

  void endTracking() async {
    setState(() {
      isLoading = true;
      result = '';
    });
    var endTrack = await helper.endTracing();
    setState(() {
      result = (endTrack['message']);
      isLink = false;
      isLoading = false;
    });
  }

  void lunchUrl() async {
    await launch(result);
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
                    image: AssetImage("assests/images/loginbtn.png"),
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
              var code = 'user1';
              isLink ? lunchUrl : null;
              String message = "I need help, please find me with the following code: $code.";
              sendMessageToContacts(recipients, message);
            },
            child: Center(
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
                  const SizedBox(
                    height: 20,
                  ),
                ],
              ),
            ),
          ),

          TextButton(
              onPressed: () {
                startTracking();
              },
              child: Text('Strat Tracking my Location')),
          TextButton(
              onPressed: () {
                shareLink();
              },
              child: Text('get my Location Link')),
          TextButton(
              onPressed: () {
                endTracking();
              },
              child: Text('End Tracking my Location')),
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
                  });
            },
          )),
        ],
      ),
    );
  }

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
        'name': 'john'
      }, SetOptions(merge: true));
      _locationSubscription?.pause(Future.delayed(const Duration(milliseconds: 10000), () => { _locationSubscription?.resume() }));
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

  telephony.sendSms(
      to: number,
      message: message
  );
}
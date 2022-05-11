// import 'dart:async';
//
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:location/location.dart' as loc;
//
// class DBFirebase {
//   final loc.Location location = loc.Location();
//   StreamSubscription<loc.LocationData>? _locationSubscription;
//
//
//   Future<void> _addLocation() async {
//     try {
//       final loc.LocationData _locationResult = await location.getLocation();
//       await FirebaseFirestore.instance.collection('location').doc('user1').set({
//         'latitude': _locationResult.latitude,
//         'longitude': _locationResult.longitude,
//       }, SetOptions(merge: true));
//       _locationSubscription?.pause(Future.delayed(const Duration(seconds: 10),
//               () => {_locationSubscription?.resume()}));
//     } catch (e) {
//       print(e);
//     }
//   }
//
//   Future<void> _listenLocation() async {
//     _locationSubscription = location.onLocationChanged.handleError((onError) {
//       print(onError);
//       _locationSubscription?.cancel();
//       setState(() {
//         _locationSubscription = null;
//       });
//     }).listen((loc.LocationData currentlocation) async {
//       await FirebaseFirestore.instance.collection('location').doc('user1').set({
//         'latitude': currentlocation.latitude,
//         'longitude': currentlocation.longitude,
//       }, SetOptions(merge: true));
//       _locationSubscription?.pause(Future.delayed(const Duration(seconds: 10),
//               () => {_locationSubscription?.resume()}));
//     });
//   }
//
//   Future _stopListening() async {
//     await _locationSubscription?.cancel();
//     setState(() {
//       _locationSubscription = null;
//     });
//   }
//
//   Future _requestPermission() async {
//     var status = await Permission.location.request();
//     if (status.isGranted) {
//       print('done');
//     } else if (status.isDenied) {
//       _requestPermission();
//     } else if (status.isPermanentlyDenied) {
//       openAppSettings();
//     }
//   }
//
//   void setState(Null Function() param0) {}
// }

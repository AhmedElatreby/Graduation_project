import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NetworkHelper {
  var devices;

  NetworkHelper({required this.url, required this.auth, required this.id});
   String url;
   String auth;
   String id;

  Future startTracing() async {
    http.Response response = await http.post(Uri.parse('$url/devices/$id/start'),
        body: null, headers: {'Authorization': auth});
    if (response.statusCode == 200) {
      String data = response.body;
      return jsonDecode(data);
    } else {
      print(response.statusCode);
    }
  }

  Future getData() async {
    http.Response response =
    await http.get(Uri.parse('$url/devices/$id'), headers: {'Authorization': auth});
    if (response.statusCode == 200) {
      String data = response.body;
      return jsonDecode(data);
    } else {
      print(response.statusCode);
    }
  }


  // Future<void> _listenLocation() async {
  //   _locationSubscription = location.onLocationChanged.handleError((onError) {
  //     print(onError);
  //     _locationSubscription?.cancel();
  //     setState(() {
  //       _locationSubscription = null;
  //     });
  //   }).listen((loc.LocationData currentlocation) async {
  //     await FirebaseFirestore.instance.collection('location').doc('user1').set({
  //       'latitude': currentlocation.latitude,
  //       'longitude': currentlocation.longitude,
  //       'name': 'User'
  //     }, SetOptions(merge: true));
  //     _locationSubscription?.pause(Future.delayed(const Duration(milliseconds: 10000), () => { _locationSubscription?.resume() }));
  //   });
  // }






  Future endTracing() async {
    http.Response response = await http.post(Uri.parse('$url/devices/$id/stop'),
        body: null, headers: {'Authorization': auth});
    if (response.statusCode == 200) {
      String data = response.body;
      return jsonDecode(data);
    } else {
      print(response.statusCode);
    }
  }
}
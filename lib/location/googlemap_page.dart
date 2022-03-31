import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GoogleMapPage extends StatefulWidget {
  @override
  State<GoogleMapPage> createState() => GoogleMapState();
}

class GoogleMapState extends State<GoogleMapPage> {
  Completer<GoogleMapController> _controller = Completer();

  static final CameraPosition _kBournemouthUniversity = CameraPosition(
    target: LatLng(50.742347717285156, -1.894766092300415),
    zoom: 14.4746,
  );


  static final Marker _kBournemouthUniversityMarker = Marker(
    markerId: MarkerId('_kBournemouthUniversity'),
    infoWindow: InfoWindow(title: 'Bournemouth University'),
    icon: BitmapDescriptor.defaultMarker,
    position: LatLng(50.742347717285156, -1.894766092300415),
  );

  static final CameraPosition _kHome = CameraPosition(
      bearing: 192.8334901395799,
      target: LatLng(50.73540115356445, -1.8586000204086304),
      tilt: 59.440717697143555,
      zoom: 19.151926040649414);

  static final Marker _kHomeMarker = Marker(
    markerId: MarkerId('_kHomeMarker'),
    infoWindow: InfoWindow(title: 'Home'),
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    position: LatLng(50.73540115356445, -1.8586000204086304),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        mapType: MapType.satellite,
        markers: {_kBournemouthUniversityMarker, _kHomeMarker},
        initialCameraPosition: _kBournemouthUniversity,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goMyLocation,
        label: const Text('My location!'),
        icon: const Icon(Icons.directions_walk),
      ),
    );
  }

  Future<void> _goMyLocation() async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(_kHome));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · Map (route + navigate)
//  Replaces:  lib/location/googlemap_page.dart
//  ★ #4  Restyled to the Lumi design system and FIXED the invisible input text:
//        the fields used a white fill on a dark theme, so the typed "direction"
//        text was white-on-white. Fields are now dark with light text + a proper
//        Lumi panel and buttons. All routing / geocoding logic is unchanged.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../secrets.dart';
import '../theme/lumi_theme.dart';

class GoogleMapPage extends StatefulWidget {
  @override
  _GoogleMapPageState createState() => _GoogleMapPageState();
}

class _GoogleMapPageState extends State<GoogleMapPage> {
  final CameraPosition _initialLocation =
      const CameraPosition(target: LatLng(0.0, 0.0));
  // Nullable, not `late`: _getCurrentLocation() kicks off in initState and can
  // resolve before onMapCreated, which used to throw LateInitializationError
  // on every launch. Camera moves are simply skipped until the map exists.
  GoogleMapController? mapController;

  Position? _currentPosition;
  String _currentAddress = '';

  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();

  final startAddressFocusNode = FocusNode();
  final desrinationAddressFocusNode = FocusNode();

  String _startAddress = '';
  String _destinationAddress = '';
  String? _placeDistance;
  LatLng? _startLatLng;
  LatLng? _destinationLatLng;

  Set<Marker> markers = {};

  late PolylinePoints polylinePoints;
  Map<PolylineId, Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Lumi-styled input field (dark fill + LIGHT text — fixes white-on-white) ──
  Widget _textField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required double width,
    required Icon prefixIcon,
    Widget? suffixIcon,
    required Function(String) locationCallback,
  }) {
    return SizedBox(
      width: width * 0.82,
      child: TextField(
        onChanged: (value) => locationCallback(value),
        controller: controller,
        focusNode: focusNode,
        style: LumiText.body(15, color: LumiColors.text), // ★ visible text
        cursorColor: LumiColors.accent,
        decoration: InputDecoration(
          prefixIcon: prefixIcon,
          prefixIconColor: LumiColors.textFaint,
          suffixIcon: suffixIcon,
          suffixIconColor: LumiColors.textFaint,
          labelText: label,
          labelStyle: LumiText.body(14, color: LumiColors.textSub),
          floatingLabelStyle: LumiText.body(14, color: LumiColors.accent),
          hintText: hint,
          hintStyle: LumiText.body(14, color: LumiColors.textFaint),
          filled: true,
          fillColor: LumiColors.field, // ★ dark fill
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: LumiColors.hairline, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: LumiColors.accent, width: 1.6),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  // Method for retrieving the current location
  _getCurrentLocation() async {
    await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).then((Position position) async {
      setState(() {
        _currentPosition = position;
        mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 18.0,
            ),
          ),
        );
      });
      await _getAddress();
    }).catchError((e) {
      print(e);
    });
  }

  // Method for retrieving the address
  _getAddress() async {
    if (_currentPosition == null) return;
    try {
      List<Placemark> p = await placemarkFromCoordinates(
          _currentPosition!.latitude, _currentPosition!.longitude);

      Placemark place = p[0];

      setState(() {
        _currentAddress =
            "${place.name}, ${place.locality}, ${place.postalCode}, ${place.country}";
        startAddressController.text = _currentAddress;
        _startAddress = _currentAddress;
      });
    } catch (e) {
      print(e);
    }
  }

  // Method for calculating the distance between two places
  Future<bool> _calculateDistance() async {
    try {
      List<Location> startPlacemark = await locationFromAddress(_startAddress);
      List<Location> destinationPlacemark =
          await locationFromAddress(_destinationAddress);

      if (startPlacemark.isEmpty) {
        throw Exception('Could not find start address');
      }
      if (destinationPlacemark.isEmpty) {
        throw Exception('Could not find destination address');
      }

      double startLatitude =
          (_startAddress == _currentAddress && _currentPosition != null)
              ? _currentPosition!.latitude
              : startPlacemark[0].latitude;

      double startLongitude =
          (_startAddress == _currentAddress && _currentPosition != null)
              ? _currentPosition!.longitude
              : startPlacemark[0].longitude;

      double destinationLatitude = destinationPlacemark[0].latitude;
      double destinationLongitude = destinationPlacemark[0].longitude;

      String startCoordinatesString = '($startLatitude, $startLongitude)';
      String destinationCoordinatesString =
          '($destinationLatitude, $destinationLongitude)';

      Marker startMarker = Marker(
        markerId: MarkerId(startCoordinatesString),
        position: LatLng(startLatitude, startLongitude),
        infoWindow: InfoWindow(
          title: 'Start $startCoordinatesString',
          snippet: _startAddress,
        ),
        icon: BitmapDescriptor.defaultMarker,
      );

      Marker destinationMarker = Marker(
        markerId: MarkerId(destinationCoordinatesString),
        position: LatLng(destinationLatitude, destinationLongitude),
        infoWindow: InfoWindow(
          title: 'Destination $destinationCoordinatesString',
          snippet: _destinationAddress,
        ),
        icon: BitmapDescriptor.defaultMarker,
      );

      markers.add(startMarker);
      markers.add(destinationMarker);

      double miny = (startLatitude <= destinationLatitude)
          ? startLatitude
          : destinationLatitude;
      double minx = (startLongitude <= destinationLongitude)
          ? startLongitude
          : destinationLongitude;
      double maxy = (startLatitude <= destinationLatitude)
          ? destinationLatitude
          : startLatitude;
      double maxx = (startLongitude <= destinationLongitude)
          ? destinationLongitude
          : startLongitude;

      mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            northeast: LatLng(maxy, maxx),
            southwest: LatLng(miny, minx),
          ),
          100.0,
        ),
      );

      await _createPolylines(startLatitude, startLongitude, destinationLatitude,
          destinationLongitude);

      double totalDistance = 0.0;
      for (int i = 0; i < polylineCoordinates.length - 1; i++) {
        totalDistance += _coordinateDistance(
          polylineCoordinates[i].latitude,
          polylineCoordinates[i].longitude,
          polylineCoordinates[i + 1].latitude,
          polylineCoordinates[i + 1].longitude,
        );
      }

      setState(() {
        _placeDistance = totalDistance.toStringAsFixed(2);
        _startLatLng = LatLng(startLatitude, startLongitude);
        _destinationLatLng = LatLng(destinationLatitude, destinationLongitude);
      });

      return true;
    } catch (e) {
      print('_calculateDistance error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not calculate route: $e'),
            backgroundColor: LumiColors.accent,
          ),
        );
      }
    }
    return false;
  }

  double _coordinateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  _createPolylines(
    double startLatitude,
    double startLongitude,
    double destinationLatitude,
    double destinationLongitude,
  ) async {
    polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      googleApiKey: Secrets.API_KEY,
      request: PolylineRequest(
        origin: PointLatLng(startLatitude, startLongitude),
        destination: PointLatLng(destinationLatitude, destinationLongitude),
        mode: TravelMode.transit,
      ),
    );

    if (result.points.isNotEmpty) {
      for (var point in result.points) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }
    }

    PolylineId id = const PolylineId('poly');
    Polyline polyline = Polyline(
      polylineId: id,
      color: LumiColors.accent,
      points: polylineCoordinates,
      width: 4,
    );
    polylines[id] = polyline;
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // round icon button matching the Lumi dark surface
  Widget _mapButton({required IconData icon, required VoidCallback onTap}) {
    return ClipOval(
      child: Material(
        color: const Color(0xF2141C2E),
        child: InkWell(
          splashColor: LumiColors.accent.withOpacity(0.2),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: LumiColors.text, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    return SizedBox(
      height: height,
      width: width,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: LumiColors.bgDeep,
        body: Stack(
          children: <Widget>[
            // Map View
            GoogleMap(
              markers: Set<Marker>.from(markers),
              initialCameraPosition: _initialLocation,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              zoomGesturesEnabled: true,
              zoomControlsEnabled: false,
              polylines: Set<Polyline>.of(polylines.values),
              onMapCreated: (GoogleMapController controller) {
                mapController = controller;
                // If the GPS fix arrived before the map was ready, catch up.
                final pos = _currentPosition;
                if (pos != null) {
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(pos.latitude, pos.longitude),
                        zoom: 18.0,
                      ),
                    ),
                  );
                }
              },
            ),

            // Zoom buttons
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _mapButton(
                        icon: Icons.add,
                        onTap: () => mapController
                            ?.animateCamera(CameraUpdate.zoomIn())),
                    const SizedBox(height: 14),
                    _mapButton(
                        icon: Icons.remove,
                        onTap: () => mapController
                            ?.animateCamera(CameraUpdate.zoomOut())),
                  ],
                ),
              ),
            ),

            // Places panel
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Container(
                    width: width * 0.92,
                    decoration: BoxDecoration(
                      color: const Color(0xF2131C30), // Midnight panel, ~95%
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(color: LumiColors.hairline),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: [
                              const Icon(Icons.route,
                                  color: LumiColors.accent, size: 18),
                              const SizedBox(width: 8),
                              Text('Plan a route', style: LumiText.display(17)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _textField(
                            label: 'Start',
                            hint: 'Choose starting point',
                            prefixIcon: const Icon(Icons.trip_origin, size: 20),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.my_location, size: 20),
                              onPressed: () {
                                startAddressController.text = _currentAddress;
                                _startAddress = _currentAddress;
                              },
                            ),
                            controller: startAddressController,
                            focusNode: startAddressFocusNode,
                            width: width,
                            locationCallback: (String value) {
                              setState(() => _startAddress = value);
                            },
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            label: 'Destination',
                            hint: 'Choose destination',
                            prefixIcon:
                                const Icon(Icons.place_outlined, size: 20),
                            controller: destinationAddressController,
                            focusNode: desrinationAddressFocusNode,
                            width: width,
                            locationCallback: (String value) {
                              setState(() => _destinationAddress = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_placeDistance != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: LumiColors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: LumiColors.green.withOpacity(0.3)),
                              ),
                              child: Text(
                                'DISTANCE · $_placeDistance km',
                                textAlign: TextAlign.center,
                                style: LumiText.body(13.5,
                                    weight: FontWeight.w700,
                                    color: LumiColors.greenSoft),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final start = _startLatLng!;
                                  final dest = _destinationLatLng!;
                                  final uri = Uri.parse(
                                    'https://www.google.com/maps/dir/?api=1'
                                    '&origin=${start.latitude},${start.longitude}'
                                    '&destination=${dest.latitude},${dest.longitude}'
                                    '&travelmode=driving',
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                                icon: const Icon(Icons.navigation,
                                    color: Colors.white, size: 18),
                                label: Text('Navigate',
                                    style: LumiText.display(14.5,
                                        color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: LumiColors.green,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_startAddress != '' &&
                                      _destinationAddress != '')
                                  ? () async {
                                      startAddressFocusNode.unfocus();
                                      desrinationAddressFocusNode.unfocus();
                                      setState(() {
                                        if (markers.isNotEmpty) markers.clear();
                                        if (polylines.isNotEmpty) {
                                          polylines.clear();
                                        }
                                        if (polylineCoordinates.isNotEmpty) {
                                          polylineCoordinates.clear();
                                        }
                                        _placeDistance = null;
                                        _startLatLng = null;
                                        _destinationLatLng = null;
                                      });

                                      _calculateDistance().then((isCalculated) {
                                        if (isCalculated && mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Route calculated successfully'),
                                            ),
                                          );
                                        }
                                      });
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: LumiColors.accent,
                                disabledBackgroundColor:
                                    LumiColors.accent.withOpacity(0.3),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text('Show route',
                                  style: LumiText.display(15.5,
                                      color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Current location button
            SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12.0, bottom: 96.0),
                  child: ClipOval(
                    child: Material(
                      color: LumiColors.accent,
                      child: InkWell(
                        splashColor: Colors.white24,
                        onTap: () {
                          if (_currentPosition == null) return;
                          mapController?.animateCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(
                                target: LatLng(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                ),
                                zoom: 18.0,
                              ),
                            ),
                          );
                        },
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(Icons.my_location, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

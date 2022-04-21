import 'package:flutter/material.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import '../location/location_service.dart';
import '../oauth/auth_controller.dart';
import 'package:location/location.dart';



class LocationPage extends StatefulWidget {
  const LocationPage({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<LocationPage> {
  List<String> recipents = ["+447562596358", "+447562596358"];


  String? lat, long, country, city, adminArea, _locationPosition;

  @override
  void initState() {
    super.initState();
    getLocation();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Current Location'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
            Center(
              child: Container(
                margin: const EdgeInsets.only(left: 20, right: 20),
                width: width,
                // child: Column(
                //   crossAxisAlignment: CrossAxisAlignment.start,
                //   children: [
                //     Text('Location Info:', style: getStyle(size: 24),),
                //     const SizedBox(height: 20,),
                //     Text('Latitude: ${lat ?? 'Loading ...'}', style: getStyle(),),
                //     const SizedBox(height: 20,),
                //     Text('Longitude: ${long ?? 'Loading ...'}', style: getStyle(),),
                //     const SizedBox(height: 20,),
                //     Text('Country: ${country ?? 'Loading ...'}', style: getStyle(),),
                //     const SizedBox(height: 20,),
                //     Text('Admin Area: ${adminArea ?? 'Loading ...'}', style: getStyle(),),
                //
                //   ],
                // ),
              ),
            ),
            const SizedBox(height: 20,),
            GestureDetector(
              onLongPressUp: ()  {
                String message = "$_locationPosition This is a test message!";
                _sendSMS(message, recipents,_locationPosition);
              },
              child: Center(
                child: Column(
                  children: [
                    ElevatedButton(
                        onPressed: ()  {},
                        style: ElevatedButton.styleFrom(
                            fixedSize: const Size(150, 150),
                            shape: const CircleBorder(),primary: Colors.redAccent
                        ),
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
          ],
        ),
      ),
    );
  }

  TextStyle getStyle({double size = 20}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.bold);

  void getLocation() async {
    final service = LocationService();
    final locationData = await service.getLocation();

    if(locationData != null){

      final placeMark = await service.getPlaceMark(locationData: locationData);

      setState(() {
        lat = locationData.latitude!.toStringAsFixed(2);
        long = locationData.longitude!.toStringAsFixed(2);

        country = placeMark?.country ?? 'could not get country';
        adminArea = placeMark?.administrativeArea ?? 'could not get admin area';
      });
    }
  }
}

// class LocationProvider with ChangeNotifier {
//   BitmapDescriptor? _pinLocationIcon;
//   BitmapDescriptor? get pinLocationIcon => _pinLocationIcon;
//   Map<MarkerId, Marker>? _marker;
//   Map<MarkerId, Marker>? get marker => _marker;
//
//   final MarkerId markerId = const MarkerId("1");
//
//   Location? _location;
//   Location? get location => _location;
//   LatLng? _locationPosition;
//   LatLng? get locationPosition => _locationPosition;
//
//   bool locationServiceActive = true;
//
//   LocationProvider() {
//     _location = Location();
//   }
//
//   initialization() async {
//     await getUserLocation();
//     await setCustomMapPin();
//   }
//
//   getUserLocation() async {
//     bool _serviceEnable;
//     PermissionStatus _permissionGranted;
//
//     _serviceEnable = await location!.serviceEnabled();
//     if (!_serviceEnable) {
//       _serviceEnable = await location!.requestService();
//
//       if (!_serviceEnable) {
//         return;
//       }
//     }
//
//     _permissionGranted = await location!.hasPermission();
//     if (_permissionGranted == PermissionStatus.denied) {
//       _permissionGranted = await location!.requestPermission();
//
//       if (_permissionGranted != PermissionStatus.granted) {
//         return;
//       }
//     }
//
//     location!.onLocationChanged.listen((LocationData currentLocation) {
//       _locationPosition =
//           LatLng(currentLocation.latitude!, currentLocation.longitude!);
//
//       print(_locationPosition);
//
//       _marker = <MarkerId, Marker>{};
//       Marker marker = Marker(
//         markerId: markerId,
//         position: LatLng(currentLocation.latitude!, currentLocation.longitude!),
//         icon: (pinLocationIcon)!,
//         draggable: true,
//         onDragEnd: ((newPosition) {
//           _locationPosition =
//               LatLng(newPosition.latitude, newPosition.longitude);
//           notifyListeners();
//         }),
//       );
//
//       _marker![markerId] = marker;
//       notifyListeners();
//     });
//   }
//
//   setCustomMapPin() async {
//     _pinLocationIcon = await BitmapDescriptor.fromAssetImage(
//       ImageConfiguration(devicePixelRatio: 2.5),
//       'assets/pin1.png',
//     );
//   }
// }

void _sendSMS(String message, List<String> recipents, _location ) async {
  String _result = await sendSMS(message: message, recipients: recipents)
      .catchError((onError) {
    print(onError);
  });
  print(_result);
}

class LocationProvider with ChangeNotifier {
  BitmapDescriptor? _pinLocationIcon;
  BitmapDescriptor? get pinLocationIcon => _pinLocationIcon;
  Map<MarkerId, Marker>? _marker;
  Map<MarkerId, Marker>? get marker => _marker;

  final MarkerId markerId = const MarkerId("1");

  Location? _location;
  Location? get location => _location;
  LatLng? _locationPosition;
  LatLng? get locationPosition => _locationPosition;

  bool locationServiceActive = true;

  LocationProvider() {
    _location = Location();
  }

  initialization() async {
    await getUserLocation();
    await setCustomMapPin();
  }

  getUserLocation() async {
    bool _serviceEnable;
    PermissionStatus _permissionGranted;

    _serviceEnable = await location!.serviceEnabled();
    if (!_serviceEnable) {
      _serviceEnable = await location!.requestService();

      if (!_serviceEnable) {
        return;
      }
    }

    _permissionGranted = await location!.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location!.requestPermission();

      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    location!.onLocationChanged.listen((LocationData currentLocation) {
      _locationPosition =
          LatLng(currentLocation.latitude!, currentLocation.longitude!);

      print(_locationPosition);

      _marker = <MarkerId, Marker>{};
      Marker marker = Marker(
        markerId: markerId,
        position: LatLng(currentLocation.latitude!, currentLocation.longitude!),
        icon: (pinLocationIcon)!,
        draggable: true,
        onDragEnd: ((newPosition) {
          _locationPosition =
              LatLng(newPosition.latitude, newPosition.longitude);
          notifyListeners();
        }),
      );

      _marker![markerId] = marker;
      notifyListeners();
    });
  }

  setCustomMapPin() async {
    _pinLocationIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 2.5),
      'assets/pin1.png',
    );
  }
}

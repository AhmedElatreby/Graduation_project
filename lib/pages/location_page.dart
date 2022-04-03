import 'package:flutter/material.dart';
import '../location/location_service.dart';

class LocationPage extends StatefulWidget {
  const LocationPage({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<LocationPage> {

  String? lat, long, country, city, adminArea;

  @override
  void initState() {
    super.initState();
    getLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Current Location'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location Info:', style: getStyle(size: 24),),
            const SizedBox(height: 20,),
            Text('Latitude: ${lat ?? 'Loading ...'}', style: getStyle(),),
            const SizedBox(height: 20,),
            Text('Longitude: ${long ?? 'Loading ...'}', style: getStyle(),),
            const SizedBox(height: 20,),
            Text('Country: ${country ?? 'Loading ...'}', style: getStyle(),),
            const SizedBox(height: 20,),
            // Text('city: ${city ?? 'Loading ...'}', style: getStyle(),),
            // const SizedBox(height: 20,),
            Text('Admin Area: ${adminArea ?? 'Loading ...'}', style: getStyle(),),
            const SizedBox(height: 20,),
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
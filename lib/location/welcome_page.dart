// import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_sms/flutter_sms.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:safetyproject/oauth/auth_controller.dart';
// import 'package:safetyproject/pages/sos.dart';
// import 'package:url_launcher/url_launcher.dart';
//
// import '../pages/location_page.dart';
//
// // class WelcomePage extends StatefulWidget {
// //   String email;
// //
// //   WelcomePage({Key? key, required this.email}) : super(key: key);
// //
// //   @override
// //   State<WelcomePage> createState() => _WelcomePageState();
// // }
// //
// // class _WelcomePageState extends State<WelcomePage> {
// //   _MapActivityState createState() => _MapActivityState();
// //
// //   int currentIndex = 0;
// //
// //   final screens = [
// //     LocationPage(),
// //     SosPage(),
// //     LocationPage(),
// //     LocationPage(),
// //   ];
// //
// //   List<String> recipents = ["+447562596358", "+447562596358"];
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     double width = MediaQuery.of(context).size.width;
// //     double height = MediaQuery.of(context).size.height;
// //     screens[currentIndex];
// //     bottomNavigationBar:
// //     BottomNavigationBar(
// //       type: BottomNavigationBarType.fixed,
// //       backgroundColor: Colors.blue,
// //       selectedItemColor: Colors.white,
// //       unselectedItemColor: Colors.white70,
// //       iconSize: 30,
// //       currentIndex: currentIndex,
// //       onTap: (index) => setState(() => currentIndex = index),
// //       items: const [
// //         BottomNavigationBarItem(
// //           icon: Icon(Icons.home),
// //           label: 'Home',
// //           // backgroundColor: Colors.blue,
// //         ),
// //         BottomNavigationBarItem(
// //           icon: Icon(Icons.call),
// //           label: 'SOS',
// //           // backgroundColor: Colors.grey,
// //         ),
// //         BottomNavigationBarItem(
// //           icon: Icon(Icons.mail),
// //           label: 'Mail',
// //           // backgroundColor: Colors.deepPurpleAccent,
// //         ),
// //         BottomNavigationBarItem(
// //           icon: Icon(Icons.map),
// //           label: 'Map',
// //           // backgroundColor: Colors.deepPurpleAccent,
// //         ),
// //       ],
// //     );
// //
// //     return Scaffold(
// //       backgroundColor: Colors.white,
// //       body: Column(
// //         children: [
// //           const SizedBox(
// //             height: 70,
// //           ),
// //           GestureDetector(
// //             onTap: () {
// //               AuthController.instance.logOut();
// //             },
// //             child: Container(
// //               width: width,
// //               margin: const EdgeInsets.only(left: 20),
// //               child: Column(
// //                 crossAxisAlignment: CrossAxisAlignment.start,
// //                 children: [
// //                   const Text(
// //                     "Welcome",
// //                     style: TextStyle(
// //                         fontSize: 36,
// //                         fontWeight: FontWeight.bold,
// //                         color: Colors.black54),
// //                   ),
// //                   Text(
// //                     widget.email,
// //                     style: const TextStyle(fontSize: 18, color: Colors.grey),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ),
// //           const SizedBox(
// //             height: 50,
// //           ),
// //           GestureDetector(
// //             onTap: () {
// //               AuthController.instance.logOut();
// //             },
// //             child: Column(
// //               children: [
// //                 TextButton(
// //                     onPressed: () async {
// //                       if (!await launch('tel:+447562596358')) {
// //                         throw 'Could not launch';
// //                       }
// //                     },
// //                     child: const Text(
// //                       'Call',
// //                       style: TextStyle(
// //                         fontSize: 30,
// //                         fontWeight: FontWeight.bold,
// //                       ),
// //                     )),
// //                 const Center(
// //                   child: Text(
// //                     "SOS",
// //                     style: TextStyle(
// //                       fontSize: 30,
// //                       fontWeight: FontWeight.bold,
// //                       color: Colors.white,
// //                     ),
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           ),
// //           const SizedBox(
// //             height: 10,
// //           ),
// //           GestureDetector(
// //             onTap: () {
// //               AuthController.instance.logOut();
// //             },
// //             child: Column(
// //               children: [
// //                 TextButton(
// //                     onPressed: () async {
// //                       String message = "This is a test message!";
// //                       _sendSMS(message, recipents);
// //                     },
// //                     child: const Text(
// //                       'SMS',
// //                       style: TextStyle(
// //                         fontSize: 30,
// //                         fontWeight: FontWeight.bold,
// //                       ),
// //                     )),
// //                 const Center(
// //                   child: Text(
// //                     "SOS",
// //                     style: TextStyle(
// //                       fontSize: 30,
// //                       fontWeight: FontWeight.bold,
// //                       color: Colors.white,
// //                     ),
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           ),
// //           const SizedBox(
// //             height: 50,
// //           ),
// //           GestureDetector(
// //             onTap: () {
// //               AuthController.instance.logOut();
// //             },
// //             child: Container(
// //               width: width * 0.4,
// //               height: height * 0.07,
// //               decoration: BoxDecoration(
// //                 borderRadius: BorderRadius.circular(30),
// //                 image: const DecorationImage(
// //                     image: AssetImage("assets/images/loginbtn.png"),
// //                     fit: BoxFit.cover),
// //               ),
// //               child: const Center(
// //                 child: Text(
// //                   "Sign out",
// //                   style: TextStyle(
// //                     fontSize: 30,
// //                     fontWeight: FontWeight.bold,
// //                     color: Colors.white,
// //                   ),
// //                 ),
// //               ),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }
// //
// // void _sendSMS(String message, List<String> recipents) async {
// //   String _result = await sendSMS(message: message, recipients: recipents)
// //       .catchError((onError) {
// //     print(onError);
// //   });
// //   print(_result);
// // }
// //
// // class MapActivity extends StatefulWidget {
// //   @override
// //   _MapActivityState createState() => _MapActivityState();
// // }
// //
// // class _MapActivityState extends State<MapActivity> {
// //   late LatLng _center;
// //   late Position currentLocation;
// //
// //   @override
// //   void initState() {
// //     // TODO: implement initState
// //     super.initState();
// //     getUserLocation();
// //   }
// //
// //   Future<Position> locateUser() async {
// //     return Geolocator.getCurrentPosition(
// //         desiredAccuracy: LocationAccuracy.high);
// //   }
// //
// //   getUserLocation() async {
// //     currentLocation = await locateUser();
// //     setState(() {
// //       _center = LatLng(currentLocation.latitude, currentLocation.longitude);
// //     });
// //     print('center $_center');
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     // TODO: implement build
// //     throw UnimplementedError();
// //   }
// // }
// //
// // class LatLng {
// //   LatLng(double latitude, double longitude);
// // }

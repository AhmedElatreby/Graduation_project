import '../emergencyContacts.class.dart';
import '../utils/get-color-gradient.dart';
import 'package:flutter/material.dart';

class ContactAvatar extends StatelessWidget {
  ContactAvatar(this.contact, this.size);
  final EmergencyContacts contact;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, gradient: getColorGradient(contact.color)),
        child: (contact.info.avatar != null && contact.info.avatar!.length > 0)
            ? const CircleAvatar(
                backgroundImage: NetworkImage(
                    "https://pbs.twimg.com/profile_images/1304985167476523008/QNHrwL2q_400x400.jpg"),
          radius: 100,
              )
            : CircleAvatar(
                child: Text(contact.info.initials(),
                    style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.transparent));
  }
}

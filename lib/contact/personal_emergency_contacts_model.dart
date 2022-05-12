class PersonalEmergency {
  late int id;
  late String name, contactNo;
  late bool primaryContact;
  PersonalEmergency(this.name, this.contactNo, this.primaryContact);

  // EmergencyContacts(this.initials, this.name, this.contactNo);

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{'id': id, 'name': name, 'contactNo': contactNo, 'primaryContact': primaryContact};
    return map;
  }

  PersonalEmergency.fromMap(Map<dynamic, dynamic> map) {
    id = map['id'];
    name = map['name'];
    contactNo = map['contactNo'];
    contactNo = map['primaryContact'];
  }
}

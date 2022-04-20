class PersonalContacts {
  late int id;
  late String name, contactNo;
  // PersonalContacts(this.name, this.contactNo);
  PersonalContacts( String name, String contactNo) {

    this.name = name;
    this.contactNo = contactNo;
  }

  // EmergencyContacts(this.initials, this.name, this.contactNo);

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{'id': id, 'name': name, 'contactNo': contactNo};
    return map;
  }

  PersonalContacts.fromMap(Map<dynamic, dynamic> map) {
    id = map['id'];
    name = map['name'];
    contactNo = map['contactNo'];
  }
}
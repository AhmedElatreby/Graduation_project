class PersonalContacts {
  late int id;
  late String name, contactNo;

  PersonalContacts(this.name, this.contactNo);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'contactNo': contactNo,
    };
  }

  PersonalContacts.fromMap(Map<String, dynamic> map)
      : id = map["id"],
        name = map["name"],
        contactNo = map["contactNo"];

  @override
  String toString() {
    return 'contacts{ name: $name, contactNo: $contactNo}';
  }
}
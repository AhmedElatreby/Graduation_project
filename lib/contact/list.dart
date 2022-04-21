import 'package:flutter/material.dart';
import 'add_contact.dart';
import 'db_helper.dart';
import 'personal_contacts.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({Key? key}) : super(key: key);

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  late DBHelper handler;
  late Future<List<PersonalContacts>> _contacts;

  @override
  void initState() {
    super.initState();
    handler = DBHelper();
    handler.initDatabase().whenComplete(() async {
      setState(() {
        _contacts = getList();
      });
    });
  }

  Future<List<PersonalContacts>> getList() async {
    return await handler.contacts();
  }

  Future<void> refreshContacts() async {
    setState(() {
      var emergencyContactsName = [];
      var emergencyContactsInitials = [];
      var emergencyContactsNo = [];
      var contacts = DBHelper() as Future<List<PersonalContacts>>?;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddContact()),
          );
        },
        child: const Icon(Icons.add),
        backgroundColor: Colors.deepOrange,
      ),
      body: FutureBuilder<List<PersonalContacts>>(
        future: _contacts,
        builder: (BuildContext context, AsyncSnapshot<List<PersonalContacts>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            final items = snapshot.data ?? <PersonalContacts>[];
            return Scrollbar(
              child: RefreshIndicator(
                // refreshContacts: refreshContacts,
                onRefresh: () async {  },
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int index) {
                    return Dismissible(
                      direction: DismissDirection.startToEnd,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: const Icon(Icons.delete_forever),
                      ),
                      key: ValueKey<int>(items[index].id),
                      onDismissed: (DismissDirection direction) async {
                        await handler.delete(items[index].id);
                        setState(() {
                          items.remove(items[index]);
                        });
                      },
                      child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(8.0),
                            title: Text(items[index].name),
                            subtitle: Text(items[index].contactNo.toString()),
                          )),
                    );
                  },
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
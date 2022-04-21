import 'personal_contactss.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'personal_contacts.dart';

class DBHelper {
  var contacts;

  Future<Database> initDatabase() async {
    return openDatabase(
      join( 'EmergencyContacts.db'),
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE todos(id INTEGER PRIMARY KEY, title TEXT, description TEXT)',
        );
      },
      version: 1,
    );
  }

  Future<void> add(PersonalContacts) async {
    final db = await initDatabase();
    await db.insert(
      "INSERT into contacts( name,contactNo)"
          "VALUES(?, ?)",
      contacts.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List> getContacts() async {
    final db = await initDatabase();
    final List<Map<String, dynamic>> queryResult = await db.query('todos');
    return queryResult.map((e) => contacts.fromMap(e)).toList();
  }

  Future<void> delete(int id) async {
    final db = await initDatabase();
    await db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
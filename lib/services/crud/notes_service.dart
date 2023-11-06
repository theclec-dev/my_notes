import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_notes/services/crud/crud_exceptions.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

class NoteService {
  NoteService.sharedInstances();
  static final NoteService _shared = NoteService.sharedInstances();

  factory NoteService() => _shared;

  Database? _db;

  List<DatabaseNote> _notes = [];
  final _notesStreamController =
      StreamController<List<DatabaseNote>>.broadcast();

  Stream<List<DatabaseNote>> get allNotes => _notesStreamController.stream;

  Future<void> ensureDbIsOpen() async {
    try {
      await open();
    } on DatabaseAlreadyOpenException {
      //empty;
    }
  }

  Future<DatabaseUser> getOrCreateUser(
      {required String email, String? name}) async {
    await ensureDbIsOpen();
    try {
      final user = await getUser(email: email);
      return user;
    } on CouldNotFindUSer {
      final newUser = await createUser(email: email, name: (name ?? ''));
      return newUser;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _cacheNotes() async {
    final allNotes = await getAllNotes();
    _notes = allNotes.toList();
    _notesStreamController.add(_notes);
  }

  Database _getDatabaseOrThrow() {
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOPen();
    } else {
      return db;
    }
  }

  Future<void> open() async {
    if (_db != null) {
      throw DatabaseAlreadyOpenException();
    }
    try {
      final docsPath = await getApplicationDocumentsDirectory();
      final dbPath = join(docsPath.path, dbName);
      final db = await openDatabase(dbPath);
      _db = db;

      await db.execute(createUserTable);
      await db.execute(createNoteTable);

      await _cacheNotes();
    } on MissingPlatformDirectoryException {
      throw UnableToGetDocumentsDirectory();
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOPen();
    } else {
      await db.close();
      _db = null;
    }
  }

  Future<void> deleteUser({required String email}) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final deletedCount = await db.delete(
      userTable,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (deletedCount != 1) {
      throw CouldNotDeleteUserException();
    }
  }

  Future<DatabaseUser> createUser(
      {required String email, required String name}) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final results = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (results.isNotEmpty) {
      throw UserAlreadyExistsException();
    }
    final userId = await db.insert(
      userTable,
      {emailColumn: email.toLowerCase(), nameColumn: name},
    );

    return DatabaseUser(id: userId, email: email);
  }

  Future<DatabaseUser> getUser({required String email}) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final results = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );
    if (results.isEmpty) {
      throw CouldNotFindUSer();
    } else {
      return DatabaseUser.fromRow(results.first);
    }
  }

  Future<DatabaseUser> updateUser({
    required DatabaseUser user,
    required String email,
    required String name,
  }) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    await getUser(email: user.email);

    final updateCount = await db.update(userTable, {
      emailColumn: email,
      nameColumn: name,
    });

    if (updateCount == 0) {
      throw UserUpdateFailedException();
    } else {
      return user;
    }
  }

  Future<DatabaseNote> createNote({required DatabaseUser owner}) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    final dbUser = await getUser(email: owner.email);

    if (dbUser != owner) {
      throw CouldNotFindUSer();
    }

    const title = 'title';
    const body = 'body';
    final noteId = await db.insert(noteTable, {
      userIdColumn: owner.id,
      titleColumn: title,
      bodyColumn: body,
      isSyncedWithCloudColumn: 1,
    });

    final note = DatabaseNote(
        id: noteId,
        userId: owner.id,
        title: title,
        body: body,
        isSyncedWithCloud: true);

    _notes.add(note);
    _notesStreamController.add(_notes);

    return note;
  }

  Future<void> deleteNote({required int id}) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final deletedCount = await db.delete(
      noteTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deletedCount == 0) {
      throw CouldNotDeleteNote();
    } else {
      // Remove the note from our local list of notes.
      _notes.removeWhere((element) => element.id == id);
      _notesStreamController.add(_notes);
    }
  }

  Future<int> deleteAllNotes() async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final deleteCount = await db.delete(noteTable);
    _notes = [];
    _notesStreamController.add(_notes);
    return deleteCount;
  }

  Future<DatabaseNote> getNote({required int id}) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final notes = await db.query(
      noteTable,
      limit: 1,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (notes.isEmpty) {
      throw CoulNotFindNote();
    } else {
      final note = DatabaseNote.fromRow(notes.first);
      _notes.removeWhere((element) => element.id == id);
      _notes.add(note);
      _notesStreamController.add(_notes);
      return note;
    }
  }

  Future<Iterable<DatabaseNote>> getAllNotes() async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final notes = await db.query(noteTable);
    return notes.map((noteRow) => DatabaseNote.fromRow(notes.first));
  }

  Future<DatabaseNote> updateNotes({
    required DatabaseNote note,
    String? title,
    required String body,
  }) async {
    await ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    await getNote(id: note.id);

    final updateCount = await db.update(noteTable, {
      titleColumn: title,
      bodyColumn: body,
      isSyncedWithCloudColumn: 0,
    });

    if (updateCount == 0) {
      throw CouldNotUpdateNote();
    } else {
      final updatedNote = await getNote(id: note.id);
      _notes.removeWhere((element) => element.id == updatedNote.id);
      _notes.add(updatedNote);
      _notesStreamController.add(_notes);

      return updatedNote;
    }
  }
}

@immutable
class DatabaseUser {
  final int id;
  final String email;

  const DatabaseUser({required this.id, required this.email});

  DatabaseUser.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        email = map[emailColumn] as String;

  @override
  String toString() {
    return 'Person, ID = $id, email = $email';
  }

  @override
  bool operator ==(covariant DatabaseUser other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DatabaseNote {
  final int id;
  final int userId;
  final String title;
  final String body;
  final bool isSyncedWithCloud;

  DatabaseNote({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.isSyncedWithCloud,
  });

  DatabaseNote.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        userId = map[userIdColumn] as int,
        title = map[titleColumn] as String,
        body = map[bodyColumn] as String,
        isSyncedWithCloud =
            (map[isSyncedWithCloudColumn] as int) == 1 ? true : false;

  @override
  String toString() {
    return 'Note, ID = $id, userId = $userId, isSyncedWithCloud = $isSyncedWithCloud';
  }

  @override
  bool operator ==(covariant DatabaseNote other) => id == other.id;

  @override
  int get hashCode => id.hashCode;
}

const dbName = 'notes.db';
const noteTable = 'notes';
const userTable = 'User';
const idColumn = 'id';
const emailColumn = 'email';
const userIdColumn = 'user_id';
const nameColumn = 'name';
const titleColumn = 'title';
const bodyColumn = 'body';
const isSyncedWithCloudColumn = 'is_synced_with_cloud';

const createUserTable = ''' CREATE TABLE IF NOT EXISTS "User" (
	"id"	INTEGER NOT NULL,
	"email"	TEXT NOT NULL UNIQUE,
  "name" TEXT NOT NULL,
	PRIMARY KEY("id" AUTOINCREMENT)
);
''';
const createNoteTable = '''CREATE TABLE IF NOT EXISTS "notes" (
        "id"	INTEGER NOT NULL,
        "user_id"	INTEGER NOT NULL,
        "title"	TEXT DEFAULT '[TITLE]',
        "body" TEXT DEFAULT '[BODY]',
        "is_synced_with_cloud"	INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY("user_id") REFERENCES "User"("id"),
        PRIMARY KEY("id" AUTOINCREMENT)
);
''';

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LearnedSignatureDb {
  static const String databaseName = 'crowd_learned_signatures.db';
  static const int databaseVersion = 1;

  static const String learnedSignaturesTable = 'learned_signatures';
  static const String candidateEventsTable = 'candidate_events';
  static const String syncStateTable = 'sync_state';

  Database? _database;
  bool _openAttempted = false;

  Future<Database?> get database async {
    if (_database != null) {
      return _database;
    }
    if (_openAttempted) {
      return null;
    }
    _openAttempted = true;
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final path =
          '${supportDirectory.path}${Platform.pathSeparator}$databaseName';
      _database = await openDatabase(
        path,
        version: databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _runMigrations(db, oldVersion, newVersion);
        },
      );
      return _database;
    } catch (_) {
      _database = null;
      return null;
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
    _database = null;
    _openAttempted = false;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $learnedSignaturesTable (
        sig_hash TEXT PRIMARY KEY,
        host_pattern TEXT NOT NULL,
        path_pattern TEXT NOT NULL,
        resource_type TEXT NOT NULL,
        source_host TEXT NOT NULL,
        marker_keys TEXT NOT NULL,
        require_ad_signal INTEGER NOT NULL DEFAULT 1,
        state TEXT NOT NULL,
        source TEXT NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        confidence REAL NOT NULL DEFAULT 0,
        seen_count INTEGER NOT NULL DEFAULT 0,
        false_positive_count INTEGER NOT NULL DEFAULT 0,
        first_seen_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        expire_at INTEGER,
        updated_at INTEGER NOT NULL,
        last_reason TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $candidateEventsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sig_hash TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        next_retry_at INTEGER,
        FOREIGN KEY(sig_hash) REFERENCES $learnedSignaturesTable(sig_hash)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncStateTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_candidate_events_status_retry
      ON $candidateEventsTable(status, next_retry_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_learned_signatures_state_updated
      ON $learnedSignaturesTable(state, updated_at)
    ''');
  }

  Future<void> _runMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await _createTables(db);
    }
    // Placeholder for future migrations.
    if (newVersion > 1) {
      // keep schema forward-compatible by not failing unknown future versions
    }
  }
}

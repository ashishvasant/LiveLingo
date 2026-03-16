import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class LocalDatabase {
  Database? _database;

  Future<void> open() async {
    if (_database != null) {
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, 'language_assist.db');
    _database = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (Database db, int version) async {
        await _createTables(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE user_settings ADD COLUMN interaction_mode TEXT NOT NULL DEFAULT 'guide'",
          );
          await db.execute(
            'ALTER TABLE user_settings ADD COLUMN mute_replies INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE user_settings ADD COLUMN audio_input_enabled INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            "ALTER TABLE user_settings ADD COLUMN default_autonomous_goal TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE user_settings ADD COLUMN profile_name TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE user_settings ADD COLUMN profile_email TEXT NOT NULL DEFAULT ''",
          );
          await db.execute('''
            CREATE TABLE session_summaries(
              id TEXT PRIMARY KEY,
              created_at TEXT NOT NULL,
              interaction_mode TEXT NOT NULL,
              goal TEXT NOT NULL,
              context_summary TEXT NOT NULL,
              target_language TEXT NOT NULL,
              outcome TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE user_settings ADD COLUMN live_voice_name TEXT NOT NULL DEFAULT 'Kore'",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE user_settings ADD COLUMN autonomous_show_all_messages INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE user_settings(
        id INTEGER PRIMARY KEY,
        backend_url TEXT NOT NULL,
        auth_token TEXT NOT NULL,
        user_language TEXT NOT NULL,
        target_language TEXT NOT NULL,
        live_voice_name TEXT NOT NULL,
        target_language_auto_infer INTEGER NOT NULL,
        allow_location_fallback INTEGER NOT NULL,
        include_camera_context INTEGER NOT NULL,
        save_local_history INTEGER NOT NULL,
        playback_speed REAL NOT NULL,
        transliteration_style TEXT NOT NULL,
        interaction_mode TEXT NOT NULL,
        mute_replies INTEGER NOT NULL,
        audio_input_enabled INTEGER NOT NULL,
        autonomous_show_all_messages INTEGER NOT NULL,
        default_autonomous_goal TEXT NOT NULL,
        profile_name TEXT NOT NULL,
        profile_email TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE history_entries(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        source TEXT NOT NULL,
        user_language TEXT NOT NULL,
        target_language TEXT NOT NULL,
        suggestion_id TEXT NOT NULL,
        display_text TEXT NOT NULL,
        target_text TEXT NOT NULL,
        transliteration TEXT NOT NULL,
        pronunciation_hint TEXT NOT NULL,
        scenario TEXT NOT NULL,
        location_guess TEXT NOT NULL,
        audio_played INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE scenario_snapshots(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        location_guess TEXT NOT NULL,
        location_source TEXT NOT NULL,
        local_language TEXT NOT NULL,
        scenario TEXT NOT NULL,
        subscenario TEXT NOT NULL,
        active_speaker_role TEXT NOT NULL,
        confidence REAL NOT NULL,
        state_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE suggestion_cache(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        state_json TEXT NOT NULL,
        items_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE intent_assist_cache(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        result_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE diagnostics(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE session_summaries(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        interaction_mode TEXT NOT NULL,
        goal TEXT NOT NULL,
        context_summary TEXT NOT NULL,
        target_language TEXT NOT NULL,
        outcome TEXT NOT NULL
      )
    ''');
  }

  Database get database {
    final Database? db = _database;
    if (db == null) {
      throw StateError('Database not initialized');
    }
    return db;
  }

  Future<AppSettings> loadSettings() async {
    final List<Map<String, Object?>> rows = await database.query(
      'user_settings',
      limit: 1,
    );
    if (rows.isEmpty) {
      final AppSettings defaults = AppSettings.defaults();
      await saveSettings(defaults);
      return defaults;
    }
    return AppSettings.fromDbMap(rows.first);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await database.insert(
      'user_settings',
      settings.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HistoryEntry>> listHistory({int limit = 100}) async {
    final List<Map<String, Object?>> rows = await database.query(
      'history_entries',
      limit: limit,
      orderBy: 'created_at DESC',
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> insertHistory(HistoryEntry entry) async {
    await database.insert(
      'history_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markHistoryAudioPlayed(String suggestionId) async {
    await database.update(
      'history_entries',
      <String, Object?>{'audio_played': 1},
      where: 'suggestion_id = ?',
      whereArgs: <Object?>[suggestionId],
    );
  }

  Future<void> saveScenarioSnapshot(String id, ScenarioState state) async {
    await database.insert('scenario_snapshots', <String, Object?>{
      'id': id,
      'created_at': state.updatedAt.toUtc().toIso8601String(),
      'location_guess': state.locationGuess,
      'location_source': state.locationSource,
      'local_language': state.localLanguage,
      'scenario': state.scenario,
      'subscenario': state.subscenario,
      'active_speaker_role': state.activeSpeakerRole,
      'confidence': state.confidence,
      'state_json': jsonEncode(state.toMap()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> cacheSuggestions(
    String id,
    ScenarioState? state,
    List<PhraseSuggestion> items,
  ) async {
    await database.insert('suggestion_cache', <String, Object?>{
      'id': id,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'state_json': jsonEncode(state?.toMap() ?? <String, dynamic>{}),
      'items_json': jsonEncode(
        items.map((PhraseSuggestion item) => item.toMap()).toList(),
      ),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveIntentAssist(String id, IntentAssist assist) async {
    await database.insert('intent_assist_cache', <String, Object?>{
      'id': id,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'result_json': jsonEncode(<String, dynamic>{
        'confidence': assist.confidence,
        'input_summary': assist.inputSummary,
        'result': <String, dynamic>{
          'display_text': assist.displayText,
          'target_text': assist.targetText,
          'transliteration': assist.transliteration,
          'pronunciation_hint': assist.pronunciationHint,
          'audio_available': assist.audioAvailable,
        },
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertDiagnostic(DiagnosticEvent event) async {
    await database.insert(
      'diagnostics',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDiagnostics() async {
    await database.delete('diagnostics');
  }

  Future<List<DiagnosticEvent>> listDiagnostics({int limit = 100}) async {
    final List<Map<String, Object?>> rows = await database.query(
      'diagnostics',
      limit: limit,
      orderBy: 'created_at DESC',
    );
    return rows.map(DiagnosticEvent.fromMap).toList();
  }

  Future<void> insertSessionSummary(SessionSummary summary) async {
    await database.insert(
      'session_summaries',
      summary.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SessionSummary>> listSessionSummaries({int limit = 30}) async {
    final List<Map<String, Object?>> rows = await database.query(
      'session_summaries',
      limit: limit,
      orderBy: 'created_at DESC',
    );
    return rows.map(SessionSummary.fromMap).toList();
  }
}

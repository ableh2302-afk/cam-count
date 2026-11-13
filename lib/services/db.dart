import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Db {
  static Database? _d;

  static Future<Database> get db async => _d ??= await openDatabase(
        join(await getDatabasesPath(), 'camcount.db'),
        version: 1,
        onCreate: (d, v) async {
          await d.execute('CREATE TABLE sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, tanggal_jam TEXT, posisi_rak TEXT, mode_hitung TEXT, total_semua_pipa INTEGER, path_foto_asli TEXT, path_foto_bertanda TEXT, catatan TEXT)');
          await d.execute('CREATE TABLE session_details(id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER, ukuran_pipa TEXT, jumlah_batang INTEGER, detail_rumus TEXT)');
          await d.execute('CREATE TABLE racks(id INTEGER PRIMARY KEY AUTOINCREMENT, jenis TEXT, nilai TEXT)');
        },
      );

  static Future<int> insertSession(Map<String, Object?> s, List<Map<String, Object?>> details) async {
    final d = await db;
    return d.transaction((t) async {
      final id = await t.insert('sessions', s);
      for (final r in details) {
        await t.insert('session_details', {...r, 'session_id': id});
      }
      return id;
    });
  }

  static Future<List<Map<String, Object?>>> sessions() async =>
      (await db).query('sessions', orderBy: 'id DESC');

  static Future<List<Map<String, Object?>>> details(int sessionId) async =>
      (await db).query('session_details', where: 'session_id=?', whereArgs: [sessionId], orderBy: 'id');

  static Future<void> deleteSession(int id) async {
    final d = await db;
    await d.delete('session_details', where: 'session_id=?', whereArgs: [id]);
    await d.delete('sessions', where: 'id=?', whereArgs: [id]);
  }

  /// Baris datar untuk export: satu baris per detail.
  static Future<List<Map<String, Object?>>> flatRows({int? sessionId}) async {
    final d = await db;
    return d.rawQuery(
      'SELECT s.tanggal_jam, s.posisi_rak, s.mode_hitung, x.ukuran_pipa, x.detail_rumus, x.jumlah_batang '
      'FROM sessions s JOIN session_details x ON x.session_id = s.id '
      '${sessionId != null ? "WHERE s.id = $sessionId " : ""}ORDER BY s.id DESC, x.id',
    );
  }

  static Future<List<Map<String, Object?>>> racks(String jenis) async =>
      (await db).query('racks', where: 'jenis=?', whereArgs: [jenis], orderBy: 'nilai');

  static Future<void> addRack(String jenis, String nilai) async =>
      (await db).insert('racks', {'jenis': jenis, 'nilai': nilai});

  static Future<void> updateRack(int id, String nilai) async =>
      (await db).update('racks', {'nilai': nilai}, where: 'id=?', whereArgs: [id]);

  static Future<void> deleteRack(int id) async =>
      (await db).delete('racks', where: 'id=?', whereArgs: [id]);
}

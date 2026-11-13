import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';

class Exporter {
  /// Export CSV (UTF-8 BOM agar ½" terbaca benar di Excel). sessionId null = semua sesi.
  static Future<String> exportCsv({int? sessionId}) async {
    final rows = await Db.flatRows(sessionId: sessionId);
    final data = <List<dynamic>>[
      ['Tanggal & Jam', 'Posisi Rak', 'Ukuran Pipa', 'Mode Hitung', 'Keterangan Coretan', 'Jumlah Batang'],
      for (final r in rows) [r['tanggal_jam'], r['posisi_rak'], r['ukuran_pipa'], r['mode_hitung'], r['detail_rumus'] ?? '', r['jumlah_batang']],
    ];
    final csv = '\uFEFF${const ListToCsvConverter().convert(data)}';
    final name = 'camcount_${DateTime.now().millisecondsSinceEpoch}.csv';
    final tmp = File('${(await getTemporaryDirectory()).path}/$name')..writeAsStringSync(csv);
    // Salinan ke folder Download (best-effort; bisa ditolak pada Android baru)
    try {
      final d = Directory('/storage/emulated/0/Download');
      if (d.existsSync()) File('${d.path}/$name').writeAsStringSync(csv);
    } catch (_) {}
    await Share.shareXFiles([XFile(tmp.path, mimeType: 'text/csv')], subject: 'Cam Count Export');
    return name;
  }
}

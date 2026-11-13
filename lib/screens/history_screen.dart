import 'dart:io';
import 'package:flutter/material.dart';
import '../services/db.dart';
import '../services/exporter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<List<Map<String, Object?>>> _f = Db.sessions();
  void _reload() => setState(() => _f = Db.sessions());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat'), actions: [
        IconButton(
          tooltip: 'Export semua ke CSV',
          icon: const Icon(Icons.table_view),
          onPressed: () async {
            try {
              await Exporter.exportCsv();
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export gagal: $e')));
            }
          },
        ),
      ]),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _f,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final l = s.data!;
          if (l.isEmpty) return const Center(child: Text('Belum ada sesi tersimpan.'));
          return ListView.separated(
            itemCount: l.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = l[i];
              final path = r['path_foto_bertanda'] as String?;
              return ListTile(
                leading: path != null && File(path).existsSync()
                    ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(path), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 120))
                    : const Icon(Icons.image_not_supported),
                title: Text('${r['posisi_rak']}  •  ${r['total_semua_pipa']} batang'),
                subtitle: Text('${r['tanggal_jam']}  •  ${r['mode_hitung']}'),
                onTap: () async {
                  await Navigator.push(c, MaterialPageRoute(builder: (_) => SessionDetailScreen(session: r)));
                  _reload();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  final Map<String, Object?> session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final id = session['id'] as int;
    final path = session['path_foto_bertanda'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text('${session['posisi_rak']}'), actions: [
        IconButton(icon: const Icon(Icons.share), tooltip: 'Export CSV sesi ini', onPressed: () => Exporter.exportCsv(sessionId: id)),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Hapus sesi ini?'),
                actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus'))],
              ),
            );
            if (ok == true) {
              await Db.deleteSession(id);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ]),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: Db.details(id),
        builder: (c, s) => ListView(children: [
          if (path != null && File(path).existsSync()) InteractiveViewer(child: Image.file(File(path))),
          ListTile(title: Text('${session['tanggal_jam']}  •  ${session['mode_hitung']}'), subtitle: Text('Total: ${session['total_semua_pipa']} batang')),
          if ((session['catatan'] as String?)?.isNotEmpty ?? false) ListTile(title: const Text('Catatan'), subtitle: Text('${session['catatan']}')),
          for (final d in s.data ?? [])
            ListTile(dense: true, title: Text('${d['ukuran_pipa']}  —  ${d['jumlah_batang']} batang'), subtitle: d['detail_rumus'] != null ? Text('${d['detail_rumus']}') : null),
        ]),
      ),
    );
  }
}

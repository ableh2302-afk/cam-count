import 'package:flutter/material.dart';
import '../services/db.dart';

class RackMasterScreen extends StatelessWidget {
  const RackMasterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Master Data Posisi Rak'),
          bottom: const TabBar(tabs: [Tab(text: 'Gudang'), Tab(text: 'Nomor Rak'), Tab(text: 'Level')]),
        ),
        body: const TabBarView(children: [_RackList('gudang'), _RackList('rak'), _RackList('level')]),
      ),
    );
  }
}

class _RackList extends StatefulWidget {
  final String jenis;
  const _RackList(this.jenis);
  @override
  State<_RackList> createState() => _RackListState();
}

class _RackListState extends State<_RackList> {
  Future<List<Map<String, Object?>>> _f = Future.value([]);
  @override
  void initState() {
    super.initState();
    _f = Db.racks(widget.jenis);
  }

  void _reload() => setState(() => _f = Db.racks(widget.jenis));

  Future<void> _edit({int? id, String initial = ''}) async {
    final ctl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(id == null ? 'Tambah' : 'Edit'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Simpan'))],
      ),
    );
    if (v == null || v.isEmpty) return;
    if (id == null) {
      await Db.addRack(widget.jenis, v);
    } else {
      await Db.updateRack(id, v);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _f,
        builder: (c, s) {
          final l = s.data ?? [];
          if (l.isEmpty) return const Center(child: Text('Belum ada data. Tekan + untuk menambah.'));
          return ListView(children: [
            for (final r in l)
              ListTile(
                title: Text('${r['nilai']}'),
                onTap: () => _edit(id: r['id'] as int, initial: '${r['nilai']}'),
                trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                  await Db.deleteRack(r['id'] as int);
                  _reload();
                }),
              ),
          ]);
        },
      ),
    );
  }
}

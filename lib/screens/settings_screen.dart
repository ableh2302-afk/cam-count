import 'package:flutter/material.dart';
import '../models.dart';
import '../services/license.dart';
import '../settings.dart';
import 'admin_screen.dart';
import 'rack_master_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = appSettings;
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Future<LicenseStatus> _lic = LicenseService.check();

  void _upd(VoidCallback f) {
    setState(f);
    s.save();
  }

  Future<void> _titleTap() async {
    final now = DateTime.now();
    _taps = now.difference(_last).inSeconds > 3 ? 1 : _taps + 1;
    _last = now;
    if (_taps < 7) return;
    _taps = 0;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('PIN Master Admin'),
        content: TextField(controller: ctl, obscureText: true, keyboardType: TextInputType.number, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text == kAdminPin), child: const Text('Masuk'))],
      ),
    );
    if (ok == true && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> f, {int? div, String suffix = ''}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 16, top: 8), child: Text('$label: ${v.toStringAsFixed(1)}$suffix')),
        Slider(value: v.clamp(min, max), min: min, max: max, divisions: div, onChanged: (x) => _upd(() => f(x))),
      ]);

  Widget _head(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)));

  Future<void> _pickColor(int i) async {
    var c = s.colorOf(i);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Widget ch(String n, int v, ValueChanged<int> f) => Row(children: [
              SizedBox(width: 20, child: Text(n)),
              Expanded(child: Slider(value: v.toDouble(), min: 0, max: 255, onChanged: (x) => set(() => f(x.round())))),
            ]);
        return AlertDialog(
          title: Text('Warna ${kPipeSizes[i]}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 40, color: c),
            ch('R', (c.r * 255).round(), (v) => c = Color.fromARGB(255, v, (c.g * 255).round(), (c.b * 255).round())),
            ch('G', (c.g * 255).round(), (v) => c = Color.fromARGB(255, (c.r * 255).round(), v, (c.b * 255).round())),
            ch('B', (c.b * 255).round(), (v) => c = Color.fromARGB(255, (c.r * 255).round(), (c.g * 255).round(), v)),
          ]),
          actions: [
            TextButton(onPressed: () { _upd(() => s.colors[i] = kDefaultColors[i]); Navigator.pop(ctx); }, child: const Text('Reset')),
            FilledButton(onPressed: () { _upd(() => s.colors[i] = c.toARGB32()); Navigator.pop(ctx); }, child: const Text('Pakai')),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: GestureDetector(onTap: _titleTap, behavior: HitTestBehavior.opaque, child: const Text('Cam Count • Pengaturan'))),
      body: ListView(children: [
        FutureBuilder<LicenseStatus>(
          future: _lic,
          builder: (c, f) {
            final l = f.data;
            if (l == null) return const SizedBox();
            final txt = l.type == 'P' ? 'Permanen' : (l.expiry != null ? 'Berlaku s/d ${l.expiry!.toString().substring(0, 10)}' : l.message);
            return ListTile(leading: const Icon(Icons.verified_user), title: const Text('Lisensi'), subtitle: Text(txt));
          },
        ),
        _head('Penanda'),
        _slider('Ketebalan garis lingkaran', s.ringWidth, 1, 6, (v) => s.ringWidth = v, div: 50, suffix: ' px'),
        _slider('Ukuran teks nomor', s.textSize, 8, 32, (v) => s.textSize = v, div: 24),
        SwitchListTile(title: const Text('Tampilkan nomor urut'), value: s.showNumbers, onChanged: (v) => _upd(() => s.showNumbers = v)),
        _slider('Ketebalan garis coretan (Mode 3)', s.strokeWidth, 1, 12, (v) => s.strokeWidth = v, div: 22, suffix: ' px'),
        ExpansionTile(title: const Text('Warna per ukuran pipa'), children: [
          for (var i = 0; i < kPipeSizes.length; i++)
            ListTile(dense: true, leading: CircleAvatar(backgroundColor: s.colorOf(i), radius: 12), title: Text(kPipeSizes[i]), onTap: () => _pickColor(i)),
        ]),
        _head('Kalibrasi & Sensitivitas Deteksi'),
        _slider('Toleransi diameter Tap-to-Match', s.tolerance, 2, 15, (v) => s.tolerance = v, div: 26, suffix: ' %'),
        _slider('param1 (Canny atas)', s.param1, 30, 300, (v) => s.param1 = v, div: 54),
        _slider('param2 (ambang akumulator; kecil = lebih sensitif)', s.param2, 10, 80, (v) => s.param2 = v, div: 70),
        _slider('Jarak minimum antar pusat (x radius)', s.minDistFactor, 0.8, 3.0, (v) => s.minDistFactor = v, div: 22),
        ListTile(
          title: const Text('Ukuran patokan default (pipa terbesar di foto)'),
          trailing: DropdownButton<int>(value: s.refSizeIdx, items: [for (var i = 0; i < kPipeSizes.length; i++) DropdownMenuItem(value: i, child: Text(kPipeSizes[i]))], onChanged: (v) => _upd(() => s.refSizeIdx = v!)),
        ),
        _head('Master Data Rak'),
        ListTile(leading: const Icon(Icons.warehouse), title: const Text('Kelola Gudang / Rak / Level'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RackMasterScreen()))),
        _head('Kamera & Layar Kerja'),
        SwitchListTile(title: const Text('Auto-flash/torch saat kamera dibuka'), value: s.autoTorch, onChanged: (v) => _upd(() => s.autoTorch = v)),
        SwitchListTile(title: const Text('Getar & bip saat tambah/hapus penanda'), value: s.haptic, onChanged: (v) => _upd(() => s.haptic = v)),
        SwitchListTile(title: const Text('Watermark Rak & Tanggal pada foto tersimpan'), value: s.watermark, onChanged: (v) => _upd(() => s.watermark = v)),
        const SizedBox(height: 32),
      ]),
    );
  }
}

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/detector.dart';
import 'camera_screen.dart';
import 'count_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _open(BuildContext context, Uint8List raw) async {
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final jpg = await compute(normalizeImage, raw);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => CountScreen(bytes: jpg)));
    } catch (e) {
      nav.pop();
      msg.showSnackBar(SnackBar(content: Text('Gagal memuat foto: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget big(IconData i, String t, VoidCallback f) => Card(
          child: InkWell(
            onTap: f,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(i, size: 36),
                const SizedBox(width: 16),
                Text(t, style: Theme.of(context).textTheme.titleMedium),
              ]),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Cam Count')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        big(Icons.photo_camera, 'Foto & Hitung (Kamera)', () async {
          final raw = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const CameraScreen()));
          if (raw != null && context.mounted) _open(context, raw);
        }),
        big(Icons.photo_library, 'Pilih dari Galeri', () async {
          final f = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (f != null && context.mounted) _open(context, await f.readAsBytes());
        }),
        big(Icons.history, 'Riwayat & Export CSV', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
        big(Icons.settings, 'Pengaturan', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
    );
  }
}

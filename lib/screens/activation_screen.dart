import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/license.dart';
import 'admin_screen.dart';

class ActivationScreen extends StatefulWidget {
  final String message;
  final VoidCallback onActivated;
  const ActivationScreen({super.key, required this.message, required this.onActivated});
  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _ctl = TextEditingController();
  String _dev = '........';
  String? _err;
  bool _busy = false;
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    LicenseService.deviceCode().then((v) => mounted ? setState(() => _dev = v) : null);
    if (widget.message.isNotEmpty) _err = widget.message;
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final e = await LicenseService.activate(_ctl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = e;
    });
    if (e == null) widget.onActivated();
  }

  Future<void> _lockTap() async {
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text == kAdminPin), child: const Text('Masuk')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: _lockTap,
                child: Icon(Icons.lock, size: 72, color: t.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text('Cam Count', style: t.textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text('Aplikasi belum diaktivasi di perangkat ini'),
              const SizedBox(height: 24),
              const Text('Kode Permintaan Perangkat'),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SelectableText(_dev, style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Salin Kode',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _dev));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kode disalin')));
                  },
                ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _ctl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Kode Aktivasi', hintText: 'M-XXXX-XXXX-XXXX', border: OutlineInputBorder()),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: t.colorScheme.error))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _go, child: const Text('Aktivasi'))),
              const SizedBox(height: 12),
              const Text('Kirim kode permintaan di atas ke admin untuk mendapat kode aktivasi.', textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}

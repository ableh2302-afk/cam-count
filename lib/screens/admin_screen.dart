import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/license.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _dev = TextEditingController();
  String _type = 'P';
  String? _code;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Key Generator')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _dev,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Kode Permintaan Perangkat (8 karakter)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          for (final e in LicenseService.types.entries)
            ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final d = _dev.text.trim().toUpperCase();
            if (d.length != 8) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kode perangkat harus 8 karakter')));
              return;
            }
            setState(() => _code = LicenseService.generate(d, _type));
          },
          child: const Text('Generate Kode Aktivasi'),
        ),
        if (_code != null) ...[
          const SizedBox(height: 24),
          Center(child: SelectableText(_code!, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 2))),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Salin'),
            onPressed: () => Clipboard.setData(ClipboardData(text: _code!)),
          ),
          const Text('Masa berlaku dihitung sejak kode diaktivasi di HP staf.', textAlign: TextAlign.center),
        ],
      ]),
    );
  }
}

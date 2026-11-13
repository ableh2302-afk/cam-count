import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../services/db.dart';
import '../services/detector.dart';
import '../settings.dart';

/// Menggambar lingkaran bernomor + lingkaran patokan tipis + coretan.
class MarkerPainter extends CustomPainter {
  final List<Marker> markers;
  final List<Stroke> strokes;
  final Stroke? cur;
  final Offset? refCenter;
  final double? refRadius;
  final AppSettings s;
  final double Function() unit;

  MarkerPainter({
    required this.markers,
    required this.strokes,
    required this.cur,
    this.refCenter,
    this.refRadius,
    required this.s,
    required this.unit,
    Listenable? repaint,
  }) : super(repaint: repaint);

  static void text(Canvas c, String t, Offset center, double size, Color col) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(color: col, fontSize: size, fontWeight: FontWeight.bold, shadows: [
          Shadow(color: Colors.black, blurRadius: size * 0.25, offset: Offset(size * 0.05, size * 0.05)),
        ]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = unit();
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final col = s.colorOf(m.sizeIdx);
      canvas.drawCircle(
        Offset(m.x, m.y),
        m.r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.ringWidth * u
          ..color = col,
      );
      if (s.showNumbers) text(canvas, '${i + 1}', Offset(m.x, m.y), s.textSize * u, col);
    }

    // Gambar lingkaran patokan tipis (jika sedang diatur di mode Tap-Match)
    if (refCenter != null && refRadius != null && refRadius! > 0) {
      canvas.drawCircle(
        refCenter!,
        refRadius!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * u
          ..color = Colors.yellowAccent,
      );
      // Titik bidik tengah tipis
      canvas.drawCircle(refCenter!, 3 * u, Paint()..color = Colors.yellowAccent);
    }

    final all = [...strokes, if (cur != null) cur!];
    for (var i = 0; i < all.length; i++) {
      final st = all[i];
      if (st.pts.isEmpty) continue;
      final path = Path()..moveTo(st.pts.first.dx, st.pts.first.dy);
      for (final q in st.pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s.strokeWidth * u
          ..color = Colors.redAccent.withOpacity(0.85),
      );
      final end = st.pts.last;
      canvas.drawCircle(end, 13 * u, Paint()..color = Colors.redAccent.shade700);
      text(canvas, '${i + 1}', end, 14 * u, Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class CountScreen extends StatefulWidget {
  final Uint8List bytes;
  const CountScreen({super.key, required this.bytes});
  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> {
  final s = appSettings;
  ui.Image? _img;
  int mode = 1, active = 0; // Default langsung ke Mode 1 (Tap-Match Patokan)
  late int refIdx = s.refSizeIdx;
  final markers = <Marker>[];
  final strokes = <Stroke>[];
  final manual = <ManualEntry>[];
  Stroke? cur;
  bool busy = false, drawing = true, _fitted = false, _scanned = false;

  // Variabel lingkaran patokan tipis yang bisa diubah ukurannya
  Offset? refCenter;
  double refRadius = 35.0;

  final tc = TransformationController();
  final perCtl = TextEditingController(text: '8');
  final noteCtl = TextEditingController();
  String gudang = '', rak = '', level = '';

  @override
  void initState() {
    super.initState();
    ui.instantiateImageCodec(widget.bytes).then((c) => c.getNextFrame()).then((f) {
      if (mounted) {
        setState(() {
          _img = f.image;
          refRadius = math.min(_img!.width, _img!.height) * 0.04;
        });
      }
    });
  }

  String get rackLabel => [if (gudang.isNotEmpty) gudang, if (rak.isNotEmpty) 'Rak $rak', if (level.isNotEmpty) 'Tk $level'].join(' / ');

  List<int> _totals() {
    final t = List<int>.filled(kPipeSizes.length, 0);
    for (final m in markers) {
      t[m.sizeIdx]++;
    }
    for (final e in manual) {
      t[e.sizeIdx] += e.total;
    }
    return t;
  }

  void _feedback() {
    if (!s.haptic) return;
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---------- MODE 0: AUTO-ALL ----------
  Future<void> _runAuto() async {
    setState(() => busy = true);
    try {
      final cs = await compute(autoDetect, {'bytes': widget.bytes, 'p1': s.param1, 'p2': s.param2, 'mdf': s.minDistFactor});
      markers.removeWhere((m) => m.auto);
      if (cs.isNotEmpty) {
        final maxR = cs.map((e) => e[2]).reduce(math.max);
        final mmPerPx = kPipeOdMm[refIdx] / (2 * maxR);
        final add = <Marker>[];
        for (final c in cs) {
          final od = 2 * c[2] * mmPerPx;
          var bi = 0;
          var bd = 1e9;
          for (var i = 0; i < kPipeOdMm.length; i++) {
            final d = (math.log(od / kPipeOdMm[i])).abs();
            if (d < bd) {
              bd = d;
              bi = i;
            }
          }
          add.add(Marker(c[0], c[1], c[2], bi, true));
        }
        add.sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
        markers.addAll(add);
      }
      _snack('${cs.length} pipa terdeteksi');
    } catch (e) {
      _snack('Deteksi gagal: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  // ---------- MODE 1: SCAN BERDASARKAN LINGKARAN PATOKAN ----------
  Future<void> _scanByReference() async {
    if (refCenter == null) {
      _snack('Ketuk satu pipa di foto terlebih dahulu untuk meletakkan lingkaran patokan.');
      return;
    }
    setState(() => busy = true);
    try {
      final cs = await compute(detectByRadius, {
        'bytes': widget.bytes,
        'r': refRadius,
        'tol': s.tolerance / 100,
        'p1': s.param1,
        'p2': s.param2,
        'mdf': s.minDistFactor,
      });

      markers.removeWhere((m) => m.auto && m.sizeIdx == active);
      final add = cs.map((c) => Marker(c[0], c[1], c[2], active, true)).toList();

      // Pastikan pipa yang dilingkari patokan ikut terhitung jika belum masuk hasil deteksi
      final hasRef = add.any((m) => (Offset(m.x, m.y) - refCenter!).distance < refRadius * 0.7);
      if (!hasRef) {
        add.add(Marker(refCenter!.dx, refCenter!.dy, refRadius, active, true));
      }

      add.sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
      markers.addAll(add);
      _scanned = true;
      _snack('Ditemukan ${add.length} pipa ukuran ${kPipeSizes[active]}');
    } catch (e) {
      _snack('Gagal memindai: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  // ---------- Tap & koreksi ----------
  Future<void> _onTap(Offset pt) async {
    if (busy || mode == 2) return;

    // Jika di Mode 1 dan belum di-scan, ketukan akan meletakkan/memindahkan lingkaran patokan tipis
    if (mode == 1 && !_scanned) {
      setState(() {
        refCenter = pt;
      });
      _feedback();
      return;
    }

    // Setelah scan (atau di Mode 0), ketukan menambah/menghapus penanda hasil
    var hit = -1;
    var best = double.infinity;
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final d = (Offset(m.x, m.y) - pt).distance;
      if (d <= m.r && m.r < best) {
        best = m.r;
        hit = i;
      }
    }
    setState(() {
      if (hit >= 0) {
        markers.removeAt(hit);
      } else {
        final same = markers.where((m) => m.sizeIdx == active).toList();
        final r = same.isNotEmpty
            ? same.map((m) => m.r).reduce((a, b) => a + b) / same.length
            : refRadius;
        markers.add(Marker(pt.dx, pt.dy, r, active, false));
      }
    });
    _feedback();
  }

  // ---------- Rak ----------
  Future<void> _rackSheet() async {
    final g = TextEditingController(text: gudang), r = TextEditingController(text: rak), l = TextEditingController(text: level);
    final gs = await Db.racks('gudang'), rs = await Db.racks('rak'), ls = await Db.racks('level');
    if (!mounted) return;
    Widget field(String label, TextEditingController c, List<Map<String, Object?>> o) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: c, decoration: InputDecoration(labelText: label)),
          Wrap(spacing: 6, children: [for (final x in o) ActionChip(label: Text('${x['nilai']}'), onPressed: () => c.text = '${x['nilai']}')]),
        ]);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Posisi Rak', style: Theme.of(c).textTheme.titleMedium),
            field('Kode Gudang', g, gs),
            field('Nomor Rak', r, rs),
            field('Tingkat / Level', l, ls),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Simpan Posisi')),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
    setState(() {
      gudang = g.text.trim();
      rak = r.text.trim();
      level = l.text.trim();
    });
  }

  // ---------- Render & simpan ----------
  void _watermark(Canvas c, double w, double h, double u, DateTime now) {
    final t = _totals();
    final lines = <String>[
      'Rak: ${rackLabel.isEmpty ? "-" : rackLabel}',
      DateFormat('dd/MM/yyyy HH:mm').format(now),
      for (var i = 0; i < t.length; i++)
        if (t[i] > 0) '${kPipeSizes[i]} : ${t[i]} btg',
      'TOTAL: ${t.fold<int>(0, (a, b) => a + b)} btg',
    ];
    final tps = lines
        .map((l) => TextPainter(text: TextSpan(text: l, style: TextStyle(color: Colors.white, fontSize: 14 * u, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)..layout())
        .toList();
    final pad = 8 * u;
    final bw = tps.map((e) => e.width).reduce(math.max) + pad * 2;
    final bh = tps.fold<double>(0, (a, e) => a + e.height) + pad * 2;
    final top = h - bh - pad;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pad, top, bw, bh), Radius.circular(pad)), Paint()..color = Colors.black.withOpacity(0.65));
    var y = top + pad;
    for (final tp in tps) {
      tp.paint(c, Offset(pad * 2, y));
      y += tp.height;
    }
  }

  Future<Uint8List> _render(DateTime now) async {
    final w = _img!.width.toDouble(), h = _img!.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(_img!, Offset.zero, Paint());
    final u = math.max(w, h) / 800;
    MarkerPainter(markers: markers, strokes: strokes, cur: null, s: s, unit: () => u).paint(c, Size(w, h));
    if (s.watermark) _watermark(c, w, h, u, now);
    final out = await rec.endRecording().toImage(w.toInt(), h.toInt());
    return (await out.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  Future<void> _save() async {
    final totals = _totals();
    final total = totals.fold<int>(0, (a, b) => a + b);
    if (total == 0) return _snack('Belum ada hasil hitungan untuk disimpan.');
    if (rackLabel.isEmpty) await _rackSheet();
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(now);
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'camcount'))..createSync(recursive: true);
      final orig = File(p.join(dir.path, 'asli_$ts.jpg'))..writeAsBytesSync(widget.bytes);
      final ann = File(p.join(dir.path, 'bertanda_$ts.png'))..writeAsBytesSync(await _render(now));
      try {
        await Gal.putImage(ann.path);
      } catch (_) {}

      final details = <Map<String, Object?>>[];
      final autoCount = List<int>.filled(kPipeSizes.length, 0);
      for (final m in markers) {
        autoCount[m.sizeIdx]++;
      }
      for (var i = 0; i < autoCount.length; i++) {
        if (autoCount[i] > 0) details.add({'ukuran_pipa': kPipeSizes[i], 'jumlah_batang': autoCount[i], 'detail_rumus': null});
      }
      for (final e in manual) {
        details.add({'ukuran_pipa': kPipeSizes[e.sizeIdx], 'jumlah_batang': e.total, 'detail_rumus': e.formula});
      }
      await Db.insertSession({
        'tanggal_jam': DateFormat('yyyy-MM-dd HH:mm:ss').format(now),
        'posisi_rak': rackLabel,
        'mode_hitung': kModeNames[mode],
        'total_semua_pipa': total,
        'path_foto_asli': orig.path,
        'path_foto_bertanda': ann.path,
        'catatan': noteCtl.text.trim(),
      }, details);
      if (!mounted) return;
      _snack('Tersimpan: $total batang');
      Navigator.pop(context);
    } catch (e) {
      _snack('Gagal menyimpan: $e');
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- UI ----------
  Widget _canvas() {
    final img = _img!;
    final w = img.width.toDouble(), h = img.height.toDouble();
    return LayoutBuilder(builder: (ctx, box) {
      if (!_fitted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final k = math.min(box.maxWidth / w, box.maxHeight / h);
          tc.value = Matrix4(k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, (box.maxWidth - w * k) / 2, (box.maxHeight - h * k) / 2, 0, 1);
          _fitted = true;
        });
      }
      final lock = mode == 2 && drawing;
      return ClipRect(
        child: InteractiveViewer(
          transformationController: tc,
          constrained: false,
          minScale: 0.05,
          maxScale: 25,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          panEnabled: !lock,
          scaleEnabled: !lock,
          child: SizedBox(
            width: w,
            height: h,
            child: GestureDetector(
              onTapUp: (d) => _onTap(d.localPosition),
              onPanStart: lock ? (d) => setState(() => cur = Stroke([d.localPosition])) : null,
              onPanUpdate: lock ? (d) => setState(() => cur?.pts.add(d.localPosition)) : null,
              onPanEnd: lock
                  ? (_) => setState(() {
                        if (cur != null && cur!.pts.length > 1) {
                          strokes.add(cur!);
                          _feedback();
                        }
                        cur = null;
                      })
                  : null,
              child: Stack(children: [
                RawImage(image: img, width: w, height: h, fit: BoxFit.fill),
                Positioned.fill(
                  child: CustomPaint(
                    painter: MarkerPainter(
                      markers: markers,
                      strokes: strokes,
                      cur: cur,
                      refCenter: (mode == 1 && !_scanned) ? refCenter : null,
                      refRadius: (mode == 1 && !_scanned) ? refRadius : null,
                      s: s,
                      unit: () => 1 / tc.value.getMaxScaleOnAxis(),
                      repaint: tc,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _sizeBar() => SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: kPipeSizes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            avatar: CircleAvatar(backgroundColor: s.colorOf(i), radius: 7),
            label: Text(kPipeSizes[i]),
            selected: active == i,
            onSelected: (_) => setState(() {
              active = i;
              if (mode == 1) {
                _scanned = false;
              }
            }),
          ),
        ),
      );

  Widget _recap() {
    final t = _totals();
    final total = t.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var i = 0; i < t.length; i++)
          if (t[i] > 0) Chip(visualDensity: VisualDensity.compact, avatar: CircleAvatar(backgroundColor: s.colorOf(i), radius: 6), label: Text('${kPipeSizes[i]}: ${t[i]}')),
        Text('TOTAL: $total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    );
  }

  Widget _modePanel() {
    if (mode == 0) {
      return Row(children: [
        const SizedBox(width: 8),
        const Text('Patokan terbesar ='),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: refIdx,
          items: [for (var i = 0; i < kPipeSizes.length; i++) DropdownMenuItem(value: i, child: Text(kPipeSizes[i]))],
          onChanged: (v) => setState(() => refIdx = v!),
        ),
        const Spacer(),
        FilledButton.icon(onPressed: busy ? null : _runAuto, icon: const Icon(Icons.auto_awesome), label: const Text('Deteksi')),
        IconButton(tooltip: 'Hapus semua penanda', onPressed: () => setState(markers.clear), icon: const Icon(Icons.delete_sweep)),
        const SizedBox(width: 8),
      ]);
    }
    if (mode == 1) {
      final maxR = _img != null ? math.min(_img!.width, _img!.height) * 0.25 : 250.0;
      if (!_scanned) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refCenter != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.radio_button_unchecked, size: 18),
                    const SizedBox(width: 6),
                    Text('Ukuran: ${(refRadius * 2).round()} px'),
                    Expanded(
                      child: Slider(
                        value: refRadius.clamp(6.0, maxR),
                        min: 6.0,
                        max: maxR,
                        onChanged: (v) => setState(() => refRadius = v),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    refCenter == null
                        ? 'Ketuk 1 ujung pipa di foto untuk memunculkan lingkaran patokan.'
                        : 'Geser slider agar lingkaran pas dengan pipa, lalu tekan Scan.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (busy || refCenter == null) ? null : _scanByReference,
                  icon: const Icon(Icons.search),
                  label: const Text('Scan'),
                ),
              ]),
            ),
          ],
        );
      }
      return Row(children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text('Diameter ${(refRadius * 2).round()} px (±${s.tolerance.round()}%). Ketuk foto untuk tambah/hapus penanda.', style: const TextStyle(fontSize: 12)),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _scanned = false),
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Atur Ulang Patokan'),
        ),
      ]);
    }
    final total = (int.tryParse(perCtl.text) ?? 0) * strokes.length;
    return Row(children: [
      const SizedBox(width: 8),
      IconButton(tooltip: 'Undo coretan', onPressed: strokes.isEmpty ? null : () => setState(strokes.removeLast), icon: const Icon(Icons.undo)),
      IconButton(tooltip: 'Clear coretan', onPressed: strokes.isEmpty ? null : () => setState(strokes.clear), icon: const Icon(Icons.layers_clear)),
      IconButton(
        tooltip: drawing ? 'Mode gambar (ketuk untuk geser/zoom)' : 'Mode geser/zoom (ketuk untuk menggambar)',
        onPressed: () => setState(() => drawing = !drawing),
        icon: Icon(drawing ? Icons.edit : Icons.pan_tool),
      ),
      Text('${strokes.length} x'),
      SizedBox(
        width: 52,
        child: TextField(controller: perCtl, keyboardType: TextInputType.number, textAlign: TextAlign.center, onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true)),
      ),
      Text('= $total'),
      const Spacer(),
      FilledButton(
        onPressed: total > 0
            ? () => setState(() {
                  manual.add(ManualEntry(active, strokes.length, int.parse(perCtl.text)));
                  strokes.clear();
                })
            : null,
        child: Text('Simpan ${kPipeSizes[active]}'),
      ),
      const SizedBox(width: 8),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hitung Pipa'),
        actions: [
          IconButton(tooltip: 'Posisi Rak', onPressed: _rackSheet, icon: const Icon(Icons.place)),
          IconButton(tooltip: 'Simpan', onPressed: busy ? null : _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: _img == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Auto-All')),
                    ButtonSegment(value: 1, label: Text('Tap-Match')),
                    ButtonSegment(value: 2, label: Text('Coret')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => setState(() {
                    mode = v.first;
                    _scanned = false;
                  }),
                ),
              ),
              if (rackLabel.isNotEmpty) Text('Posisi: $rackLabel', style: const TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: _canvas()),
                  if (busy) const Positioned.fill(child: ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator()))),
                ]),
              ),
              _sizeBar(),
              _modePanel(),
              if (manual.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(spacing: 6, children: [
                    for (var i = 0; i < manual.length; i++)
                      InputChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${kPipeSizes[manual[i].sizeIdx]}: ${manual[i].formula}'),
                        onDeleted: () => setState(() => manual.removeAt(i)),
                      ),
                  ]),
                ),
              _recap(),
              const SizedBox(height: 8),
            ]),
    );
  }
}

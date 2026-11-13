import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Normalisasi orientasi EXIF + batasi sisi terpanjang 2000 px. Dijalankan lewat compute().
Uint8List normalizeImage(Uint8List raw) {
  var im = img.decodeImage(raw)!;
  im = img.bakeOrientation(im);
  final m = math.max(im.width, im.height);
  if (m > 2000) {
    im = im.width >= im.height ? img.copyResize(im, width: 2000) : img.copyResize(im, height: 2000);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

class Circ {
  final double x, y, r;
  Circ(this.x, this.y, this.r);
}

cv.Mat _prepareGray(Uint8List bytes) {
  final m = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
  // Tingkatkan kontras lokal dengan CLAHE agar ujung pipa gelap/bertumpuk lebih jelas
  final clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));
  final eq = clahe.apply(m);
  clahe.dispose();
  m.dispose();
  final b = cv.gaussianBlur(eq, (5, 5), 1.5);
  eq.dispose();
  return b;
}

List<Circ> _hough(cv.Mat g, double minR, double maxR, double p1, double p2, double mdf) {
  final minRi = math.max(4, minR.floor());
  final maxRi = math.max(minRi + 2, maxR.ceil());
  // Jarak antar pusat minimal sekitar 1.4x minR atau sesuai pengaturan mdf (dibatasi agar tidak terlalu jauh)
  final effectiveMdf = math.min(mdf, 1.8);
  final minDist = math.max(8.0, effectiveMdf * minRi);

  final c = cv.HoughCircles(
    g,
    cv.HOUGH_GRADIENT,
    1.2, // dp sedikit > 1 membuat deteksi lingkaran yang sedikit miring/oval jauh lebih sensitif
    minDist,
    param1: math.max(30.0, p1 * 0.8),
    param2: math.max(12.0, p2 * 0.65), // Lebih toleran terhadap tepi pipa yang tidak bulat sempurna
    minRadius: minRi,
    maxRadius: maxRi,
  );

  final out = <Circ>[];
  if (!c.isEmpty && c.cols > 0) {
    for (var i = 0; i < c.cols; i++) {
      final v = c.at<cv.Vec3f>(0, i);
      if (v.val3 > 0) {
        out.add(Circ(v.val1, v.val2, v.val3));
      }
    }
  }
  c.dispose();
  return out;
}

/// Buang duplikat (pusat berdekatan DAN radius mirip). Lingkaran yang konsentris
/// tapi radiusnya beda (pipa bersarang) tetap dipertahankan.
List<Circ> _dedupe(List<Circ> all) {
  all.sort((a, b) => b.r.compareTo(a.r));
  final keep = <Circ>[];
  for (final c in all) {
    final dup = keep.any((k) {
      final d = math.sqrt(math.pow(k.x - c.x, 2) + math.pow(k.y - c.y, 2));
      return (k.r - c.r).abs() / k.r < 0.25 && d < 0.75 * math.max(k.r, c.r);
    });
    if (!dup) keep.add(c);
  }
  return keep;
}

/// Hough multi-band: tiap pita radius dipindai terpisah sehingga pipa kecil
/// di dalam rongga pipa besar tetap terdeteksi.
List<Circ> _allBands(cv.Mat g, double p1, double p2, double mdf) {
  final w = g.cols.toDouble(), h = g.rows.toDouble();
  final limit = math.min(w, h) * 0.45;
  var a = math.max(8.0, math.min(w, h) * 0.01);
  final out = <Circ>[];
  while (a < limit) {
    final b = math.min(limit, a * 2.0);
    out.addAll(_hough(g, a, b, p1, p2, mdf));
    a *= 1.8;
  }
  return _dedupe(out);
}

List<List<double>> _pack(List<Circ> cs) => cs.map((c) => [c.x, c.y, c.r]).toList();

/// MODE 1 (Auto-All). args: bytes, p1, p2, mdf
List<List<double>> autoDetect(Map<String, dynamic> a) {
  final g = _prepareGray(a['bytes'] as Uint8List);
  final p1 = a['p1'] as double;
  final p2 = a['p2'] as double;
  final mdf = a['mdf'] as double;

  var cs = _allBands(g, p1, p2, mdf);
  // Jika masih kosong, ulangi dengan ambang lebih longgar
  if (cs.isEmpty) {
    cs = _allBands(g, p1 * 0.7, math.max(10.0, p2 * 0.5), mdf);
  }
  g.dispose();
  return _pack(cs);
}

/// MODE 2 (Patokan Lingkaran Resizable). args: bytes, r, tol (0..1), p1, p2, mdf
List<List<double>> detectByRadius(Map<String, dynamic> a) {
  final g = _prepareGray(a['bytes'] as Uint8List);
  final r = a['r'] as double;
  final tol = math.max(0.08, a['tol'] as double);
  final p1 = a['p1'] as double;
  final p2 = a['p2'] as double;
  final mdf = a['mdf'] as double;

  final minR = math.max(4.0, r * (1.0 - tol));
  final maxR = r * (1.0 + tol);

  var found = _dedupe(_hough(g, minR, maxR, p1, p2, mdf));
  // Fallback jika ambang standar belum menangkap lingkaran
  if (found.isEmpty) {
    found = _dedupe(_hough(g, minR, maxR, p1 * 0.7, math.max(10.0, p2 * 0.5), mdf));
  }
  g.dispose();
  return _pack(found);
}

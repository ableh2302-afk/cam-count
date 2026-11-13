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

cv.Mat _gray(Uint8List bytes) {
  final m = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
  final b = cv.medianBlur(m, 5);
  m.dispose();
  return b;
}

List<Circ> _hough(cv.Mat g, double minR, double maxR, double p1, double p2, double mdf) {
  final minRi = math.max(3, minR.floor());
  final maxRi = math.max(minRi + 1, maxR.ceil());
  final minDist = math.max(4.0, mdf * minRi);
  final c = cv.HoughCircles(g, cv.HOUGH_GRADIENT, 1.0, minDist,
      param1: p1, param2: p2, minRadius: minRi, maxRadius: maxRi);
  final out = <Circ>[];
  for (var i = 0; i < c.cols; i++) {
    final v = c.at<cv.Vec3f>(0, i);
    out.add(Circ(v.val1, v.val2, v.val3));
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
      return (k.r - c.r).abs() / k.r < 0.2 && d < 0.6 * c.r;
    });
    if (!dup) keep.add(c);
  }
  return keep;
}

/// Hough multi-band: tiap pita radius dipindai terpisah sehingga pipa kecil
/// di dalam rongga pipa besar tetap terdeteksi (nested detection).
List<Circ> _allBands(cv.Mat g, double p1, double p2, double mdf) {
  final w = g.cols.toDouble(), h = g.rows.toDouble();
  final limit = math.min(w, h) * 0.45;
  var a = math.max(6.0, math.max(w, h) * 0.006);
  final out = <Circ>[];
  while (a < limit) {
    final b = math.min(limit, a * 2.2);
    out.addAll(_hough(g, a, b, p1, p2, mdf));
    a *= 2.0;
  }
  return _dedupe(out);
}

List<List<double>> _pack(List<Circ> cs) => cs.map((c) => [c.x, c.y, c.r]).toList();

/// MODE 1. args: bytes, p1, p2, mdf
List<List<double>> autoDetect(Map<String, dynamic> a) {
  final g = _gray(a['bytes'] as Uint8List);
  final cs = _allBands(g, a['p1'] as double, a['p2'] as double, a['mdf'] as double);
  g.dispose();
  return _pack(cs);
}

/// MODE 2. args: bytes, tx, ty, tol (0..1), p1, p2, mdf
/// Mengembalikan {'r': radius sampel (-1 bila gagal), 'c': semua lingkaran berdiameter sama}.
Map<String, dynamic> tapMatch(Map<String, dynamic> a) {
  final p1 = a['p1'] as double, p2 = a['p2'] as double, mdf = a['mdf'] as double;
  final tx = a['tx'] as double, ty = a['ty'] as double, tol = a['tol'] as double;
  final g = _gray(a['bytes'] as Uint8List);
  final all = _allBands(g, p1, p2, mdf);

  Circ? best;
  var bestScore = double.infinity;
  for (final c in all) {
    final d = math.sqrt(math.pow(c.x - tx, 2) + math.pow(c.y - ty, 2));
    if (d <= c.r) {
      final score = d / c.r;
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
  }
  if (best == null) {
    g.dispose();
    return {'r': -1.0, 'c': <List<double>>[]};
  }
  final r = best.r;
  final found = _dedupe(_hough(g, r * (1 - tol), r * (1 + tol), p1, p2, mdf));
  g.dispose();
  final hasSample = found.any((c) => math.sqrt(math.pow(c.x - best!.x, 2) + math.pow(c.y - best.y, 2)) < 0.5 * r);
  if (!hasSample) found.add(best);
  return {'r': r, 'c': _pack(found)};
}

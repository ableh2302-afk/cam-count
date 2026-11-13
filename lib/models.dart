import 'dart:ui';

const List<String> kPipeSizes = ['½"', '¾"', '1"', '1¼"', '1½"', '2"', '2½"', '3"', '4"', '5"', '6"', '8"', '10"', '12"'];

/// Diameter luar nominal (mm) tiap ukuran, dipakai untuk klasifikasi rasio di Mode 1.
const List<double> kPipeOdMm = [21.3, 26.7, 33.4, 42.2, 48.3, 60.3, 73.0, 88.9, 114.3, 141.3, 168.3, 219.1, 273.0, 323.9];

const List<int> kDefaultColors = [
  0xFFE53935, 0xFFFB8C00, 0xFFFDD835, 0xFF7CB342, 0xFF00897B, 0xFF00ACC1, 0xFF1E88E5,
  0xFF3949AB, 0xFF8E24AA, 0xFFD81B60, 0xFF6D4C41, 0xFF546E7A, 0xFFFF6F00, 0xFF00E676,
];

const List<String> kModeNames = ['Auto-All', 'Tap-to-Match', 'Manual Coret'];

class Marker {
  double x, y, r;
  int sizeIdx;
  bool auto;
  Marker(this.x, this.y, this.r, this.sizeIdx, this.auto);
}

class Stroke {
  final List<Offset> pts;
  Stroke(this.pts);
}

class ManualEntry {
  final int sizeIdx, strokes, perStroke;
  ManualEntry(this.sizeIdx, this.strokes, this.perStroke);
  int get total => strokes * perStroke;
  String get formula => '$strokes coretan x $perStroke pipa';
}

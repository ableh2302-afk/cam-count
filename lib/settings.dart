import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

final AppSettings appSettings = AppSettings();

class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;
  double ringWidth = 3, textSize = 14, strokeWidth = 5;
  double tolerance = 6, param1 = 100, param2 = 30, minDistFactor = 1.6;
  bool showNumbers = true, autoTorch = false, haptic = true, watermark = true;
  int refSizeIdx = 5;
  List<int> colors = List.of(kDefaultColors);

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    ringWidth = _p.getDouble('ringWidth') ?? 3;
    textSize = _p.getDouble('textSize') ?? 14;
    strokeWidth = _p.getDouble('strokeWidth') ?? 5;
    tolerance = _p.getDouble('tolerance') ?? 6;
    param1 = _p.getDouble('param1') ?? 100;
    param2 = _p.getDouble('param2') ?? 30;
    minDistFactor = _p.getDouble('minDistFactor') ?? 1.6;
    showNumbers = _p.getBool('showNumbers') ?? true;
    autoTorch = _p.getBool('autoTorch') ?? false;
    haptic = _p.getBool('haptic') ?? true;
    watermark = _p.getBool('watermark') ?? true;
    refSizeIdx = _p.getInt('refSizeIdx') ?? 5;
    final c = _p.getStringList('colors');
    if (c != null && c.length == kPipeSizes.length) colors = c.map(int.parse).toList();
  }

  Future<void> save() async {
    await _p.setDouble('ringWidth', ringWidth);
    await _p.setDouble('textSize', textSize);
    await _p.setDouble('strokeWidth', strokeWidth);
    await _p.setDouble('tolerance', tolerance);
    await _p.setDouble('param1', param1);
    await _p.setDouble('param2', param2);
    await _p.setDouble('minDistFactor', minDistFactor);
    await _p.setBool('showNumbers', showNumbers);
    await _p.setBool('autoTorch', autoTorch);
    await _p.setBool('haptic', haptic);
    await _p.setBool('watermark', watermark);
    await _p.setInt('refSizeIdx', refSizeIdx);
    await _p.setStringList('colors', colors.map((e) => e.toString()).toList());
    notifyListeners();
  }

  Color colorOf(int i) => Color(colors[i]);
}

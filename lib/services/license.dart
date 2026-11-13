import 'dart:convert';
import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// WAJIB diganti sebelum build rilis. Jangan pernah dibagikan.
const String kSecretKey = 'GANTI-DENGAN-SECRET-PANJANG-ACAK-MILIK-ANDA-8f3k2Qz9xLw1';
const String kAdminPin = '889900';

class LicenseStatus {
  final bool valid;
  final String message;
  final String type; // M, Y, P
  final DateTime? expiry;
  LicenseStatus(this.valid, this.message, {this.type = '', this.expiry});
}

class LicenseService {
  static const _st = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const types = {'M': '30 Hari', 'Y': '1 Tahun', 'P': 'Permanen'};

  /// Kode permintaan perangkat: 8 karakter dari hash Android ID.
  static Future<String> deviceCode() async {
    String? id;
    try {
      if (Platform.isAndroid) {
        id = await const AndroidId().getId();
        if (id == null) {
          final a = await DeviceInfoPlugin().androidInfo;
          id = '${a.brand}|${a.model}|${a.id}|${a.fingerprint}';
        }
      } else if (Platform.isIOS) {
        id = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } catch (_) {}
    id ??= 'unknown-device';
    return sha256.convert(utf8.encode('camcount|$id')).toString().substring(0, 8).toUpperCase();
  }

  static String _mac(String dev, String type) {
    final h = Hmac(sha256, utf8.encode(kSecretKey));
    return h.convert(utf8.encode('$dev|$type')).toString().substring(0, 12).toUpperCase();
  }

  /// Format: M-XXXX-XXXX-XXXX (huruf pertama = jenis masa berlaku).
  static String generate(String deviceCode, String type) {
    final m = _mac(deviceCode.trim().toUpperCase(), type);
    return '$type-${m.substring(0, 4)}-${m.substring(4, 8)}-${m.substring(8, 12)}';
  }

  static String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String? verify(String dev, String code) {
    final c = _norm(code);
    if (c.length != 13) return null;
    final t = c[0];
    if (!types.containsKey(t)) return null;
    final expected = _mac(dev, t);
    final given = c.substring(1);
    var diff = 0;
    for (var i = 0; i < 12; i++) {
      diff |= expected.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return diff == 0 ? t : null;
  }

  static Future<String?> activate(String input) async {
    final dev = await deviceCode();
    final t = verify(dev, input);
    if (t == null) return 'Kode aktivasi tidak valid untuk perangkat ini.';
    final now = DateTime.now().toIso8601String();
    await _st.write(key: 'code', value: _norm(input));
    await _st.write(key: 'at', value: now);
    await _st.write(key: 'last', value: now);
    return null;
  }

  static Future<LicenseStatus> check() async {
    try {
      final code = await _st.read(key: 'code');
      final at = DateTime.tryParse(await _st.read(key: 'at') ?? '');
      if (code == null || at == null) return LicenseStatus(false, '');
      final dev = await deviceCode();
      final t = verify(dev, code);
      if (t == null) return LicenseStatus(false, 'Lisensi tidak cocok dengan perangkat ini.');
      final now = DateTime.now();
      final last = DateTime.tryParse(await _st.read(key: 'last') ?? '');
      if (last != null && now.isBefore(last.subtract(const Duration(hours: 24)))) {
        return LicenseStatus(false, 'Jam perangkat tidak wajar (dimundurkan). Perbaiki tanggal/jam HP.');
      }
      await _st.write(key: 'last', value: (last != null && last.isAfter(now) ? last : now).toIso8601String());
      DateTime? exp;
      if (t == 'M') exp = at.add(const Duration(days: 30));
      if (t == 'Y') exp = at.add(const Duration(days: 365));
      if (exp != null && now.isAfter(exp)) {
        return LicenseStatus(false, 'Masa berlaku lisensi telah habis. Minta kode aktivasi baru.', type: t, expiry: exp);
      }
      return LicenseStatus(true, 'Aktif', type: t, expiry: exp);
    } catch (e) {
      return LicenseStatus(false, 'Gagal membaca lisensi: $e');
    }
  }
}

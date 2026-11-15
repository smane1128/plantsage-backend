import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Simple file-based JSON cache stored in app documents directory.
class CacheService {
  static Future<String> _path(String key) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/plantsage_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/$key.json';
  }

  static Future<void> save(String key, dynamic data) async {
    try {
      final path = await _path(key);
      await File(path).writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<dynamic> load(String key) async {
    try {
      final path = await _path(key);
      final file = File(path);
      if (await file.exists()) return jsonDecode(await file.readAsString());
    } catch (_) {}
    return null;
  }
}

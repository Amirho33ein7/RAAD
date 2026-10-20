import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Durable app-local state, backed by an atomically replaced JSON file.
///
/// SharedPreferences is kept as a migration/mirror source by the UI. This file
/// is the primary recovery copy so an interrupted preferences write cannot
/// silently erase a saved profile.
class LocalPersistenceService {
  LocalPersistenceService({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? directoryProviderOverride;

  static const String fileName = 'raad_local_data_v1.json';

  /// Override only in tests; production always uses the app documents folder.
  static Future<Directory> Function()? directoryProviderOverride;

  final Future<Directory> Function()? _directoryProvider;
  Future<void> _writeQueue = Future<void>.value();

  Future<Directory> _directory() async {
    // Capture test overrides at construction, not per operation. Otherwise a
    // late write from a disposed widget can follow another test's global path.
    final dir = await (_directoryProvider ?? getApplicationDocumentsDirectory)();
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _dataFile async =>
      File('${(await _directory()).path}/$fileName');

  Future<Map<String, dynamic>?> read() async {
    await _writeQueue;
    return _readUnqueued();
  }

  Future<Map<String, dynamic>?> _readUnqueued() async {
    final main = await _dataFile;
    final backup = File('${main.path}.bak');

    for (final candidate in [main, backup]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FileSystemException {
        // Try the verified recovery copy.
      } on FormatException {
        // A torn write is ignored in favour of the recovery copy.
      } catch (_) {
        // Keep trying a known recovery file rather than clearing app data.
      }
    }
    return null;
  }

  Future<void> saveValue(String key, Object? value) =>
      saveValues(<String, dynamic>{key: value});

  Future<void> saveValues(Map<String, dynamic> values) {
    final operation = _writeQueue.then((_) async {
      final current = await _readUnqueued() ?? <String, dynamic>{};
      current.addAll(values);
      await _writeAtomically(current);
    });
    // A failed write is reported to its caller but must not poison the queue.
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> saveAll(Map<String, dynamic> values) {
    final operation = _writeQueue.then((_) => _writeAtomically(values));
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _writeAtomically(Map<String, dynamic> values) async {
    final main = await _dataFile;
    final temp = File('${main.path}.tmp');
    final backup = File('${main.path}.bak');
    final encoded = jsonEncode(values);

    await temp.writeAsString(encoded, flush: true);
    final tempDecoded = jsonDecode(await temp.readAsString());
    if (tempDecoded is! Map || jsonEncode(tempDecoded) != encoded) {
      throw const FileSystemException('ذخیرهٔ موقت اطلاعات رعد تأیید نشد.');
    }

    if (await backup.exists()) await backup.delete();
    if (await main.exists()) await main.rename(backup.path);

    try {
      await temp.rename(main.path);
      final finalDecoded = jsonDecode(await main.readAsString());
      if (finalDecoded is! Map || jsonEncode(finalDecoded) != encoded) {
        throw const FileSystemException('تأیید نهایی اطلاعات رعد ناموفق بود.');
      }
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await main.exists()) await main.delete();
      if (await backup.exists()) await backup.rename(main.path);
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

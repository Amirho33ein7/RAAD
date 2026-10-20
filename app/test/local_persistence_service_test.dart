import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raad/services/local_persistence_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('raad-local-state-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('saved profiles and manual profile survive a new store instance', () async {
    final store = LocalPersistenceService(directoryProvider: () async => directory);
    await store.saveValues({
      'savedPlayers': [
        {
          'query': 'UID-12345',
          'profile': {'nickname': 'NightOwl', 'level': 88},
        },
      ],
      'manualProfile': {'nickname': 'MyProfile', 'level': '91'},
      'profileCache': {'nickname': 'NightOwl', 'shortId': 'ID-7788', 'level': 88},
      'lastProfileQuery': 'UID-12345',
    });

    final reopened = LocalPersistenceService(directoryProvider: () async => directory);
    final restored = await reopened.read();

    expect((restored!['savedPlayers'] as List).single['query'], 'UID-12345');
    expect((restored['savedPlayers'] as List).single['profile']['level'], 88);
    expect(restored['manualProfile']['nickname'], 'MyProfile');
    expect(restored['profileCache']['nickname'], 'NightOwl');
    expect(restored['profileCache']['level'], 88);
    expect(restored['lastProfileQuery'], 'UID-12345');
  });

  test('serialized updates preserve unrelated saved data', () async {
    final store = LocalPersistenceService(directoryProvider: () async => directory);
    await store.saveAll({'savedPlayers': [], 'manualProfile': {'level': '20'}});
    await Future.wait([
      store.saveValue('savedPlayers', [
        {'query': 'UID-1', 'profile': {'nickname': 'A'}},
      ]),
      store.saveValue('lastProfileQuery', 'UID-1'),
      store.saveValue('manualProfile', {'level': '21'}),
    ]);

    final result = await store.read();
    expect((result!['savedPlayers'] as List).length, 1);
    expect(result['lastProfileQuery'], 'UID-1');
    expect(result['manualProfile']['level'], '21');
  });

  test('keeps the last committed state available if the main file is later corrupted', () async {
    final store = LocalPersistenceService(directoryProvider: () async => directory);
    await store.saveAll({
      'savedPlayers': [
        {'query': 'UID-OLD', 'profile': {'nickname': 'NightOwl'}},
      ],
      'clips': [
        {'type': 'link', 'url': 'https://example.com/old-clip'},
      ],
    });
    await store.saveValues({
      'savedPlayers': [
        {'query': 'UID-NEW', 'profile': {'nickname': 'NightOwl2'}},
      ],
      'clips': [
        {'type': 'link', 'url': 'https://example.com/new-clip'},
      ],
    });

    final main = File('${directory.path}/${LocalPersistenceService.fileName}');
    final backup = File('${main.path}.bak');
    expect(await backup.exists(), isTrue);

    await main.writeAsString('{damaged JSON');
    final recovered = await store.read();

    expect((recovered!['savedPlayers'] as List).single['query'], 'UID-OLD');
    expect((recovered['clips'] as List).single['url'], 'https://example.com/old-clip');
  });

  test('recovers from an interrupted main-file write using the backup copy', () async {
    final store = LocalPersistenceService(directoryProvider: () async => directory);
    final backup = File('${directory.path}/${LocalPersistenceService.fileName}.bak');
    final main = File('${directory.path}/${LocalPersistenceService.fileName}');
    await backup.writeAsString(jsonEncode({'savedPlayers': [{'query': 'UID-BACKUP'}]}));
    await main.writeAsString('{broken json');

    final result = await store.read();
    expect((result!['savedPlayers'] as List).single['query'], 'UID-BACKUP');
  });
}

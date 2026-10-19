import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raad/services/clip_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('raad-clip-tests-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('copies the full file and verifies its size in the target directory', () async {
    final source = File('${temporaryDirectory.path}/source.mp4');
    final bytes = <int>[0, 1, 2, 3, 255, 128, 19];
    await source.writeAsBytes(bytes);
    final targetDirectory = Directory('${temporaryDirectory.path}/nested/raad_clips');

    final result = await ClipStorageService.copyToDirectory(
      sourcePath: source.path,
      destinationDirectory: targetDirectory,
      timestamp: DateTime(2026, 10, 20),
    );

    final target = File(result.path);
    expect(await target.exists(), isTrue);
    expect(result.sizeBytes, bytes.length);
    expect(await target.length(), bytes.length);
    expect(await target.readAsBytes(), bytes);
    expect(result.path, endsWith('.mp4'));
  });

  test('rejects a missing source file', () async {
    await expectLater(
      ClipStorageService.copyToDirectory(
        sourcePath: '${temporaryDirectory.path}/does-not-exist.mp4',
        destinationDirectory: Directory('${temporaryDirectory.path}/out'),
      ),
      throwsA(isA<ClipStorageException>()),
    );
  });

  test('rejects an empty file', () async {
    final source = File('${temporaryDirectory.path}/empty.mp4');
    await source.writeAsBytes(<int>[]);

    await expectLater(
      ClipStorageService.copyToDirectory(
        sourcePath: source.path,
        destinationDirectory: Directory('${temporaryDirectory.path}/out'),
      ),
      throwsA(isA<ClipStorageException>()),
    );
  });

  test('rejects a file larger than the configured limit', () async {
    final source = File('${temporaryDirectory.path}/too-large.mp4');
    await source.writeAsBytes(<int>[1, 2, 3]);

    await expectLater(
      ClipStorageService.copyToDirectory(
        sourcePath: source.path,
        destinationDirectory: Directory('${temporaryDirectory.path}/out'),
        maxBytes: 2,
      ),
      throwsA(isA<ClipStorageException>()),
    );
  });

  test('does not overwrite a previous clip when timestamps collide', () async {
    final sourceA = File('${temporaryDirectory.path}/a.mp4');
    final sourceB = File('${temporaryDirectory.path}/b.mp4');
    await sourceA.writeAsBytes(<int>[1, 2, 3]);
    await sourceB.writeAsBytes(<int>[4, 5, 6]);
    final destination = Directory('${temporaryDirectory.path}/out');
    final sameTime = DateTime(2026, 10, 20);

    final first = await ClipStorageService.copyToDirectory(
      sourcePath: sourceA.path,
      destinationDirectory: destination,
      timestamp: sameTime,
    );
    final second = await ClipStorageService.copyToDirectory(
      sourcePath: sourceB.path,
      destinationDirectory: destination,
      timestamp: sameTime,
    );

    expect(second.path, isNot(first.path));
    expect(await File(first.path).readAsBytes(), <int>[1, 2, 3]);
    expect(await File(second.path).readAsBytes(), <int>[4, 5, 6]);
  });
}

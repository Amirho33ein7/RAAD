import 'dart:io';

class StoredClipFile {
  const StoredClipFile({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;
}

class ClipStorageException implements Exception {
  const ClipStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Copies a picked video into durable app-private storage and verifies the result.
class ClipStorageService {
  static const int maxVideoSizeBytes = 500 * 1024 * 1024;

  static Future<StoredClipFile> copyToDirectory({
    required String sourcePath,
    required Directory destinationDirectory,
    int maxBytes = maxVideoSizeBytes,
    DateTime? timestamp,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const ClipStorageException('فایل ویدیوی انتخاب‌شده دیگر در دسترس نیست.');
    }

    final sourceLength = await source.length();
    if (sourceLength <= 0) {
      throw const ClipStorageException('فایل ویدیوی انتخاب‌شده خالی است.');
    }
    if (sourceLength > maxBytes) {
      throw const ClipStorageException('اندازهٔ ویدیو از سقف مجاز بیشتر است.');
    }

    await destinationDirectory.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final slash = sourcePath.lastIndexOf(Platform.pathSeparator);
    final rawExtension = dot > slash && dot < sourcePath.length - 1
        ? sourcePath.substring(dot).toLowerCase()
        : '.mp4';
    final extension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(rawExtension)
        ? rawExtension
        : '.mp4';

    final stamp = (timestamp ?? DateTime.now()).microsecondsSinceEpoch;
    var targetPath = '${destinationDirectory.path}${Platform.pathSeparator}clip_$stamp$extension';
    var suffix = 1;
    while (await File(targetPath).exists()) {
      targetPath = '${destinationDirectory.path}${Platform.pathSeparator}clip_${stamp}_$suffix$extension';
      suffix++;
    }

    final target = File(targetPath);
    try {
      await source.copy(target.path);
      if (!await target.exists()) {
        throw const ClipStorageException('فایل مقصد پس از کپی ساخته نشد.');
      }
      final copiedLength = await target.length();
      if (copiedLength != sourceLength) {
        throw ClipStorageException(
          'کپی ویدیو کامل نیست؛ اندازهٔ مبدأ $sourceLength و مقصد $copiedLength بایت است.',
        );
      }
      return StoredClipFile(path: target.path, sizeBytes: copiedLength);
    } catch (_) {
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      rethrow;
    }
  }
}

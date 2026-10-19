/// Strict numeric version comparison for GitHub release tags.
/// Build metadata (for example +5) identifies a build but does not make a release newer.
class AppVersion {
  static List<int>? _parts(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(normalized)) return null;
    try {
      return normalized.split('.').map(int.parse).toList(growable: false);
    } on FormatException {
      return null;
    }
  }

  static bool isValid(String value) => _parts(value) != null;

  /// Returns -1, 0, or 1; returns null if either version is malformed.
  static int? compare(String left, String right) {
    final a = _parts(left);
    final b = _parts(right);
    if (a == null || b == null) return null;

    for (var index = 0; index < 3; index++) {
      final difference = a[index].compareTo(b[index]);
      if (difference != 0) return difference;
    }
    return 0;
  }

  static bool isNewer(String remote, String local) =>
      (compare(remote, local) ?? 0) > 0;
}

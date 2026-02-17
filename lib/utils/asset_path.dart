class AssetPath {
  static bool isRemote(String? raw) {
    if (raw == null) return false;
    final p = raw.trim().toLowerCase();
    return p.startsWith('http://') || p.startsWith('https://') || p.startsWith('gs://');
  }

  static String _decodeUrlLike(String input) {
    var out = input;
    for (int i = 0; i < 2; i++) {
      final lower = out.toLowerCase();
      if (!lower.contains('%3a') && !lower.contains('%2f') && !lower.contains('%25')) {
        break;
      }
      try {
        final decoded = Uri.decodeFull(out);
        if (decoded == out) break;
        out = decoded;
      } catch (_) {
        break;
      }
    }
    return out;
  }

  static String normalize(String? raw) {
    if (raw == null) return '';
    var p = raw.trim();
    if (p.isEmpty) return '';

    p = _decodeUrlLike(p);
    final lower = p.toLowerCase();
    if (lower.startsWith('gs://')) {
      final withoutScheme = p.substring(5);
      final slash = withoutScheme.indexOf('/');
      if (slash > 0 && slash < withoutScheme.length - 1) {
        final bucket = withoutScheme.substring(0, slash);
        final objectPath = withoutScheme.substring(slash + 1);
        final encodedObject = Uri.encodeComponent(objectPath);
        return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedObject?alt=media';
      }
    }
    if (isRemote(p)) return p;

    // Convert backslashes (Windows) to forward slashes
    p = p.replaceAll('\\', '/');

    // If someone accidentally stored "assets/assets/..", collapse to "assets/.."
    while (p.startsWith('assets/assets/')) {
      p = p.replaceFirst('assets/assets/', 'assets/');
    }

    // Some JSON might start with "/assets/..." or "./assets/..."
    if (p.startsWith('/')) p = p.substring(1);
    if (p.startsWith('./')) p = p.substring(2);

    // Ensure it starts with "assets/"
    if (!p.startsWith('assets/')) {
      p = 'assets/$p';
    }

    return p;
  }
}

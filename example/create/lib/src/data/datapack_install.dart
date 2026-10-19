// Writing the embedded pack to a folder (pure: the folder is a [PackSink]).
import 'dart:convert';

import 'pack_format.dart';

/// The few file operations the installer needs; the module adapts the host's
/// `DataFolder` to it, tests use an in-memory map.
abstract interface class PackSink {
  bool exists(String path);
  String readString(String path);
  void writeBytes(String path, List<int> bytes);
  void writeString(String path, String text);
  void createDirectory(String path);
  void deleteRecursive(String path);
}

/// What [installDatapack] did.
final class InstallResult {
  /// Whether files were (re)written; false when the stored stamp matched.
  final bool wrote;
  final int files;
  final int bytes;
  final String stamp;

  const InstallResult({required this.wrote, required this.files, required this.bytes, required this.stamp});
}

/// The stamp that says what is on disk: the content hash plus the chosen categories.
String datapackStamp(String version, Set<String> categories) => '$version|${(categories.toList()..sort()).join(',')}';

/// Writes the pack below [root] when the stored stamp (`<root>/.stamp`) differs
/// from the current one (embedded [version] and the enabled [categories]). The
/// old tree is deleted first so switched-off categories disappear. The stamp is
/// written last: an interrupted write is redone on the next load.
InstallResult installDatapack({
  required PackSink sink,
  required String root,
  required String version,
  required String mcmeta,
  required List<PackBlob> blobs,
  required Set<String> categories,
}) {
  final stamp = datapackStamp(version, categories);
  final stampPath = '$root/.stamp';
  if (sink.exists(stampPath) && sink.exists('$root/pack.mcmeta')) {
    String? stored;
    try {
      stored = sink.readString(stampPath);
    } catch (_) {}
    if (stored == stamp) return InstallResult(wrote: false, files: 0, bytes: 0, stamp: stamp);
  }
  if (sink.exists(root)) sink.deleteRecursive(root);
  sink.createDirectory(root);
  sink.writeString('$root/pack.mcmeta', mcmeta);
  final dirs = <String>{root};
  var files = 1, bytes = utf8.encode(mcmeta).length;
  for (final blob in blobs) {
    if (!categories.contains(blob.category)) continue;
    for (final f in blob.unpack()) {
      final slash = f.path.lastIndexOf('/');
      if (slash > 0) {
        final dir = '$root/${f.path.substring(0, slash)}';
        if (dirs.add(dir)) sink.createDirectory(dir);
      }
      sink.writeBytes('$root/${f.path}', f.bytes);
      files++;
      bytes += f.bytes.length;
    }
  }
  sink.writeString(stampPath, stamp);
  return InstallResult(wrote: true, files: files, bytes: bytes, stamp: stamp);
}

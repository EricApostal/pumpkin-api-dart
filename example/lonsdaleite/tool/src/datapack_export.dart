/// Writes the mod's `data/` folder as a standalone data pack.
library;

import 'dart:convert';
import 'dart:io';

import 'vanilla.dart';

/// Copies `<shared>/data` to `<out>/data` and writes `<out>/pack.mcmeta`
/// (the mod's pack formats with a data pack description). Existing files are
/// overwritten; files that are not in the mod are left alone. Returns how many
/// data files were written.
int exportDatapack({required Directory shared, required Directory out, required Json packMeta}) {
  final data = Directory('${shared.path}/data');
  var written = 0;
  for (final file in data.listSync(recursive: true).whereType<File>()) {
    final target = File('${out.path}/data/${file.path.substring(data.path.length + 1)}');
    target.parent.createSync(recursive: true);
    file.copySync(target.path);
    written++;
  }
  final pack = {...(packMeta['pack']! as Json), 'description': 'Lonsdaleite Tools data'};
  File('${out.path}/pack.mcmeta')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'pack': pack})}\n');
  return written;
}

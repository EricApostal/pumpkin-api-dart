// Packages Create's data pack into `lib/src/data/datapack.g.dart`.
//
//   dart run tool/package_datapack.dart [--create <Create mod checkout>]
//                                       [--out lib/src/data/datapack.g.dart]
//                                       [--report lib/src/data/datapack_report.json]
//
// Reads `src/generated/resources/data/**` and `src/main/resources/data/**` (the
// hand written files win) plus `pack.mcmeta` of the Java mod, drops what a server
// never needs, minifies the JSON, sorts the files into categories and embeds each
// category as gzip + base64 chunks (see lib/src/data/pack_format.dart). The
// categories can be switched off one by one in `config.json` (`datapack.<name>`).
//
// Dropped: `.wiki` (documentation for the Ponder wiki), namespaces the host does
// not know (`curios`, `quark`), and anything that is not a regular file.
// Recipes of every type are kept; the report lists the type of each recipe file.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:create/src/data/pack_format.dart';

/// The categories in the order they are emitted; also the config keys.
const categories = [
  'recipes',
  'loot_tables',
  'advancements',
  'recipe_advancements',
  'tags',
  'structures',
  'registries',
  'other',
];

/// Namespaces that are shipped; the rest (`curios`, `quark`) is dropped.
const _namespaces = {'create', 'c', 'minecraft', 'neoforge'};

/// Which category a pack path (`data/<ns>/<rest>`) belongs to, or `null` to drop it.
String? categoryOf(String path) {
  final parts = path.split('/');
  if (parts.length < 4 || parts[0] != 'data') return null;
  final ns = parts[1];
  final head = parts[2];
  if (!_namespaces.contains(ns) || head.startsWith('.')) return null;
  if (ns == 'neoforge') return 'registries';
  switch (head) {
    case 'recipe':
    case 'recipes':
      return 'recipes';
    case 'loot_table':
    case 'loot_tables':
      return 'loot_tables';
    case 'advancement':
    case 'advancements':
      return parts[3] == 'recipes' ? 'recipe_advancements' : 'advancements';
    case 'tags':
      return 'tags';
    case 'structure':
    case 'structures':
      return 'structures';
    // Data driven registries and data maps. They collide with what the plugin
    // registers itself (damage types, enchantments), so they are off by default.
    case 'damage_type':
    case 'enchantment':
    case 'worldgen':
    case 'neoforge':
    case 'data_maps':
    case 'create':
      return 'registries';
    case 'curios':
      return null;
    default:
      return 'other';
  }
}

Uint8List _prepare(String path, Uint8List bytes) {
  if (!path.endsWith('.json') && !path.endsWith('.mcmeta')) return bytes;
  return Uint8List.fromList(utf8.encode(jsonEncode(jsonDecode(utf8.decode(bytes)))));
}

/// All regular files below [root] as pack path (relative to [base]) to file.
Map<String, File> _scan(Directory root, Directory base) {
  final out = <String, File>{};
  if (!root.existsSync()) return out;
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.substring(base.path.length + 1).replaceAll(r'\', '/');
    out[rel] = e;
  }
  return out;
}

Future<void> main(List<String> args) async {
  var createDir = Platform.environment['CREATE_MOD_DIR'] ?? '../../../../java/Create';
  var outPath = 'lib/src/data/datapack.g.dart';
  var reportPath = 'lib/src/data/datapack_report.json';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--create':
        createDir = args[++i];
      case '--out':
        outPath = args[++i];
      case '--report':
        reportPath = args[++i];
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(64);
    }
  }
  final src = Directory('$createDir/src');
  if (!src.existsSync()) {
    stderr.writeln('Create checkout not found at ${src.path} (use --create or CREATE_MOD_DIR)');
    exit(66);
  }

  // Generated first, hand written files override.
  final generatedRoot = Directory('${src.path}/generated/resources');
  final mainRoot = Directory('${src.path}/main/resources');
  final files = <String, File>{
    ..._scan(Directory('${generatedRoot.path}/data'), generatedRoot),
    ..._scan(Directory('${mainRoot.path}/data'), mainRoot),
  };

  final byCategory = {for (final c in categories) c: <PackFile>[]};
  final dropped = <String, int>{};
  final recipeTypes = <String, int>{};
  final recipeFiles = <String, String>{};
  for (final path in (files.keys.toList()..sort())) {
    final category = categoryOf(path);
    if (category == null) {
      final key = path.split('/').take(3).join('/');
      dropped[key] = (dropped[key] ?? 0) + 1;
      continue;
    }
    final bytes = _prepare(path, files[path]!.readAsBytesSync());
    byCategory[category]!.add(PackFile(path, bytes));
    if (category == 'recipes' && path.endsWith('.json')) {
      final type = (jsonDecode(utf8.decode(bytes)) as Map)['type'] as String? ?? '<none>';
      recipeTypes[type] = (recipeTypes[type] ?? 0) + 1;
      recipeFiles[path] = type;
    }
  }

  // pack.mcmeta of the Java mod, with a description that says what this is.
  final mcmetaFile = File('${mainRoot.path}/pack.mcmeta');
  final mcmeta = mcmetaFile.existsSync()
      ? jsonDecode(mcmetaFile.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'pack': <String, dynamic>{}};
  final pack = Map<String, dynamic>.of((mcmeta['pack'] as Map).cast<String, dynamic>());
  pack['description'] = 'Create: server data (generated by tool/package_datapack.dart)';
  pack['pack_format'] ??= 15;
  final mcmetaText = jsonEncode({...mcmeta, 'pack': pack});

  final hashParts = <List<int>>[utf8.encode(mcmetaText)];
  final blobs = StringBuffer();
  final stats = <String, Map<String, int>>{};
  for (final c in categories) {
    final list = byCategory[c]!;
    if (list.isEmpty) continue;
    final raw = encodePackEntries(list);
    final gz = Uint8List.fromList(gzip.encode(raw));
    for (final f in list) {
      hashParts
        ..add(utf8.encode(f.path))
        ..add(f.bytes);
    }
    final b64 = base64Encode(gz);
    stats[c] = {'files': list.length, 'raw': raw.length, 'gzip': gz.length, 'base64': b64.length};
    blobs.writeln("  PackBlob('$c', ${list.length}, ${raw.length}, [");
    for (final chunk in chunkString(b64)) {
      blobs.writeln("    '$chunk',");
    }
    blobs.writeln('  ]),');
  }
  final version = fnv1a64Hex(hashParts);

  final out = StringBuffer()
    ..writeln('// GENERATED by tool/package_datapack.dart. Do not edit.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars, implementation_imports')
    ..writeln("import 'pack_format.dart';")
    ..writeln()
    ..writeln('/// Hash of the embedded files; the plugin rewrites the pack when it changes.')
    ..writeln("const String datapackVersion = '$version';")
    ..writeln()
    ..writeln('/// `pack.mcmeta` of the embedded pack.')
    ..writeln("const String datapackMcmeta = '${mcmetaText.replaceAll("'", r"\'")}';")
    ..writeln()
    ..writeln('/// The embedded categories, each independently skippable by config.')
    ..writeln('const List<PackBlob> datapackBlobs = [')
    ..write(blobs)
    ..writeln('];');
  File(outPath).writeAsStringSync(out.toString());

  final report = {
    'version': version,
    'categories': stats,
    'recipeTypes': Map.fromEntries(recipeTypes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))),
    'dropped': dropped,
    'recipeFiles': recipeFiles,
  };
  File(reportPath).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));

  var gzTotal = 0, rawTotal = 0, count = 0;
  for (final e in stats.entries) {
    stdout.writeln('${e.key.padRight(20)} ${e.value['files'].toString().padLeft(5)} files  raw ${e.value['raw']}  gzip ${e.value['gzip']}');
    gzTotal += e.value['gzip']!;
    rawTotal += e.value['raw']!;
    count += e.value['files']!;
  }
  stdout.writeln('total $count files, raw $rawTotal, gzip $gzTotal, version $version');
  stdout.writeln('dropped: $dropped');
  stdout.writeln('recipe types: ${recipeTypes.length}');
}

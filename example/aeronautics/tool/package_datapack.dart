// Packages Aeronautics' data pack into `lib/src/data/datapack.g.dart`.
//
//   dart run tool/package_datapack.dart [--mod <Aeronautics mod checkout>]
//                                       [--out lib/src/data/datapack.g.dart]
//                                       [--report lib/src/data/datapack_report.json]
//
// Modeled on `example/create/tool/package_datapack.dart` and sharing its format
// (`package:create/src/data/pack_format.dart`, the writer of the embedded blobs,
// and `datapack_install.dart`, the reader the plugin uses).
//
// Reads `common/src/generated/resources/data/**`, `common/src/main/resources/data/**`
// and `neoforge/src/main/resources/data/**` of the Java mod (a later directory wins
// over an earlier one) plus the mod's `pack.mcmeta`, drops what a server never needs,
// minifies the JSON, sorts the files into categories and embeds each category as
// gzip + base64 chunks. The categories can be switched off one by one in
// `config.json` (`datapack.<name>`).
//
// Dropped: `assets/` (client side; a Pumpkin plugin ships no assets), the datagen
// `.cache`, and anything that is not a regular file. Recipes of every type are kept;
// the report lists the type of each recipe file.
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

/// Namespaces that are shipped: everything the Java mod writes into `data/`,
/// including the tags it adds to Sable's and Simulated's namespaces.
const _namespaces = {'aeronautics', 'c', 'minecraft', 'sable', 'simulated', 'neoforge'};

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
    // Data driven registries (the jukebox song, Sable's physics block properties
    // and floating materials) and data maps. The plugin registers the song itself
    // through the host API, so this stays off by default.
    case 'jukebox_song':
    case 'physics_block_properties':
    case 'floating_materials':
    case 'worldgen':
    case 'data_maps':
      return 'registries';
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
  var modDir =
      Platform.environment['AERONAUTICS_MOD_DIR'] ?? '../../../../java/Simulated-Project/aeronautics';
  var outPath = 'lib/src/data/datapack.g.dart';
  var reportPath = 'lib/src/data/datapack_report.json';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--mod':
        modDir = args[++i];
      case '--out':
        outPath = args[++i];
      case '--report':
        reportPath = args[++i];
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(64);
    }
  }
  final common = Directory('$modDir/common/src');
  if (!common.existsSync()) {
    stderr.writeln('Aeronautics checkout not found at ${common.path} (use --mod or AERONAUTICS_MOD_DIR)');
    exit(66);
  }

  // The three resource roots, later ones win over earlier ones.
  final roots = <Directory>[
    Directory('$modDir/common/src/generated/resources'),
    Directory('$modDir/common/src/main/resources'),
    Directory('$modDir/neoforge/src/main/resources'),
  ];
  final files = <String, File>{};
  for (final root in roots) {
    files.addAll(_scan(Directory('${root.path}/data'), root));
  }

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
  final mcmetaFile = File('${roots[1].path}/pack.mcmeta');
  final mcmeta = mcmetaFile.existsSync()
      ? jsonDecode(mcmetaFile.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'pack': <String, dynamic>{}};
  final pack = Map<String, dynamic>.of((mcmeta['pack'] as Map).cast<String, dynamic>());
  pack['description'] = 'Aeronautics: server data (generated by tool/package_datapack.dart)';
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
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln("import 'package:create/src/data/pack_format.dart';")
    ..writeln()
    ..writeln('/// Hash of the embedded files; the plugin rewrites the pack when it changes.')
    ..writeln("const String datapackVersion = '$version';")
    ..writeln()
    ..writeln('/// `pack.mcmeta` of the embedded pack.')
    ..writeln("const String datapackMcmeta = '${mcmetaText.replaceAll("'", r"\'")}';")
    ..writeln()
    ..writeln('/// The embedded categories, each independently skippable by config.')
    ..writeln('const List<PackBlob> aeronauticsDatapackBlobs = [')
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
/// Reads the mod's `shared-resources` folder: the data pack (`data/`), the
/// resource pack (`assets/`) and the language file.
library;

import 'dart:convert';
import 'dart:io';

import 'vanilla.dart';

/// A parsed `data/<namespace>/...` tree.
final class ModData {
  /// `item` or `block` to tag id to the tag file's JSON.
  final Map<String, Map<String, Json>> tags;

  /// Every recipe: `{id, type, json}`.
  final List<Json> recipes;

  /// Every loot table: `{id, type, json}`.
  final List<Json> lootTables;

  /// Data files of kinds the generator does not read (advancements, ...), as
  /// `data/` relative paths. Anything listed here is not in the manifest.
  final List<String> unreadDataFiles;

  /// `assets/` relative paths grouped by what they are.
  final Map<String, List<String>> assets;

  /// The `en_us.json` translations.
  final Map<String, String> lang;

  /// The `pack.mcmeta` as JSON.
  final Json packMeta;

  const ModData({
    required this.tags,
    required this.recipes,
    required this.lootTables,
    required this.unreadDataFiles,
    required this.assets,
    required this.lang,
    required this.packMeta,
  });

  factory ModData.read(Directory shared) {
    final data = Directory('${shared.path}/data');
    final tags = <String, Map<String, Json>>{};
    final recipes = <Json>[];
    final lootTables = <Json>[];
    final unread = <String>[];

    for (final file in _jsonFiles(data)) {
      final relative = _relative(data, file);
      final [namespace, kind, ...rest] = relative.split('/');
      final path = rest.join('/').replaceAll(RegExp(r'\.json$'), '');
      final json = _readJson(file);
      switch (kind) {
        case 'recipe':
          recipes.add({'id': '$namespace:$path', 'type': json['type'], 'json': json});
        case 'loot_table':
          lootTables.add({'id': '$namespace:$path', 'type': json['type'], 'json': json});
        case 'tags':
          final [registry, ...tagPath] = rest;
          final tagId = '$namespace:${tagPath.join('/').replaceAll(RegExp(r'\.json$'), '')}';
          (tags[registry] ??= {})[tagId] = json;
        default:
          unread.add('data/$relative');
      }
    }

    final assetsDir = Directory('${shared.path}/assets');
    final assets = <String, List<String>>{};
    for (final file in _allFiles(assetsDir)) {
      final relative = _relative(assetsDir, file);
      final parts = relative.split('/');
      final group = parts.length >= 3 ? parts[1] : 'root';
      (assets[group] ??= []).add('assets/$relative');
    }

    final langFile = File('${shared.path}/assets/${_onlyNamespace(assetsDir)}/lang/en_us.json');
    return ModData(
      tags: tags,
      recipes: recipes,
      lootTables: lootTables,
      unreadDataFiles: unread,
      assets: assets,
      lang: {
        for (final e in _readJson(langFile).entries) e.key: e.value as String,
      },
      packMeta: _readJson(File('${shared.path}/pack.mcmeta')),
    );
  }

  static String _onlyNamespace(Directory assets) {
    final names = assets.listSync().whereType<Directory>().map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last).toList();
    if (names.length != 1) throw StateError('Expected one assets namespace, found $names');
    return names.single;
  }

  static Json _readJson(File file) =>
      jsonDecode(file.readAsStringSync()) as Json;

  static String _relative(Directory base, File file) =>
      file.path.substring(base.path.length + 1);

  static List<File> _allFiles(Directory dir) {
    final files = dir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static List<File> _jsonFiles(Directory dir) =>
      _allFiles(dir).where((f) => f.path.endsWith('.json')).toList();
}

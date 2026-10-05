// Generates the vanilla registry lists (names in network id order) that the
// registry synchronisation needs, from the JSON assets of a Pumpkin checkout.
//
//   puro dart run tool/generate_vanilla_registries.dart [--assets <dir>] [--mc-version 26.3]
//
// Writes lib/src/vanilla_registries.g.dart (embedded in plugins) and
// data/vanilla_registries.json (read by the Python test client). Both are
// checked in; run this only when Pumpkin's assets change (a new Minecraft
// version).
//
// The ids come from the same files Pumpkin uses for its own packets, so they
// are the ids Pumpkin puts on the wire: that agreement is what the registry
// sync has to promise a NeoForge client.
import 'dart:convert';
import 'dart:io';

const defaultAssets =
    '/Users/eric/Documents/development/languages/rust/Pumpkin/assets';

void main(List<String> args) {
  var assets = Platform.environment['PUMPKIN_ASSETS'] ?? defaultAssets;
  var version = '26.3';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--assets' && i + 1 < args.length) assets = args[++i];
    if (args[i] == '--mc-version' && i + 1 < args.length) version = args[++i];
  }
  final dir = Directory(assets);
  if (!dir.existsSync()) {
    stderr.writeln('Pumpkin assets not found: $assets (use --assets <dir>)');
    exit(2);
  }

  Object json(String name) =>
      jsonDecode(File('$assets/$name').readAsStringSync()) as Object;

  /// Names of a `{name: {"id": n, ...}}` map, ordered by id (must be 0..n-1).
  List<String> byIdField(String file) {
    final map = (json(file) as Map).cast<String, dynamic>();
    return _ordered(file, {
      for (final e in map.entries) e.key: (e.value as Map)['id'] as int,
    });
  }

  /// Names of a `{name: n}` map, ordered by n.
  List<String> byValue(String file) {
    final map = (json(file) as Map).cast<String, dynamic>();
    return _ordered(file, {for (final e in map.entries) e.key: e.value as int});
  }

  /// Names of a list whose order is the id.
  List<String> listOrder(String file, {String? key}) {
    final list = (json(file) as List).cast<Object?>();
    return [
      for (final e in list)
        key == null ? e as String : (e as Map)[key] as String,
    ];
  }

  final blocks = (json('blocks.json') as Map).cast<String, dynamic>();
  final blockList = (blocks['blocks'] as List).cast<Map<String, dynamic>>();

  final registries = <String, List<String>>{
    'minecraft:item': byIdField('items.json'),
    'minecraft:block': _ordered('blocks.json', {
      for (final b in blockList) b['name'] as String: b['id'] as int,
    }),
    'minecraft:entity_type': byIdField('entities.json'),
    'minecraft:fluid': _ordered('fluids.json', {
      for (final f
          in (json('fluids.json') as List).cast<Map<String, dynamic>>())
        f['name'] as String: f['id'] as int,
    }),
    'minecraft:mob_effect': byIdField('effect.json'),
    'minecraft:potion': byIdField('potion.json'),
    'minecraft:attribute': byIdField('attributes.json'),
    'minecraft:data_component_type': byValue('data_component.json'),
    'minecraft:particle_type': listOrder('particles.json'),
    'minecraft:sound_event': listOrder('sounds.json'),
    'minecraft:game_event': listOrder('game_event.json'),
    'minecraft:custom_stat': listOrder('custom_stats.json'),
    'minecraft:menu': listOrder('screens.json'),
    'minecraft:block_entity_type': [
      for (final n in (blocks['block_entity_types'] as List)) n as String,
    ],
  };

  // Block state ids are 0..n-1 over all blocks in id order; the client numbers
  // the states of a modded block after these.
  final stateIds = <int>{
    for (final b in blockList)
      for (final state in (b['states'] as List).cast<Map<String, dynamic>>())
        state['id'] as int,
  };
  final stateCount = stateIds.length;
  for (var i = 0; i < stateCount; i++) {
    if (!stateIds.contains(i)) {
      stderr.writeln('blocks.json: block state ids are not contiguous (missing $i)');
      exit(3);
    }
  }

  // Everything is `minecraft:`; the files mix prefixed and bare names.
  final qualified = <String, List<String>>{
    for (final e in registries.entries)
      e.key: [for (final n in e.value) n.contains(':') ? n : 'minecraft:$n'],
  };
  for (final e in qualified.entries) {
    final unique = e.value.toSet();
    if (unique.length != e.value.length) {
      stderr.writeln('${e.key} has duplicate names');
      exit(3);
    }
  }

  final here = File.fromUri(Platform.script).parent.parent.path;

  File('$here/data/vanilla_registries.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert({'minecraft_version': version, 'source': 'Pumpkin assets (items.json, blocks.json, entities.json, '
        'fluids.json, effect.json, potion.json, attributes.json, '
        'data_component.json, particles.json, sounds.json, game_event.json, '
        'custom_stats.json, screens.json)', 'block_state_count': stateCount, 'note': 'Names in network id order (index = id). Derived from Mojang '
        'data files shipped with Pumpkin; see assets/NOTICE.md there.', 'registries': qualified})}\n',
  );

  final out = StringBuffer()
    ..writeln(
      '// GENERATED by tool/generate_vanilla_registries.dart from the JSON',
    )
    ..writeln('// assets of Pumpkin ($assets). Do not edit.')
    ..writeln('//')
    ..writeln(
      '// Names of the vanilla registries in network id order (index = id),',
    )
    ..writeln('// without the `minecraft:` prefix, one per line.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln("/// The Minecraft version the lists are for.")
    ..writeln("const String vanillaMinecraftVersion = '$version';")
    ..writeln()
    ..writeln('/// The number of vanilla block states: the id of the first state of the')
    ..writeln('/// first modded block.')
    ..writeln('const int vanillaBlockStateCount = $stateCount;')
    ..writeln();
  for (final e in qualified.entries) {
    final name = _constName(e.key);
    out
      ..writeln('const String $name =')
      ..writeln(
        "    '${e.value.map((n) => n.substring('minecraft:'.length)).join(r'\n')}';",
      )
      ..writeln();
  }
  out
    ..writeln('/// The registries with a generated list.')
    ..writeln('const List<String> vanillaRegistryKeys = [');
  for (final key in qualified.keys) {
    out.writeln("  '$key',");
  }
  out
    ..writeln('];')
    ..writeln()
    ..writeln(
      '/// The packed (newline separated, no namespace) list of [registry], or null.',
    )
    ..writeln('String? vanillaRegistryPacked(String registry) {')
    ..writeln('  switch (registry) {');
  for (final key in qualified.keys) {
    out
      ..writeln("    case '$key':")
      ..writeln('      return ${_constName(key)};');
  }
  out
    ..writeln('    default:')
    ..writeln('      return null;')
    ..writeln('  }')
    ..writeln('}');
  File('$here/lib/src/vanilla_registries.g.dart').writeAsStringSync('$out');

  for (final e in qualified.entries) {
    stdout.writeln('${e.key}: ${e.value.length} entries');
  }
}

String _constName(String key) {
  final parts = key.substring('minecraft:'.length).split('_');
  return 'vanilla${parts.map((p) => p[0].toUpperCase() + p.substring(1)).join()}Packed';
}

List<String> _ordered(String file, Map<String, int> ids) {
  final byId = <int, String>{};
  for (final e in ids.entries) {
    if (byId.containsKey(e.value)) {
      stderr.writeln('$file: duplicate id ${e.value}');
      exit(3);
    }
    byId[e.value] = e.key;
  }
  for (var i = 0; i < byId.length; i++) {
    if (!byId.containsKey(i)) {
      stderr.writeln('$file: ids are not contiguous (missing $i)');
      exit(3);
    }
  }
  return [for (var i = 0; i < byId.length; i++) byId[i]!];
}

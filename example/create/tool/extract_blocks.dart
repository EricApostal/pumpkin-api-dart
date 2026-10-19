// Extracts Create's BLOCKS and ITEMS from the Java sources.
//
// Usage (from example/create):
//   dart run tool/extract_blocks.dart [--create DIR] [--mc DIR] [--out DIR]
//                                     [--dump] [KEY ...]
//
// See tool/README.md. Writes lib/src/manifest/{blocks,items}.g.dart and
// lib/src/manifest/REPORT_blocks.md. Uses only dart:io / dart:convert.
import 'dart:convert';
import 'dart:io';

import 'src/blocks_build.dart';
import 'src/blocks_emit.dart';
import 'src/blocks_enum.dart';
import 'src/interp.dart';
import 'src/items_build.dart';
import 'src/java.dart';

void main(List<String> args) {
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final pkgRoot = File(Platform.script.toFilePath()).parent.parent.path;
  final create = _norm(opt('--create') ?? Platform.environment['CREATE_MOD_DIR'] ?? '$pkgRoot/../../../../java/Create');
  final mc = opt('--mc') ?? Platform.environment['MC_SRC_DIR'] ?? _findMcSources(pkgRoot);
  final outDir = _norm(opt('--out') ?? '$pkgRoot/lib/src/manifest');
  if (mc == null) {
    stderr.writeln('Vanilla Minecraft 26.3 sources not found. Pass --mc DIR (root containing net/minecraft/...).');
    exit(2);
  }
  stdout.writeln('create: $create\nminecraft sources: $mc\nout: $outDir');

  final roots = [Directory('$create/src/main/java'), Directory(mc), ...externalRoots(pkgRoot)];
  final idx = SourceIndex(roots)..build();
  final ip = Interp(idx);
  final en = BlockEnumerator(ip, create)..enumerateAll();
  final st = BlockBuilderStage(ip, create);
  final recs = st.build(en.blocks);
  final ie = ItemEnumerator(ip, st, st.engine);
  final items = ie.enumerate(recs);

  final flagsWithValue = {'--create', '--mc', '--out'};
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (flagsWithValue.contains(args[i])) {
      i++;
    } else if (!args[i].startsWith('--')) {
      positional.add(args[i]);
    }
  }
  for (final k in positional) {
    _dumpBlock(recs, k);
  }
  if (args.contains('--dump')) {
    for (final r in recs) {
      stdout.writeln('${r.key} [${r.className}] ${r.props.sorted.map((p) => p.toString()).join(' ')}');
    }
  }

  final report = _report(recs, items, create, ip);
  Directory(outDir).createSync(recursive: true);
  File('$outDir/blocks.g.dart').writeAsStringSync(emitBlocks(recs));
  File('$outDir/items.g.dart').writeAsStringSync(emitItems(items));
  File('$outDir/REPORT_blocks.md').writeAsStringSync(report);
  stdout.writeln('blocks: ${recs.length}, items: ${items.length}');
  stdout.writeln('wrote $outDir/blocks.g.dart, items.g.dart, REPORT_blocks.md');
}

String _norm(String p) => Directory(p).existsSync() ? Directory(p).resolveSymbolicLinksSync() : p;

String? _findMcSources(String pkgRoot) {
  final reg = Directory('$pkgRoot/../../../../java/Registrate/build/neoForm');
  if (!reg.existsSync()) return null;
  for (final d in reg.listSync()) {
    final t = Directory('${d.path}/steps/transformSource/transformed');
    if (t.existsSync()) return t.path;
  }
  return null;
}

/// Unzips library source jars (catnip etc.) from ~/.m2 into .dart_tool so that
/// external enums / base classes referenced by Create can be resolved.
List<Directory> externalRoots(String pkgRoot) {
  final home = Platform.environment['HOME'] ?? '';
  final out = <Directory>[];
  final cache = Directory('$pkgRoot/.dart_tool/create_manifest/ext_src');
  final jars = <String, String>{
    'catnip': '$home/.m2/repository/net/createmod/catnip/catnip-neoforge',
    'ponder': '$home/.m2/repository/net/createmod/ponder',
  };
  for (final e in jars.entries) {
    final base = Directory(e.value);
    if (!base.existsSync()) continue;
    final found = base.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('-sources.jar')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (found.isEmpty) continue;
    final dest = Directory('${cache.path}/${e.key}');
    if (!dest.existsSync()) {
      dest.createSync(recursive: true);
      final r = Process.runSync('unzip', ['-qo', found.last.path, '-d', dest.path]);
      if (r.exitCode != 0) {
        stderr.writeln('unzip failed for ${found.last.path}: ${r.stderr}');
        continue;
      }
    }
    out.add(dest);
  }
  return out;
}

void _dumpBlock(List<BlockRecord> recs, String key) {
  for (final r in recs.where((r) => r.key == key)) {
    stdout.writeln('${r.key} ${r.className} factory=${r.def.factoryExpr}');
    for (final p in r.props.sorted) {
      stdout.writeln('  ${p.name} ${p.kind} ${p.values} verified=${p.verified} from ${p.source}');
    }
    stdout.writeln('  defaults ${r.props.defaults}');
    stdout.writeln('  hardness ${r.stats.hardness}/${r.stats.resistance} sound ${r.stats.sound} map ${r.stats.mapColor} light ${r.stats.light}');
    stdout.writeln('  notes ${r.notes}');
  }
}

String _report(List<BlockRecord> recs, List<ItemRecord> items, String create, Interp ip) {
  final sb = StringBuffer();
  final gen = '$create/src/generated/resources/assets/create';
  String h(String s) => '\n## $s\n';
  sb.writeln('# Blocks and items manifest report');
  sb.writeln();
  sb.writeln('Generated by `tool/extract_blocks.dart` (do not hand-edit). Output: `blocks.g.dart`, `items.g.dart`.');

  sb.writeln(h('Counts'));
  final bySource = <String, int>{};
  for (final r in recs) {
    final s = r.def.source;
    final g = s.startsWith('AllBlocks.')
        ? (s.contains('[') ? 'AllBlocks (generated per colour / copper variant)' : 'AllBlocks (explicit)')
        : s.startsWith('AllFluids.')
            ? 'AllFluids (fluid blocks)'
            : s.startsWith('palette:')
                ? 'palettes (stone types: pattern + partials)'
                : s.startsWith('AllPaletteStoneTypes.')
                    ? 'palettes (custom base stone blocks)'
                    : 'AllPaletteBlocks (glass / windows / panes)';
    bySource[g] = (bySource[g] ?? 0) + 1;
  }
  sb.writeln('| Source | Blocks |\n|---|---|');
  bySource.forEach((k, v) => sb.writeln('| $k | $v |'));
  sb.writeln('| **total blocks** | **${recs.length}** |');
  var states = 0;
  var withProps = 0;
  var water = 0;
  for (final r in recs) {
    states += r.stateCount;
    if (r.props.props.isNotEmpty) withProps++;
    if (r.waterlogged) water++;
  }
  sb.writeln();
  sb.writeln('* block states (sum): $states; blocks with properties: $withProps; waterloggable: $water');
  sb.writeln('* items: ${items.length} (${items.where((i) => i.isBlockItem).length} block items, '
      '${items.where((i) => !i.isBlockItem).length} others)');
  sb.writeln('* "~700" in the task text is the number of `block.create.*` lang keys incl. tooltips; the real block count is ${recs.length}.');

  sb.writeln(h('Enumeration cross-check'));
  final bs = Directory('$gen/blockstates').listSync().map((e) => e.path.split('/').last.replaceAll('.json', '')).toSet();
  final lang = (jsonDecode(File('$gen/lang/en_us.json').readAsStringSync()) as Map).keys.cast<String>();
  final langBlocks = lang.where((k) => k.startsWith('block.create.') && k.split('.').length == 3).map((k) => k.substring(13)).toSet();
  final keys = recs.map((r) => r.key).toSet();
  sb.writeln('* enumerated blocks: ${recs.length} (unique ${keys.length})');
  sb.writeln('* blockstate JSON files: ${bs.length}; in enumeration but no JSON: ${keys.difference(bs).toList()}; JSON without block: ${bs.difference(keys).toList()}');
  sb.writeln('* lang `block.create.<key>` entries: ${langBlocks.length}; missing from enumeration: ${langBlocks.difference(keys).toList()}; blocks without lang: ${keys.difference(langBlocks).toList()}');
  final models = Directory('$gen/models/item').listSync().map((e) => e.path.split('/').last.replaceAll('.json', '')).toSet();
  final ik = items.map((i) => i.key).toSet();
  final langItems = lang.where((k) => k.startsWith('item.create.') && k.split('.').length == 3).map((k) => k.substring(12)).toSet();
  sb.writeln('* item model JSON files: ${models.length}; enumerated items without a model file: ${ik.difference(models).toList()}');
  sb.writeln('  (the extra model files are derived models: armor trims `cardboard_*_trim`, `clipboard_0..2`)');
  sb.writeln('* lang `item.create.<key>` keys not matching an item: ${langItems.difference(ik).toList()} (generic names for the per-style package items)');

  sb.writeln(h('Block state property cross-check (Java vs blockstate JSON)'));
  var checked = 0;
  final disagree = <String>[];
  for (final r in recs) {
    if (r.jsonProps == null) continue;
    checked++;
    if (r.jsonAgrees == false) disagree.add(r.key);
  }
  sb.writeln('* blocks whose blockstate JSON variant / multipart keys were compared to the Java properties: $checked');
  sb.writeln('* disagreements (JSON uses a property or a value that Java does not define): ${disagree.isEmpty ? 'none' : disagree.join(', ')}');
  sb.writeln('* JSON files only list the properties the model generator varies on (`forAllStatesExcept`, collapsed wall sides, etc.), so a property being absent from JSON is not a disagreement; the check is one-directional (JSON subset of Java).');

  sb.writeln(h('Entries marked `verified: false`'));
  final unv = recs.where((r) => !r.verified).toList();
  if (unv.isEmpty) {
    sb.writeln('No block is marked unverified.');
  } else {
    for (final r in unv) {
      sb.writeln('* block `${r.key}` (${r.def.source}): ${r.notes.where((n) => n.startsWith('!') || n.startsWith('props:')).map((n) => n.replaceFirst('!', '')).join('; ')}');
    }
  }
  final uit = items.where((i) => !i.verified).toList();
  if (uit.isEmpty) {
    sb.writeln('No item is marked unverified.');
  } else {
    for (final i in uit) {
      sb.writeln('* item `${i.key}` (${i.source}): ${i.notes.join('; ')}');
    }
  }

  sb.writeln(h('Other uncertain / noteworthy values'));
  final dyn = recs.where((r) => r.stats.lightDynamic).map((r) => r.key).toList();
  sb.writeln('* state dependent light level (constant is the max literal found, may be 0): ${dyn.join(', ')}');
  final custom = recs.where((r) => r.stats.sound == 'custom').map((r) => r.key).toList();
  sb.writeln('* custom (non `SoundType` constant) sound types: ${custom.join(', ')}');
  final mc = recs.where((r) => r.stats.mapColor == 'dynamic' || r.stats.mapColor.startsWith('from:')).map((r) => '${r.key}=${r.stats.mapColor}').toList();
  sb.writeln('* map colour derived from another block or dynamic: ${mc.join(', ')}');
  final noItem = recs.where((r) => !r.def.hasItem).map((r) => r.key).toList();
  sb.writeln('* blocks without a block item (${noItem.length}): ${noItem.join(', ')}');

  sb.writeln(h('Assumptions and ambiguities'));
  sb.writeln('''
* **Registration order.** Registrate keeps registrations per registry in `register()` call order (Guava `HashBasedTable` is insertion ordered). `Create` initialises `AllBlocks`, `AllItems`, `AllFluids`, `AllPaletteBlocks` in this order; the extractor assumes no static initialiser pulls another `All*` class forward (all cross references in `AllBlocks` are inside lambdas). Block items are registered when the item builder is `build()`/`register()`ed, i.e. in block order, before the block itself. Items are therefore: block items of AllBlocks, AllItems (incl. the package items generated from `PackageStyles`), fluid buckets, palette block items.
* **State ids.** `StateDefinition` sorts properties by name; values are in `Property.getPossibleValues()` order (bool: true,false; int: min..max; enum: declaration order or the explicit list/filter given to `EnumProperty.create`). Note 26.3 `BlockStateProperties.FACING` is NORTH,EAST,SOUTH,WEST,UP,DOWN (explicit list) while the horizontal facing and other `Direction`-filtered properties follow the `Direction` enum order DOWN,UP,NORTH,SOUTH,WEST,EAST. The state index is a mixed radix number with the first (alphabetically smallest) property most significant (`Lists.cartesianProduct`).
* **Default state** is folded from every `registerDefaultState(...)` call along the class chain (root first); `stateDefinition.any()` resets to the first value of each property. Properties never set default to their first value.
* **`SharedProperties.copperMetal()`** returns `Blocks.COPPER_BLOCK`, which in 26.3 is a `WeatheringCopperCollection`, not a `Block` (the port is in progress). The extractor treats it as the unaffected copper block (hardness 3, resistance 6, requires tool, `COPPER` sound, `COLOR_ORANGE`).
* **Block base stats** come from the last `initialProperties(...)` (vanilla `Properties.ofFullCopy`) followed by all `properties(...)` callbacks in order, like `BlockBuilder`; vanilla blocks are read from the decompiled `Blocks.java`. State dependent fields (`lightLevel`) are flagged `lightDynamic`.
* **Item stats** cover `Item.Properties` calls on the registrate chain (`stacksTo`, `durability`, `fireResistant`, `rarity`, `food`, tool/armor builders) plus `stacksTo`/`durability` literals found in constructors of Create item classes along the superclass chain. Vanilla item classes are assumed not to override the stack size. Components built from complex expressions (`food`, `component(..)`) are kept as text.
* **Library sources.** catnip's sources (e.g. `Pointing`) are unzipped from `~/.m2` into `.dart_tool/create_manifest/ext_src`.
* **Stress values** (`stressImpact`/`stressCapacity`) are the `CStress.setImpact/setCapacity` defaults attached to each block; the config defaults live in `stress.g.dart`.''');
  if (ip.warnings.isNotEmpty) {
    sb.writeln(h('Interpreter warnings'));
    for (final w in ip.warnings.toSet()) {
      sb.writeln('* $w');
    }
  }
  return sb.toString();
}

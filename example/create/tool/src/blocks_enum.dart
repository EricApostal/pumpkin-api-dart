// Enumerates every block Create registers, in registration order.
import 'expr.dart';
import 'interp.dart';
import 'java.dart';

class BlockDef {
  BlockDef(this.key, this.source);
  String key;
  final String source; // e.g. AllBlocks.SHAFT / AllBlocks.SEATS[red] / palette:granite
  String? factoryExpr;
  Map<String, Bound> factoryEnv = const {};
  JavaClass? factoryCtx;
  List<Call> calls = [];
  // derived
  String? className;
  JavaClass? cls;
  bool hasItem = false;
  final List<Call> initialCalls = [];
  final List<Call> propCalls = []; // order: initial/props interleaved is irrelevant (see Registrate)
  final List<Call> itemPropCalls = [];
  Call? itemFactory;
  final List<String> mineable = [];
  final List<String> notes = [];
  bool verified = true;
  int order = -1;
}

class BlockEnumerator {
  BlockEnumerator(this.ip, this.createRoot);
  final Interp ip;
  final String createRoot;
  final List<BlockDef> blocks = [];

  SourceIndex get idx => ip.idx;

  JavaClass _cls(String simple) {
    final c = idx.bySimpleName(simple);
    if (c == null) throw StateError('class $simple not found');
    return c;
  }

  // ---------------------------------------------------------------------
  void enumerateAll() {
    _allBlocks();
    _fluidBlocks();
    _allPaletteBlocks();
  }

  void _addFromCalls(List<Call> calls, String source, JavaClass ctx) {
    BlockDef? d;
    var mode = 'block';
    for (final c in calls) {
      switch (c.name) {
        case 'block':
          if (d != null) {
            d.notes.add('second block() call in chain ignored');
            break;
          }
          final a = splitArgs(c.args);
          final key = ip.evalText(a[0], c.env, c.ctx ?? ctx);
          d = BlockDef(key is String ? key : '?${a[0]}', source);
          if (key is! String) {
            d.verified = false;
            d.notes.add('key not evaluable: ${a[0]}');
          }
          d.factoryExpr = a.length > 1 ? a[1] : null;
          d.factoryEnv = c.env;
          d.factoryCtx = c.ctx ?? ctx;
          break;
        case 'initialProperties':
          d?.initialCalls.add(c);
          break;
        case 'properties':
          if (mode == 'item') {
            d?.itemPropCalls.add(c);
          } else {
            d?.propCalls.add(c);
          }
          break;
        case 'item':
          if (d != null) {
            d.hasItem = true;
            d.itemFactory = c;
          }
          mode = 'item';
          break;
        case 'simpleItem':
          if (d != null) {
            d.hasItem = true;
            d.itemFactory = null;
          }
          break;
        case 'build':
          mode = 'block';
          break;
        case 'tag':
          if (mode == 'block' && d != null && c.args.contains('MINEABLE_WITH_')) {
            for (final m in RegExp(r'MINEABLE_WITH_(\w+)').allMatches(c.args)) {
              d.mineable.add(m.group(1)!.toLowerCase());
            }
          }
          break;
        case 'transform?':
          d?.notes.add('unresolved transform: ${c.args}');
          d?.verified = false;
          break;
        default:
          break;
      }
      if (d != null) d.calls.add(c);
    }
    if (d == null) {
      throw StateError('no block() in $source');
    }
    d.order = blocks.length;
    blocks.add(d);
  }

  // ---------------------------------------------------------------- AllBlocks
  void _allBlocks() {
    final cls = _cls('AllBlocks');
    for (final f in cls.fields) {
      if (!f.isStatic || f.init.isEmpty) continue;
      final init = f.init.trim();
      if (init.startsWith('new DyedBlockList')) {
        _dyed(f, cls);
      } else if (init.startsWith('new CopperBlockSet')) {
        _copperSet(f, cls);
      } else if (f.name == 'REGISTRATE') {
        continue;
      } else {
        final calls = ip.flatten(init, const {}, cls);
        if (calls.isEmpty || !calls.any((c) => c.name == 'block')) {
          if (f.type.contains('BlockEntry')) {
            throw StateError('AllBlocks.${f.name}: no block() found: $init');
          }
          continue;
        }
        _addFromCalls(calls, 'AllBlocks.${f.name}', cls);
      }
    }
  }

  void _dyed(JavaField f, JavaClass cls) {
    final m = RegExp(r'new\s+DyedBlockList\s*<[^>]*>\s*\(', dotAll: true).firstMatch(f.init)!;
    final op = m.end - 1;
    final cl = matchClose(f.init, op);
    final lamText = f.init.substring(op + 1, cl);
    final lam = parseLambda(lamText)!;
    final dye = idx.resolveClass('DyeColor', cls.file)!;
    final colours = ip.enumValues(dye)!;
    final an = ip.analyseBody(lam.body);
    final skipM = RegExp(r'if\s*\(\s*\w+\s*==\s*DyeColor\.(\w+)\s*\)\s*\{?\s*return\s+(\w+)\s*;').allMatches(lam.body);
    final skip = {for (final m in skipM) m.group(1)!};
    for (final col in colours) {
      if (skip.contains(col.name)) continue; // lambda returns an already registered block
      final env = <String, Bound>{};
      env[lam.params.first] = Bound('DyeColor.${col.name}', const {}, cls);
      ip.bindLocals(env, an.locals, cls);
      final calls = ip.flatten(an.ret ?? lam.body, env, cls);
      _addFromCalls(calls, 'AllBlocks.${f.name}[${col.name.toLowerCase()}]', cls);
    }
  }

  // --------------------------------------------------------------- copper sets
  void _copperSet(JavaField f, JavaClass cls) {
    final m = RegExp(r'new\s+CopperBlockSet\s*\(', dotAll: true).firstMatch(f.init)!;
    final cl = matchClose(f.init, m.end - 1);
    final args = splitArgs(f.init.substring(m.end, cl));
    // (REGISTRATE, name, endTexture, variants, [recipe], [onRegister])
    final name = ip.evalText(args[1], const {}, cls) as String;
    final variantsExpr = args[3];
    final variants = <String>[];
    if (variantsExpr.contains('DEFAULT_VARIANTS')) {
      variants.addAll(const ['BlockVariant', 'SlabVariant', 'StairVariant']);
    } else {
      for (final v in RegExp(r'(\w+Variant)\.INSTANCE').allMatches(variantsExpr)) {
        variants.add(v.group(1)!);
      }
    }
    final cbs = _cls('CopperBlockSet');
    const states = ['UNAFFECTED', 'EXPOSED', 'WEATHERED', 'OXIDIZED'];
    for (final waxed in const [false, true]) {
      for (final variant in variants) {
        final suffix = variant == 'BlockVariant' ? '' : (variant == 'SlabVariant' ? '_slab' : '_stairs');
        for (final st in states) {
          var key = '';
          if (waxed) key += 'waxed_';
          if (st != 'UNAFFECTED') key += '${st.toLowerCase()}_';
          key += name;
          if (suffix.isNotEmpty) {
            key = key.endsWith('s') ? key.substring(0, key.length - 1) : key;
          }
          key += suffix;
          final d = BlockDef(key, 'AllBlocks.${f.name}[$variant,$st,${waxed ? 'waxed' : 'plain'}]');
          final cn = variant == 'BlockVariant'
              ? (waxed ? 'Block' : 'WeatheringCopperFullBlock')
              : variant == 'SlabVariant'
                  ? (waxed ? 'SlabBlock' : 'WeatheringCopperSlabBlock')
                  : (waxed ? 'StairBlock' : 'WeatheringCopperStairBlock');
          d.className = cn;
          d.factoryExpr = '<copper:$variant>';
          d.factoryCtx = cbs;
          d.hasItem = true; // simpleItem()
          d.mineable.add('pickaxe');
          // initialProperties(() -> Blocks.COPPER_BLOCK.weathering().<state>())
          d.initialCalls.add(Call('initialProperties', '<copper:$st>', const {}, cbs));
          d.order = blocks.length;
          d.notes.add('CopperBlockSet: initial properties copied from vanilla ${st.toLowerCase()} copper block');
          blocks.add(d);
        }
      }
    }
  }

  // ------------------------------------------------------------ fluid blocks
  void _fluidBlocks() {
    final cls = _cls('AllFluids');
    for (final f in cls.fields) {
      if (!f.isStatic || f.init.isEmpty) continue;
      final calls = ip.flatten(f.init, const {}, cls);
      if (calls.isEmpty || !calls.any((c) => c.name == 'block')) continue;
      final first = calls.first;
      final key = ip.evalText(splitArgs(first.args).first, first.env, cls) as String;
      final d = BlockDef(key, 'AllFluids.${f.name}')
        ..className = 'LiquidBlock'
        ..hasItem = false
        ..factoryExpr = '<fluid-block>'
        ..factoryCtx = cls;
      d.initialCalls.add(Call('initialProperties', '<vanilla:WATER>', const {}, cls));
      d.propCalls.add(Call('properties', 'p -> p.noLootTable()', const {}, cls));
      var inBlock = false;
      for (final c in calls) {
        if (c.name == 'block') {
          inBlock = true;
        } else if (c.name == 'build') {
          inBlock = false;
        } else if (inBlock && c.name == 'properties') {
          d.propCalls.add(c);
        }
      }
      d.order = blocks.length;
      blocks.add(d);
    }
  }

  // ------------------------------------------------------------ palette blocks
  void _allPaletteBlocks() {
    final cls = _cls('AllPaletteBlocks');
    for (final f in cls.fields) {
      if (!f.isStatic || f.init.isEmpty || f.name == 'REGISTRATE') continue;
      final init = f.init.trim();
      final calls = ip.flatten(init, const {}, cls);
      if (!calls.any((c) => c.name == 'block')) {
        throw StateError('AllPaletteBlocks.${f.name}: no block() in $init');
      }
      _addFromCalls(calls, 'AllPaletteBlocks.${f.name}', cls);
    }
    _stoneTypes();
  }

  void _stoneTypes() {
    final st = _cls('AllPaletteStoneTypes');
    final pattern = _cls('PaletteBlockPattern');
    final partial = _cls('PaletteBlockPartial');
    final dyeless = <String, Bound>{};
    // the pattern arrays
    final patternFields = {for (final f in pattern.fields) f.name: f};
    List<String> parseNames(String init) {
      final m = RegExp(r'\{(.*)\}', dotAll: true).firstMatch(init);
      return splitArgs(m!.group(1)!);
    }

    final vanillaRange = parseNames(patternFields['VANILLA_RANGE']!.init);
    final standardRange = parseNames(patternFields['STANDARD_RANGE']!.init);
    final partialFields = {for (final f in partial.fields) f.name: f};
    List<String> partialsOf(String ptn) {
      // create("cut", PREFIX, ALL_PARTIALS) etc. -> list of partial constants
      final init = _patternInit(pattern, ptn);
      final m = RegExp(r'create\s*\(').firstMatch(init)!;
      final cl = matchClose(init, m.end - 1);
      final a = splitArgs(init.substring(m.end, cl));
      final rest = a.skip(2).toList();
      final out = <String>[];
      for (final r in rest) {
        if (partialFields.containsKey(r) && partialFields[r]!.type.endsWith('[]')) {
          out.addAll(parseNames(partialFields[r]!.init));
        } else if (r.endsWith('PARTIALS')) {
          // referenced array
          final pf = partialFields[r];
          if (pf != null) out.addAll(parseNames(pf.init));
        } else {
          out.add(r);
        }
      }
      return out;
    }

    String createName(String ptn, String variant) {
      final init = _patternInit(pattern, ptn);
      final m = RegExp(r'create\s*\(').firstMatch(init)!;
      final cl = matchClose(init, m.end - 1);
      final a = splitArgs(init.substring(m.end, cl));
      final id = ip.evalText(a[0], const {}, pattern) as String;
      final nameType = a[1];
      if (nameType == 'WRAP') {
        final split = id.split('_');
        if (split.length == 2) return '${split[0]}_${variant}_${split[1]}';
      }
      return nameType == 'SUFFIX' ? '${variant}_$id' : '${id}_$variant';
    }

    String patternFactory(String ptn) {
      final init = _patternInit(pattern, ptn);
      final bm = RegExp(r'\.block\(([\w:]+)\)').firstMatch(init);
      if (bm != null) return bm.group(1)!.split('::').first;
      return 'Block';
    }

    final partialClass = {'STAIR': 'StairBlock', 'SLAB': 'SlabBlock', 'UNIQUE_SLAB': 'SlabBlock', 'WALL': 'WallBlock'};
    final partialName = {'STAIR': 'stairs', 'SLAB': 'slab', 'UNIQUE_SLAB': 'slab', 'WALL': 'wall'};

    for (final ec in st.enumConstants) {
      final id = ec.name.toLowerCase();
      final args = splitArgs(ec.args);
      final range = args[0] == 'VANILLA_RANGE' ? vanillaRange : standardRange;
      String baseExpr;
      if (args[0] == 'VANILLA_RANGE') {
        // r -> () -> Blocks.GRANITE
        baseExpr = 'vanilla:${RegExp(r'Blocks\.(\w+)').firstMatch(args[1])!.group(1)}';
      } else {
        // custom stone block: r.paletteStoneBlock("asurine", () -> Blocks.DEEPSLATE, true, true).properties(...).register()
        final lam = parseLambda(args[1])!;
        final calls = ip.flatten(lam.body, const {}, st);
        _addFromCalls(calls, 'AllPaletteStoneTypes.$id', st);
        baseExpr = 'self:$id';
      }
      for (final p in range) {
        final pName = createName(p, id);
        final cn = patternFactory(p);
        final ptnSrc = 'palette:$id/$p';
        final d = BlockDef(pName, ptnSrc)
          ..className = cn
          ..hasItem = true
          ..factoryExpr = '<palette:$cn>'
          ..factoryCtx = pattern;
        d.mineable.add('pickaxe');
        d.initialCalls.add(Call('initialProperties', '<$baseExpr>', const {}, st));
        d.order = blocks.length;
        blocks.add(d);
        // partials
        for (final pc in partialsOf(p)) {
          final patternName = _nonPlural(pName);
          final pn = '${patternName}_${partialName[pc]}';
          final pd = BlockDef(pn, '$ptnSrc/$pc')
            ..className = partialClass[pc]
            ..hasItem = true
            ..factoryExpr = '<partial:$pc>'
            ..factoryCtx = partial;
          pd.mineable.add('pickaxe');
          pd.initialCalls.add(Call('initialProperties', '<ofFullCopy:$pName>', const {}, partial));
          if (pc == 'WALL') pd.propCalls.add(Call('properties', 'p -> p.forceSolidOn()', const {}, partial));
          pd.order = blocks.length;
          blocks.add(pd);
        }
      }
    }
    dyeless.clear();
  }

  String _nonPlural(String s) => s.endsWith('s') ? s.substring(0, s.length - 1) : s;

  String _patternInit(JavaClass pattern, String name) {
    final f = pattern.field(name)!;
    return f.init;
  }
}

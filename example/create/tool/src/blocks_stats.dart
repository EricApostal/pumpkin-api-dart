// Block / item base statistics interpreter (BlockBehaviour.Properties / Item.Properties).
import 'expr.dart';
import 'interp.dart';
import 'java.dart';

class BlockStats {
  double hardness = 0;
  double resistance = 0;
  bool requiresTool = false;
  int light = 0;
  bool lightDynamic = false;
  String sound = 'STONE';
  String mapColor = 'NONE';
  bool noOcclusion = false;
  bool noCollision = false;
  bool isAir = false;
  bool? redstoneConductor;
  bool? suffocating;
  bool? viewBlocking;
  bool forceSolidOn = false;
  bool forceSolidOff = false;
  String pushReaction = 'NORMAL';
  bool noLootTable = false;
  bool ignitedByLava = false;
  bool randomTicks = false;
  bool replaceable = false;
  bool dynamicShape = false;
  double friction = 0.6;
  double speedFactor = 1.0;
  double jumpFactor = 1.0;
  final List<String> issues = [];

  BlockStats copy() {
    final c = BlockStats()
      ..hardness = hardness
      ..resistance = resistance
      ..requiresTool = requiresTool
      ..light = light
      ..lightDynamic = lightDynamic
      ..sound = sound
      ..mapColor = mapColor
      ..noOcclusion = noOcclusion
      ..noCollision = noCollision
      ..isAir = isAir
      ..redstoneConductor = redstoneConductor
      ..suffocating = suffocating
      ..viewBlocking = viewBlocking
      ..forceSolidOn = forceSolidOn
      ..forceSolidOff = forceSolidOff
      ..pushReaction = pushReaction
      ..noLootTable = noLootTable
      ..ignitedByLava = ignitedByLava
      ..randomTicks = randomTicks
      ..replaceable = replaceable
      ..dynamicShape = dynamicShape
      ..friction = friction
      ..speedFactor = speedFactor
      ..jumpFactor = jumpFactor;
    c.issues.addAll(issues);
    return c;
  }
}

class ItemStats {
  int maxStack = 64;
  int? durability;
  bool fireResistant = false;
  String rarity = 'COMMON';
  bool food = false;
  String? foodDesc;
  final List<String> components = [];
  final List<String> issues = [];
  int? burnTime;
  ItemStats copy() {
    final c = ItemStats()
      ..maxStack = maxStack
      ..durability = durability
      ..fireResistant = fireResistant
      ..rarity = rarity
      ..food = food
      ..foodDesc = foodDesc
      ..burnTime = burnTime;
    c.components.addAll(components);
    c.issues.addAll(issues);
    return c;
  }
}

/// A single `.name(args)` applied to a Properties object.
class PCall {
  PCall(this.name, this.args, this.env, this.ctx);
  final String name;
  final String args;
  final Map<String, Bound> env;
  final JavaClass? ctx;
}

class StatsEngine {
  StatsEngine(this.ip, this.blockStatsByKey);
  final Interp ip;
  final Map<String, BlockStats> blockStatsByKey;
  SourceIndex get idx => ip.idx;

  final Map<String, BlockStats?> _vanilla = {};

  /// AllBlocks / AllPaletteBlocks field name -> registered block key.
  final Map<String, String> fieldKeys = {};

  // ------------------------------------------------------------ vanilla
  JavaClass get _blocksCls => idx.bySimpleName('Blocks')!;

  BlockStats? vanilla(String field, {String? color}) {
    final ck = color == null ? field : '$field#$color';
    if (_vanilla.containsKey(ck)) return _vanilla[ck];
    _vanilla[ck] = null;
    final f = _blocksCls.field(field);
    if (f == null) return null;
    final init = f.init;
    if (f.type.contains('ColorCollection') && color != null) {
      final lm = RegExp(r'color\s*->\s*').firstMatch(init);
      final i = init.indexOf('BlockBehaviour.Properties');
      if (lm != null && i > 0) {
        final ch = parseChain(init.substring(i));
        final s = BlockStats();
        for (final c in ch.calls.skip(1)) {
          applyBlock(s, PCall(c.key, c.value, {'color': Bound('DyeColor.$color', const {}, _blocksCls)}, _blocksCls));
        }
        _vanilla[ck] = s;
        return s;
      }
    }
    if (f.type.contains('WeatheringCopperCollection')) {
      // all copper-family collections derive from COPPER_BLOCK's lambda
      final s = BlockStats()
        ..hardness = 3
        ..resistance = 6
        ..requiresTool = true
        ..sound = 'COPPER'
        ..mapColor = 'COLOR_ORANGE';
      s.issues.add('copper collection: values taken from the state lambda in Blocks.java (unaffected state)');
      _vanilla[ck] = s;
      return s;
    }
    final i = init.indexOf('BlockBehaviour.Properties');
    if (i < 0) {
      final s = BlockStats();
      s.issues.add('vanilla $field: no Properties expression found');
      _vanilla[ck] = s;
      return s;
    }
    final ch = parseChain(init.substring(i));
    final s = BlockStats();
    final calls = ch.calls;
    var start = 0;
    if (calls.isNotEmpty && (calls.first.key == 'ofFullCopy' || calls.first.key == 'ofLegacyCopy')) {
      final arg = calls.first.value.trim();
      final m = RegExp(r'^(?:Blocks\.)?(\w+)$').firstMatch(arg);
      final base = m == null ? null : vanilla(m.group(1)!);
      if (base != null) {
        final c = base.copy();
        _copyInto(s, c);
      } else {
        s.issues.add('vanilla $field copies unknown `$arg`');
      }
      start = 1;
    } else if (calls.isNotEmpty && calls.first.key == 'of') {
      start = 1;
    }
    for (var k = start; k < calls.length; k++) {
      applyBlock(s, PCall(calls[k].key, calls[k].value, const {}, _blocksCls));
    }
    _vanilla[ck] = s;
    return s;
  }

  void _copyInto(BlockStats dst, BlockStats src) {
    dst
      ..hardness = src.hardness
      ..resistance = src.resistance
      ..requiresTool = src.requiresTool
      ..light = src.light
      ..lightDynamic = src.lightDynamic
      ..sound = src.sound
      ..mapColor = src.mapColor
      ..noOcclusion = src.noOcclusion
      ..noCollision = src.noCollision
      ..isAir = src.isAir
      ..redstoneConductor = src.redstoneConductor
      ..suffocating = src.suffocating
      ..viewBlocking = src.viewBlocking
      ..forceSolidOn = src.forceSolidOn
      ..forceSolidOff = src.forceSolidOff
      ..pushReaction = src.pushReaction
      ..noLootTable = src.noLootTable
      ..ignitedByLava = src.ignitedByLava
      ..randomTicks = src.randomTicks
      ..replaceable = src.replaceable
      ..dynamicShape = src.dynamicShape
      ..friction = src.friction
      ..speedFactor = src.speedFactor
      ..jumpFactor = src.jumpFactor;
    dst.issues.addAll(src.issues);
  }

  // ------------------------------------------------------- text helpers
  /// Follows identifier bindings to the underlying expression text.
  String resolveText(String text, Map<String, Bound> env, [int depth = 0]) {
    text = text.trim();
    if (depth > 10) return text;
    if (RegExp(r'^[A-Za-z_]\w*$').hasMatch(text)) {
      final b = env[text];
      if (b != null && !b.isBuilder) return resolveText(b.text, b.env, depth + 1);
    }
    return text;
  }

  String? _mapColorName(String arg, Map<String, Bound> env, JavaClass? ctx) {
    arg = resolveText(arg, env);
    final lam0 = parseLambda(arg);
    if (lam0 != null && lam0.params.isEmpty) {
      return _mapColorName(lam0.body.trim().replaceAll(RegExp(r';\s*$'), ''), env, ctx);
    }
    // `parent.get().defaultMapColor()` / `planks.defaultMapColor()` / `planks::defaultMapColor`
    final dm0 = RegExp(r'^(\w+)(?:\.get\(\))?\s*(?:\.defaultMapColor\(\)|::defaultMapColor)$').firstMatch(arg.replaceAll(RegExp(r'\s+'), ''));
    if (dm0 != null) {
      final target = resolveText(dm0.group(1)!, env);
      final tm = RegExp(r'^(?:\(\)\s*->\s*)?(?:Blocks\.(\w+)|(?:AllBlocks\.|AllPaletteBlocks\.)?(\w+))(?:\.get\(\))?$').firstMatch(target);
      if (tm != null) {
        if (tm.group(1) != null) {
          final v = vanilla(tm.group(1)!);
          if (v != null) return v.mapColor;
        } else {
          final key = fieldKeys[tm.group(2)!];
          final b = key == null ? null : blockStatsByKey[key];
          if (b != null) return b.mapColor;
        }
      }
      return 'from:$target';
    }
    final gm = RegExp(r'^(\w+)\.get\(\)$').firstMatch(arg);
    if (gm != null) {
      final bd = env[gm.group(1)!];
      if (bd != null && !bd.isBuilder) {
        final lam = parseLambda(bd.text);
        final inner = lam != null ? lam.body.trim().replaceAll(RegExp(r';\s*$'), '') : bd.text;
        return _mapColorName(inner, bd.env, bd.ctx ?? ctx);
      }
    }
    final m = RegExp(r'^MapColor\.(\w+)$').firstMatch(arg);
    if (m != null) return m.group(1);
    // dye colour
    final v = ip.evalText(arg, env, ctx);
    if (v is EnumVal && v.type == 'DyeColor') return 'dye:${v.name}';
    final dm = RegExp(r'^(\w+)(?:\.getMapColor\(\))?$').firstMatch(arg);
    if (dm != null) {
      final b = env[dm.group(1)!];
      if (b != null) {
        final vv = ip.evalText(b.text, b.env, b.ctx ?? ctx);
        if (vv is EnumVal && vv.type == 'DyeColor') return 'dye:${vv.name}';
      }
    }
    if (arg.contains('::defaultMapColor') || arg.contains('defaultMapColor')) return 'from:$arg';
    if (arg.contains('->')) return 'dynamic';
    return null;
  }

  /// Resolve an `initialProperties(...)` argument to a stats base.
  BlockStats? baseFor(Call c) {
    var arg = resolveText(c.args, c.env);
    // synthetic markers
    final sm = RegExp(r'^<(\w+):(\w+)>$').firstMatch(arg);
    if (sm != null) {
      final kind = sm.group(1)!;
      final v = sm.group(2)!;
      if (kind == 'vanilla') return vanilla(v)?.copy();
      if (kind == 'ofFullCopy' || kind == 'self') {
        final b = blockStatsByKey[v];
        return b?.copy();
      }
      if (kind == 'copper') {
        const mc = {'UNAFFECTED': 'COLOR_ORANGE', 'EXPOSED': 'TERRACOTTA_LIGHT_GRAY', 'WEATHERED': 'WARPED_STEM', 'OXIDIZED': 'WARPED_NYLIUM'};
        final s = BlockStats()
          ..hardness = 3
          ..resistance = 6
          ..requiresTool = true
          ..sound = 'COPPER'
          ..mapColor = mc[v] ?? 'COLOR_ORANGE';
        return s;
      }
      return null;
    }
    // SharedProperties::stone
    final mr = RegExp(r'^(\w+)::(\w+)$').firstMatch(arg);
    if (mr != null) {
      final cls = idx.resolveClass(mr.group(1)!, (c.ctx ?? _blocksCls).file, context: c.ctx);
      final meth = cls?.methods.where((m) => m.name == mr.group(2)).firstOrNull;
      if (meth != null) {
        final rm = RegExp(r'return\s+(.*?);', dotAll: true).firstMatch(meth.body);
        if (rm != null) return _baseFromExpr(rm.group(1)!, c.env, cls);
      }
      return null;
    }
    final lam = parseLambda(arg);
    if (lam != null) {
      return _baseFromExpr(lam.body.replaceFirst(RegExp(r'^\s*return\s+'), '').replaceAll(';', ''), c.env, c.ctx);
    }
    return _baseFromExpr(arg, c.env, c.ctx);
  }

  BlockStats? _baseFromExpr(String expr, Map<String, Bound> env, JavaClass? ctx) {
    expr = resolveText(expr.trim(), env);
    expr = expr.replaceAll(RegExp(r'\.get\(\)$'), '');
    var m = RegExp(r'^Blocks\.(\w+)\.pick\(DyeColor\.(\w+)\)$').firstMatch(expr);
    if (m != null) return vanilla(m.group(1)!, color: m.group(2))?.copy();
    m = RegExp(r'^Blocks\.(\w+)(?:\.weathering\(\)\.\w+\(\))?$').firstMatch(expr);
    if (m != null) return vanilla(m.group(1)!)?.copy();
    m = RegExp(r'^(\w+)$').firstMatch(expr);
    if (m != null && env.containsKey(m.group(1))) {
      final b = env[m.group(1)!]!;
      return _baseFromExpr(b.text, b.env, b.ctx);
    }
    return null;
  }

  // ------------------------------------------------ Properties call lists
  /// Expands an argument of `.properties(arg)` into the individual property calls.
  List<PCall>? expandPropertiesArg(Call c, {int depth = 0}) {
    if (depth > 5) return null;
    var arg = c.args.trim();
    arg = resolveText(arg, c.env);
    // method ref  X::name
    final mr = RegExp(r'^([\w.]+)::(\w+)$').firstMatch(arg);
    if (mr != null) {
      final q = mr.group(1)!;
      if (q.endsWith('Properties')) return [PCall(mr.group(2)!, '', c.env, c.ctx)];
      final cls = idx.resolveClass(q, (c.ctx ?? _blocksCls).file, context: c.ctx);
      final found = cls == null ? null : ip.findMethod(null, mr.group(2)!, cls);
      if (found != null) {
        final names = ip.paramNames(found.method.params);
        final an = ip.analyseBody(found.method.body);
        if (an.ret != null && names.length == 1) {
          return _chainCalls(an.ret!, names.first, c.env, found.cls);
        }
      }
      return null;
    }
    final lam = parseLambda(arg);
    if (lam == null || lam.params.isEmpty) return null;
    final an = ip.analyseBody(lam.body);
    var expr = an.ret ?? lam.body;
    final env2 = Map<String, Bound>.from(c.env);
    ip.bindLocals(env2, an.locals, c.ctx ?? _blocksCls);
    // `cond ? p.x() : p`
    final q = splitTop(expr, '?');
    if (q.length == 2) {
      final rest = splitTop(q[1], ':');
      if (rest.length == 2) {
        final cond = ip.evalText(q[0], env2, c.ctx);
        if (cond is bool) expr = cond ? rest[0] : rest[1];
      }
    }
    if (expr.trim() == lam.params.first) return <PCall>[];
    final r = _chainCalls(expr, lam.params.first, env2, c.ctx);
    return r;
  }

  List<PCall>? _chainCalls(String expr, String root, Map<String, Bound> env, JavaClass? ctx) {
    expr = expr.trim();
    final ch = parseChain(expr);
    if (ch.root == root) {
      return [for (final k in ch.calls) PCall(k.key, k.value, env, ctx)];
    }
    // ternary `cond ? p.x() : p`  -> unresolved
    return null;
  }

  // ------------------------------------------------------------- appliers
  double? _num(String s, Map<String, Bound> env, JavaClass? ctx) {
    final v = ip.evalText(s, env, ctx);
    return v is num ? v.toDouble() : null;
  }

  bool? _boolArg(String arg, Map<String, Bound> env, JavaClass? ctx) {
    final t = resolveText(arg, env);
    final mr = RegExp(r'::(always|never)$').firstMatch(t);
    if (mr != null) return mr.group(1) == 'always';
    final lam = parseLambda(t);
    if (lam == null) return null;
    final v = ip.evalText(lam.body, const {}, ctx);
    return v is bool ? v : null;
  }

  void applyBlock(BlockStats s, PCall c) {
    final a = splitArgs(c.args);
    switch (c.name) {
      case 'strength':
        final h = _num(a[0], c.env, c.ctx);
        final r = a.length > 1 ? _num(a[1], c.env, c.ctx) : h;
        if (h == null || r == null) {
          s.issues.add('strength(${c.args}) not evaluable');
        } else {
          s.hardness = h;
          s.resistance = r;
        }
        break;
      case 'destroyTime':
        final h = _num(a[0], c.env, c.ctx);
        if (h == null) {
          s.issues.add('destroyTime(${c.args}) not evaluable');
        } else {
          s.hardness = h;
        }
        break;
      case 'explosionResistance':
        final r = _num(a[0], c.env, c.ctx);
        if (r == null) {
          s.issues.add('explosionResistance(${c.args}) not evaluable');
        } else {
          s.resistance = r;
        }
        break;
      case 'instabreak':
        s.hardness = 0;
        s.resistance = 0;
        break;
      case 'requiresCorrectToolForDrops':
        s.requiresTool = true;
        break;
      case 'noOcclusion':
        s.noOcclusion = true;
        break;
      case 'noCollission':
      case 'noCollision':
        s.noCollision = true;
        break;
      case 'air':
        s.isAir = true;
        break;
      case 'noLootTable':
        s.noLootTable = true;
        break;
      case 'ignitedByLava':
        s.ignitedByLava = true;
        break;
      case 'randomTicks':
        s.randomTicks = true;
        break;
      case 'replaceable':
        s.replaceable = true;
        break;
      case 'dynamicShape':
        s.dynamicShape = true;
        break;
      case 'forceSolidOn':
        s.forceSolidOn = true;
        s.forceSolidOff = false;
        break;
      case 'forceSolidOff':
        s.forceSolidOff = true;
        s.forceSolidOn = false;
        break;
      case 'friction':
        s.friction = _num(a[0], c.env, c.ctx) ?? s.friction;
        break;
      case 'speedFactor':
        s.speedFactor = _num(a[0], c.env, c.ctx) ?? s.speedFactor;
        break;
      case 'jumpFactor':
        s.jumpFactor = _num(a[0], c.env, c.ctx) ?? s.jumpFactor;
        break;
      case 'pushReaction':
        s.pushReaction = a[0].split('.').last;
        break;
      case 'sound':
        final t = resolveText(a[0], c.env);
        final m = RegExp(r'^SoundType\.(\w+)$').firstMatch(t);
        s.sound = m != null ? m.group(1)! : 'custom';
        if (m == null) s.issues.add('custom sound type: ${t.length > 60 ? t.substring(0, 60) : t}');
        break;
      case 'mapColor':
        final n = _mapColorName(a[0], c.env, c.ctx);
        if (n == null) {
          s.issues.add('mapColor(${a[0]}) not evaluable');
        } else {
          s.mapColor = n;
        }
        break;
      case 'lightLevel':
        final t = resolveText(a[0], c.env);
        final lam = parseLambda(t);
        if (lam != null) {
          final v = ip.evalText(lam.body, const {}, c.ctx);
          if (v is int) {
            s.light = v;
            s.lightDynamic = false;
            break;
          }
          final ints = RegExp(r'(?<![\w.])(\d+)(?![\w.])').allMatches(lam.body).map((m) => int.parse(m.group(1)!)).where((x) => x <= 15).toList();
          s.light = ints.isEmpty ? 0 : ints.reduce((x, y) => x > y ? x : y);
          s.lightDynamic = true;
        } else {
          s.lightDynamic = true;
          s.light = 0;
          s.issues.add('lightLevel via method reference: $t (dynamic; max unknown)');
        }
        break;
      case 'isRedstoneConductor':
        s.redstoneConductor = _boolArg(a[0], c.env, c.ctx);
        if (s.redstoneConductor == null) s.issues.add('isRedstoneConductor not constant: ${a[0]}');
        break;
      case 'isSuffocating':
        s.suffocating = _boolArg(a[0], c.env, c.ctx);
        if (s.suffocating == null) s.issues.add('isSuffocating not constant: ${a[0]}');
        break;
      case 'isViewBlocking':
        s.viewBlocking = _boolArg(a[0], c.env, c.ctx);
        if (s.viewBlocking == null) s.issues.add('isViewBlocking not constant: ${a[0]}');
        break;
      // irrelevant to registration stats
      case 'instrument':
      case 'isValidSpawn':
      case 'emissiveRendering':
      case 'hasPostProcess':
      case 'offsetType':
      case 'overrideLootTable':
      case 'overrideDescription':
      case 'lootFrom':
      case 'setId':
      case 'noTerrainParticles':
      case 'ofFullCopy':
      case 'of':
      case 'liquid':
      case 'isBlockEntity':
      case 'requiresCorrectToolForDrops_':
      case 'rarity':
      case 'sandPaper':
      case 'ofLegacyCopy':
      case 'overrideDescriptionId':
      case 'useShapeForLightOcclusion':
      case 'pistonBehavior':
      case 'jumpFactor_':
        break;
      default:
        s.issues.add('unhandled Properties call `${c.name}(${c.args.length > 40 ? '${c.args.substring(0, 40)}..' : c.args})`');
    }
  }

  void applyItem(ItemStats s, PCall c) {
    final a = splitArgs(c.args);
    switch (c.name) {
      case 'stacksTo':
        final v = ip.evalText(a[0], c.env, c.ctx);
        if (v is int) {
          s.maxStack = v;
        } else {
          s.issues.add('stacksTo(${a[0]}) not evaluable');
        }
        break;
      case 'durability':
        final v = ip.evalText(a[0], c.env, c.ctx);
        if (v is int) {
          s.durability = v;
          s.maxStack = 1;
        } else {
          s.durability = -1;
          s.maxStack = 1;
          s.issues.add('durability(${a[0].length > 50 ? a[0].substring(0, 50) : a[0]}) not evaluable');
        }
        break;
      case 'fireResistant':
        s.fireResistant = true;
        break;
      case 'rarity':
        s.rarity = a[0].split('.').last;
        break;
      case 'food':
        s.food = true;
        s.foodDesc = c.args.replaceAll(RegExp(r'\s+'), ' ');
        break;
      case 'sword':
      case 'pickaxe':
      case 'axe':
      case 'shovel':
      case 'hoe':
      case 'tool':
      case 'humanoidArmor':
      case 'component':
      case 'attributes':
      case 'enchantable':
      case 'repairable':
      case 'useCooldown':
      case 'craftRemainder':
      case 'usingConvertsTo':
      case 'overrideDescription':
      case 'useBlockDescriptionPrefix':
      case 'setId':
      case 'jukeboxPlayable':
      case 'equippable':
      case 'trimMaterial':
        s.components.add('${c.name}(${c.args.replaceAll(RegExp(r"\s+"), " ")})');
        if (c.name == 'sword' || c.name == 'pickaxe' || c.name == 'axe' || c.name == 'shovel' || c.name == 'hoe' || c.name == 'humanoidArmor') {
          s.maxStack = 1;
          s.issues.add('${c.name}() sets durability from a tool/armor material (not evaluated)');
        }
        break;
      default:
        s.issues.add('unhandled Item.Properties call `${c.name}`');
    }
  }
}

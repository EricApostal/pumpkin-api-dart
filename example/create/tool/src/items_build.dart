// Item enumeration (registration order) + stats.
import 'blocks_build.dart';
import 'blocks_stats.dart';
import 'interp.dart';
import 'java.dart';

class ItemRecord {
  ItemRecord(this.key, this.source);
  final String key;
  final String source;
  String className = '?';
  String? qualified;
  bool isBlockItem = false;
  String? blockKey;
  ItemStats stats = ItemStats();
  final List<String> notes = [];
  bool verified = true;
  int order = -1;
}

class ItemEnumerator {
  ItemEnumerator(this.ip, this.stage, this.engine);
  final Interp ip;
  final BlockBuilderStage stage;
  final StatsEngine engine;
  SourceIndex get idx => ip.idx;

  final List<ItemRecord> items = [];

  JavaClass _cls(String n) => idx.bySimpleName(n)!;

  String? _q(JavaClass? c) => c == null ? null : '${c.file.package}.${c.qualifiedName}';

  List<ItemRecord> enumerate(List<BlockRecord> blocks) {
    // 1. AllBlocks block items
    bool blockItem(BlockRecord b) => b.def.hasItem;
    for (final b in blocks) {
      if (b.def.source.startsWith('AllBlocks.') && blockItem(b)) _blockItem(b);
    }
    // 2. AllItems
    _allItems();
    // 3. fluid buckets
    _fluidBuckets();
    // 4. palettes
    for (final b in blocks) {
      if (!b.def.source.startsWith('AllBlocks.') && !b.def.source.startsWith('AllFluids.') && blockItem(b)) _blockItem(b);
    }
    for (var i = 0; i < items.length; i++) {
      items[i].order = i;
    }
    return items;
  }

  void _blockItem(BlockRecord b) {
    final r = ItemRecord(b.key, b.def.source)
      ..isBlockItem = true
      ..blockKey = b.key;
    r.stats = b.item ?? ItemStats();
    r.className = 'BlockItem';
    r.qualified = _q(idx.bySimpleName('BlockItem'));
    final fac = b.def.itemFactory;
    if (fac != null && fac.args.trim().isNotEmpty) {
      final c = stage.classFromFactory(fac.args, fac.env, fac.ctx);
      if (c != null) {
        r.className = c.name;
        r.qualified = _q(c);
      } else {
        r.notes.add('item factory class not resolved: ${fac.args}');
        r.verified = false;
      }
    }
    for (final n in r.stats.issues) {
      r.notes.add(n);
    }
    items.add(r);
  }

  // ------------------------------------------------------------- AllItems
  void _allItems() {
    final cls = _cls('AllItems');
    for (final m in cls.members) {
      if (m.kind == 'field') {
        for (final f in parseFieldMember(m.text)) {
          if (!f.isStatic || f.init.isEmpty || f.name == 'REGISTRATE') continue;
          final calls = ip.flatten(f.init, const {}, cls);
          if (!calls.any((c) => c.name == 'item')) {
            if (f.type.contains('ItemEntry')) throw StateError('AllItems.${f.name}: no item() in ${f.init}');
            continue;
          }
          _addItem(calls, 'AllItems.${f.name}', cls);
        }
      } else if (m.kind == 'init' && m.text.contains('PackageStyles')) {
        _packages(cls);
      }
    }
  }

  void _packages(JavaClass allItems) {
    final ps = _cls('PackageStyles');
    final styles = ps.field('STYLES')!;
    final m = RegExp(r'ImmutableList\.of\((.*)\)\s*$', dotAll: true).firstMatch(styles.init.trim())!;
    for (final a in splitArgs(m.group(1)!)) {
      String type;
      int w, h;
      bool rare;
      final nm = RegExp(r'^new\s+PackageStyle\(\s*"(\w+)"\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*[\d.]+f?\s*,\s*(true|false)\s*\)$').firstMatch(a);
      if (nm != null) {
        type = nm.group(1)!;
        w = int.parse(nm.group(2)!);
        h = int.parse(nm.group(3)!);
        rare = nm.group(4) == 'true';
      } else {
        final rm = RegExp(r'^rare\(\s*"(\w+)"\s*\)$').firstMatch(a);
        if (rm == null) throw StateError('unknown PackageStyle expr $a');
        type = 'rare_${rm.group(1)}';
        w = 12;
        h = 10;
        rare = true;
      }
      final id = '${type}_package${rare ? '' : '_${w}x$h'}';
      final r = ItemRecord(id, 'AllItems.<PackageStyles ${type} ${w}x$h>')
        ..className = 'PackageItem';
      r.qualified = _q(idx.bySimpleName('PackageItem'));
      r.stats.maxStack = 1;
      items.add(r);
    }
  }

  void _addItem(List<Call> calls, String source, JavaClass ctx) {
    ItemRecord? r;
    final propCalls = <Call>[];
    Call? factory;
    int? burn;
    for (final c in calls) {
      switch (c.name) {
        case 'item':
          final a = splitArgs(c.args);
          final key = ip.evalText(a[0], c.env, c.ctx ?? ctx);
          r = ItemRecord(key is String ? key : '?${a[0]}', source);
          if (key is! String) {
            r.verified = false;
            r.notes.add('key not evaluable: ${a[0]}');
          }
          if (a.length > 1) {
            factory = Call('factory', a[1], c.env, c.ctx ?? ctx);
          }
          break;
        case 'properties':
          propCalls.add(c);
          break;
        case 'burnTime':
          final v = ip.evalText(c.args, c.env, c.ctx);
          burn = v is int ? v : null;
          break;
        case 'transform?':
          r?.notes.add('unresolved transform: ${c.args}');
          r?.verified = false;
          break;
        default:
          break;
      }
    }
    if (r == null) throw StateError('no item() in $source');
    final stats = ItemStats();
    for (final pc in propCalls) {
      final pcalls = engine.expandPropertiesArg(pc);
      if (pcalls == null) {
        r.notes.add('properties(${pc.args.replaceAll(RegExp(r"\s+"), " ")}) not expanded');
        r.verified = false;
        continue;
      }
      for (final x in pcalls) {
        _applyItem(stats, x, r);
      }
    }
    stats.burnTime = burn;
    if (factory != null) {
      final c = stage.classFromFactory(factory.args, factory.env, factory.ctx);
      if (c != null) {
        r.className = c.name;
        r.qualified = _q(c);
        _scanClass(c, stats, r);
      } else {
        r.className = '?';
        r.notes.add('item class not resolved from `${factory.args}`');
        r.verified = false;
      }
    }
    for (final n in stats.issues) {
      r.notes.add(n);
    }
    r.stats = stats;
    items.add(r);
  }

  void _applyItem(ItemStats s, PCall c, ItemRecord r) {
    if (c.name == 'sword' || c.name == 'pickaxe' || c.name == 'axe' || c.name == 'shovel' || c.name == 'hoe') {
      final a = splitArgs(c.args);
      final mat = _toolMaterialDurability(a[0], c);
      s.maxStack = 1;
      if (mat != null) {
        s.durability = mat;
        s.components.add('${c.name}(${a[0]})');
        r.notes.add('durability $mat derived from tool material ${a[0]}');
      } else {
        s.durability = -1;
        s.components.add('${c.name}(${a[0]})');
        r.notes.add('tool material durability not evaluated');
        r.verified = false;
      }
      return;
    }
    engine.applyItem(s, c);
  }

  int? _toolMaterialDurability(String expr, PCall c) {
    final q = expr.trim();
    final dot = q.lastIndexOf('.');
    if (dot < 0) return null;
    final cls = idx.resolveClass(q.substring(0, dot), (c.ctx ?? _cls('AllItems')).file, context: c.ctx);
    final f = cls?.field(q.substring(dot + 1));
    if (cls == null || f == null) return null;
    final m = RegExp(r'^new\s+ToolMaterial\((.*)\)$', dotAll: true).firstMatch(f.init.trim());
    if (m == null) return null;
    final args = splitArgs(m.group(1)!);
    final v = ip.evalText(args[1], const {}, cls);
    return v is int ? v : null;
  }

  void _scanClass(JavaClass c, ItemStats s, ItemRecord r) {
    JavaClass? k = c;
    var depth = 0;
    while (k != null && depth++ < 8) {
      if (!k.file.path.contains('/com/simibubi/create/')) break;
      for (final ct in k.ctors) {
        final m = RegExp(r'stacksTo\(\s*(\d+)\s*\)').firstMatch(ct.body);
        if (m != null) {
          s.maxStack = int.parse(m.group(1)!);
          r.notes.add('class ${k.name} constructor sets stacksTo(${m.group(1)})');
        }
        final d = RegExp(r'durability\(\s*(\d+)\s*\)').firstMatch(ct.body);
        if (d != null) {
          s.durability = int.parse(d.group(1)!);
          s.maxStack = 1;
          r.notes.add('class ${k.name} constructor sets durability(${d.group(1)})');
        }
        if (ct.body.contains('fireResistant()')) {
          s.fireResistant = true;
          r.notes.add('class ${k.name} constructor sets fireResistant');
        }
      }
      final sup = k.superName;
      k = sup == null ? null : idx.resolveClass(sup, k.file, context: k);
    }
  }

  // ------------------------------------------------------------- buckets
  void _fluidBuckets() {
    final cls = _cls('AllFluids');
    for (final f in cls.fields) {
      if (!f.isStatic || f.init.isEmpty) continue;
      final calls = ip.flatten(f.init, const {}, cls);
      if (calls.isEmpty) continue;
      final first = calls.first;
      if (!(first.name == 'standardFluid' || first.name == 'fluid')) continue;
      if (!calls.any((c) => c.name == 'bucket')) continue;
      final name = ip.evalText(splitArgs(first.args).first, first.env, cls) as String;
      final r = ItemRecord('${name}_bucket', 'AllFluids.${f.name}')..className = 'BucketItem';
      r.qualified = _q(idx.bySimpleName('BucketItem'));
      r.stats.maxStack = 1;
      r.notes.add('Registrate FluidBuilder.bucket(): craftRemainder(bucket), stacksTo(1)');
      items.add(r);
    }
  }
}

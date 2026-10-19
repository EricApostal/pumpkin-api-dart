// Turns enumerated BlockDefs into fully resolved block records.
import 'dart:convert';
import 'dart:io';

import 'blocks_enum.dart';
import 'blocks_props.dart';
import 'blocks_stats.dart';
import 'expr.dart';
import 'interp.dart';
import 'java.dart';

class BlockRecord {
  BlockRecord(this.def);
  final BlockDef def;
  String get key => def.key;
  String className = '?';
  String? classQualified;
  PropResult props = PropResult();
  BlockStats stats = BlockStats();
  ItemStats? item;
  double? stressImpact;
  double? stressCapacity;
  final List<String> notes = [];
  bool verified = true;
  // json cross-check
  Map<String, Set<String>>? jsonProps;
  bool? jsonAgrees;
  int get stateCount => props.props.values.fold(1, (a, p) => a * (p.values.isEmpty ? 1 : p.values.length));
  bool get waterlogged => props.props.containsKey('waterlogged');
}

class BlockBuilderStage {
  BlockBuilderStage(this.ip, this.createRoot);
  final Interp ip;
  final String createRoot;
  late final PropResolver props = PropResolver(ip);
  final Map<String, BlockStats> statsByKey = {};
  late final StatsEngine engine = StatsEngine(ip, statsByKey);
  SourceIndex get idx => ip.idx;

  List<BlockRecord> build(List<BlockDef> defs) {
    final out = <BlockRecord>[];
    for (final d in defs) {
      final fm = RegExp(r'^(?:AllBlocks|AllPaletteBlocks)\.(\w+)$').firstMatch(d.source);
      if (fm != null) engine.fieldKeys[fm.group(1)!] = d.key;
    }
    for (final d in defs) {
      final r = BlockRecord(d);
      _resolveClass(r);
      _stats(r);
      _stress(r);
      _props(r);
      _item(r);
      r.verified = d.verified && r.props.verified && !r.notes.any((n) => n.startsWith('!'));
      statsByKey[r.key] = r.stats;
      out.add(r);
    }
    _crossCheck(out);
    return out;
  }

  // -------------------------------------------------------------- class
  void _resolveClass(BlockRecord r) {
    final d = r.def;
    JavaClass? cls;
    if (d.className != null) {
      cls = idx.bySimpleName(d.className!);
      r.className = d.className!;
    } else if (d.factoryExpr != null) {
      cls = _classFromFactory(d.factoryExpr!, d.factoryEnv, d.factoryCtx, 0);
      r.className = cls?.name ?? '?';
    }
    if (cls == null) {
      r.notes.add('!block class not resolved from `${d.factoryExpr}`');
      r.verified = false;
    }
    d.cls = cls;
    r.classQualified = cls == null ? null : '${cls.file.package}.${cls.qualifiedName}';
  }

  JavaClass? classFromFactory(String expr, Map<String, Bound> env, JavaClass? ctx) => _classFromFactory(expr, env, ctx, 0);

  JavaClass? _classFromFactory(String expr, Map<String, Bound> env, JavaClass? ctx, int depth) {
    if (depth > 6 || ctx == null) return null;
    expr = expr.trim();
    // bound parameter
    if (RegExp(r'^\w+$').hasMatch(expr) && env.containsKey(expr)) {
      final b = env[expr]!;
      return _classFromFactory(b.text, b.env, b.ctx ?? ctx, depth + 1);
    }
    // Foo::new / Foo::method
    final mr = RegExp(r'^([\w.]+)::(\w+)$').firstMatch(expr);
    if (mr != null) {
      var cls = idx.resolveClass(mr.group(1)!, ctx.file, context: ctx);
      if (cls == null && mr.group(1)!.contains('.')) {
        // Class.STATIC_FIELD::method -> use the field's declared type
        final q = mr.group(1)!;
        final owner = idx.resolveClass(q.substring(0, q.lastIndexOf('.')), ctx.file, context: ctx);
        final fld = owner?.field(q.substring(q.lastIndexOf('.') + 1));
        if (owner != null && fld != null) cls = idx.resolveClass(fld.type, owner.file, context: owner);
      }
      if (cls == null) return null;
      if (mr.group(2) == 'new') return cls;
      return _classFromStatic(cls, mr.group(2)!);
    }
    // call returning a factory: Foo.ofType(X) / helper(X)
    if (!expr.contains('->') && !expr.contains('::')) {
      final ch0 = parseChain(expr);
      if (ch0.calls.length == 1 && ch0.root != 'new') {
        final found = ip.findMethod(ch0.root.isEmpty ? null : ch0.root, ch0.calls.first.key, ctx, argc: splitArgs(ch0.calls.first.value).length);
        if (found != null) {
          final an = ip.analyseBody(found.method.body);
          final menv = <String, Bound>{};
          final names = ip.paramNames(found.method.params);
          final args = splitArgs(ch0.calls.first.value);
          for (var i = 0; i < names.length && i < args.length; i++) {
            menv[names[i]] = Bound(args[i], env, ctx);
          }
          if (an.ret != null) {
            final c = _classFromFactory(an.ret!, menv, found.cls, depth + 1);
            if (c != null) return c;
          }
          return found.cls;
        }
      }
    }
    final lam = parseLambda(expr);
    if (lam != null) {
      var body = lam.body.trim();
      final rm = RegExp(r'return\s+(.*?);', dotAll: true).firstMatch(body);
      if (rm != null) body = rm.group(1)!;
      body = body.replaceAll(RegExp(r';\s*$'), '').trim();
      final nm = RegExp(r'^new\s+([\w.]+)\s*(?:<[^>]*>)?\s*\(').firstMatch(body);
      if (nm != null) return idx.resolveClass(nm.group(1)!, ctx.file, context: ctx);
      final ch = parseChain(body);
      if (ch.calls.length == 1) {
        // Foo.method(p) or helper(p)
        final q = ch.root;
        if (q.isNotEmpty) {
          final cls = idx.resolveClass(q, ctx.file, context: ctx);
          if (cls != null) return _classFromStatic(cls, ch.calls.first.key);
        } else {
          final found = ip.findMethod(null, ch.calls.first.key, ctx);
          if (found != null) return _classFromMethod(found.method, found.cls);
        }
      }
      // delegated to a bound factory: e.g. `p -> factory.apply(p)`
      final fm = RegExp(r'^(\w+)\.apply\(').firstMatch(body);
      if (fm != null && env.containsKey(fm.group(1))) {
        return _classFromFactory(fm.group(1)!, env, ctx, depth + 1);
      }
    }
    return null;
  }

  JavaClass? _classFromStatic(JavaClass cls, String method) {
    final found = ip.findMethod(null, method, cls);
    if (found == null) return cls;
    return _classFromMethod(found.method, found.cls) ?? cls;
  }

  JavaClass? _classFromMethod(JavaMethod m, JavaClass owner) {
    final nm = RegExp(r'new\s+([\w.]+)\s*(?:<[^>]*>)?\s*\(').firstMatch(m.body);
    if (nm != null) {
      final c = idx.resolveClass(nm.group(1)!, owner.file, context: owner);
      if (c != null) return c;
    }
    final rt = m.returnType;
    if (rt.isNotEmpty) return idx.resolveClass(rt, owner.file, context: owner);
    return owner;
  }

  // -------------------------------------------------------------- stats
  void _stats(BlockRecord r) {
    final d = r.def;
    var s = BlockStats();
    if (d.initialCalls.isNotEmpty) {
      final base = engine.baseFor(d.initialCalls.last);
      if (base == null) {
        r.notes.add('!initialProperties not resolved: ${d.initialCalls.last.args.replaceAll(RegExp(r"\s+"), " ")}');
      } else {
        s = base;
      }
    }
    for (final pc in d.propCalls) {
      final calls = engine.expandPropertiesArg(pc);
      if (calls == null) {
        r.notes.add('properties(${pc.args.replaceAll(RegExp(r"\s+"), " ").substring(0, pc.args.length.clamp(0, 50))}) not expanded');
        continue;
      }
      for (final c in calls) {
        engine.applyBlock(s, c);
      }
    }
    for (final i in s.issues) {
      r.notes.add('stats: $i');
    }
    r.stats = s;
  }

  void _stress(BlockRecord r) {
    for (final c in r.def.calls) {
      if (c.name == 'stress:impact' || c.name == 'stress:capacity') {
        final v = ip.evalText(c.args, c.env, c.ctx);
        if (v is num) {
          if (c.name == 'stress:impact') {
            r.stressImpact = v.toDouble();
          } else {
            r.stressCapacity = v.toDouble();
          }
        } else {
          r.notes.add('stress value not evaluable: ${c.args}');
        }
      }
    }
  }

  // --------------------------------------------------------- properties
  void _props(BlockRecord r) {
    final cls = r.def.cls;
    if (cls == null) return;
    r.props = props.resolve(cls);
    for (final n in r.props.notes) {
      r.notes.add('props: $n');
    }
  }

  // --------------------------------------------------------------- item
  void _item(BlockRecord r) {
    final d = r.def;
    if (!d.hasItem) return;
    final it = ItemStats();
    for (final pc in d.itemPropCalls) {
      final calls = engine.expandPropertiesArg(pc);
      if (calls == null) {
        r.notes.add('item properties(${pc.args.length > 40 ? pc.args.substring(0, 40) : pc.args}) not expanded');
        continue;
      }
      for (final c in calls) {
        engine.applyItem(it, c);
      }
    }
    // item class overrides (constructors passing stacksTo etc.)
    final fac = d.itemFactory;
    if (fac != null && fac.args.trim().isNotEmpty) {
      final ic = _classFromFactory(fac.args, fac.env, fac.ctx, 0);
      if (ic != null) {
        _scanItemClass(ic, it, r.notes);
      }
    }
    for (final i in it.issues) {
      r.notes.add('item: $i');
    }
    r.item = it;
  }

  void _scanItemClass(JavaClass c, ItemStats it, List<String> notes) {
    JavaClass? k = c;
    var depth = 0;
    while (k != null && depth++ < 6) {
      if (!k.file.path.contains('/com/simibubi/create/')) break;
      for (final ct in k.ctors) {
        final m = RegExp(r'stacksTo\(\s*(\d+)\s*\)').firstMatch(ct.body);
        if (m != null) {
          it.maxStack = int.parse(m.group(1)!);
          notes.add('item class ${k.name} constructor sets stacksTo(${m.group(1)})');
        }
      }
      final s = k.superName;
      k = s == null ? null : idx.resolveClass(s, k.file, context: k);
    }
  }

  // ---------------------------------------------------- JSON cross-check
  void _crossCheck(List<BlockRecord> recs) {
    final dir = Directory('$createRoot/src/generated/resources/assets/create/blockstates');
    for (final r in recs) {
      final f = File('${dir.path}/${r.key}.json');
      if (!f.existsSync()) {
        r.notes.add('no blockstate JSON');
        continue;
      }
      final js = jsonDecode(f.readAsStringSync());
      final jp = <String, Set<String>>{};
      void addKey(String k) {
        if (k.isEmpty) return;
        for (final part in k.split(',')) {
          final eq = part.indexOf('=');
          if (eq < 0) continue;
          jp.putIfAbsent(part.substring(0, eq), () => {}).add(part.substring(eq + 1));
        }
      }

      void walkWhen(dynamic w) {
        if (w is Map) {
          w.forEach((k, v) {
            if (k == 'OR' || k == 'AND') {
              if (v is List) {
                for (final e in v) {
                  walkWhen(e);
                }
              }
            } else {
              jp.putIfAbsent(k as String, () => {}).addAll(v.toString().split('|'));
            }
          });
        }
      }

      if (js is Map) {
        final variants = js['variants'];
        if (variants is Map) {
          for (final k in variants.keys) {
            addKey(k as String);
          }
        }
        final mp = js['multipart'];
        if (mp is List) {
          for (final p in mp) {
            if (p is Map && p['when'] != null) walkWhen(p['when']);
          }
        }
      }
      r.jsonProps = jp;
      var agree = true;
      final javaProps = r.props.props;
      for (final e in jp.entries) {
        final p = javaProps[e.key];
        if (p == null) {
          r.notes.add('!JSON uses property `${e.key}` which Java does not define');
          agree = false;
          continue;
        }
        final extra = e.value.difference(p.values.toSet());
        if (extra.isNotEmpty) {
          r.notes.add('!JSON values $extra for `${e.key}` not in Java values ${p.values}');
          agree = false;
        }
      }
      // properties missing in JSON are fine (forAllStatesExcept) but if JSON is variant-based
      // and covers a property with fewer values, report softly
      for (final e in jp.entries) {
        final p = javaProps[e.key];
        if (p != null && e.value.length < p.values.length) {
          // collapsed models (e.g. wall sides) are normal; not reported
        }
      }
      r.jsonAgrees = agree;
    }
  }
}

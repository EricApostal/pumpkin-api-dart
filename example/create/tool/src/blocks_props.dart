// Block state property resolver: walks `createBlockStateDefinition` /
// `registerDefaultState` through the Create and vanilla class hierarchies.
import 'expr.dart';
import 'interp.dart';
import 'java.dart';

class PropDef {
  PropDef(this.name, this.kind, this.values, {this.enumCls, this.source = '', this.verified = true, this.note});
  final String name;
  final String kind; // bool | int | enum
  final List<String> values;
  final JavaClass? enumCls;
  final String source; // where it was declared
  bool verified;
  String? note;
  PropDef copy() => PropDef(name, kind, values, enumCls: enumCls, source: source, verified: verified, note: note);
}

class PropResult {
  final Map<String, PropDef> props = {}; // keyed by name (insertion = discovery order)
  final Map<String, String> defaults = {};
  final List<String> notes = [];
  bool verified = true;
  List<PropDef> get sorted => (props.values.toList()..sort((a, b) => a.name.compareTo(b.name)));
}

class PropResolver {
  PropResolver(this.ip);
  final Interp ip;
  SourceIndex get idx => ip.idx;
  final Map<String, Map<String, PropDef>> _collectCache = {};
  final Map<String, PropDef?> _fieldCache = {};

  PropResult resolve(JavaClass cls) {
    final r = PropResult();
    final notes = <String>[];
    final props = _collect(cls, 0, notes);
    r.props.addAll({for (final e in props.entries) e.key: e.value.copy()});
    r.notes.addAll(notes);
    for (final p in r.props.values) {
      if (!p.verified) r.verified = false;
    }
    _defaults(cls, r);
    return r;
  }

  // ------------------------------------------------------------ collection
  JavaClass? _super(JavaClass c) {
    final s = c.superName;
    if (s == null) return null;
    return idx.resolveClass(s, c.file, context: c);
  }

  Map<String, PropDef> _collect(JavaClass c, int depth, List<String> notes) {
    final key = '${c.file.path}#${c.qualifiedName}';
    final hit = _collectCache[key];
    if (hit != null) return hit;
    final out = <String, PropDef>{};
    if (depth > 12) return out;
    JavaMethod? m;
    for (final x in c.methods) {
      if (x.name == 'createBlockStateDefinition') {
        m = x;
        break;
      }
    }
    final callsSuper = m == null || m.body.contains('super.createBlockStateDefinition');
    if (callsSuper) {
      final parent = _super(c);
      if (parent != null) out.addAll(_collect(parent, depth + 1, notes));
    }
    if (m != null) {
      final body = m.body;
      for (final am in RegExp(r'\badd\s*\(').allMatches(body)) {
        final op = am.end - 1;
        final cl = matchClose(body, op);
        if (cl < 0) continue;
        final prefix = body.substring((am.start - 1).clamp(0, body.length), am.start);
        if (prefix != '.' && prefix != ' ' && prefix != '\n' && prefix != '\t') continue;
        for (final a in splitArgs(body.substring(op + 1, cl))) {
          final p = resolveProp(a, c);
          if (p == null) {
            notes.add('${c.name}: unresolved property expression `$a`');
            out['?$a'] = PropDef('?$a', 'unknown', const [], verified: false, note: 'unresolved in ${c.name}');
          } else {
            out[p.name] = p;
          }
        }
      }
    }
    _collectCache[key] = out;
    return out;
  }

  // ------------------------------------------------------- property exprs
  PropDef? resolveProp(String expr, JavaClass ctx, [int depth = 0]) {
    if (depth > 8) return null;
    expr = expr.trim();
    if (expr.contains('(') || expr.contains('[')) return null;
    final parts = expr.split('.');
    final name = parts.last;
    final qual = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : '';
    JavaField? f;
    JavaClass? owner;
    if (qual.isEmpty) {
      final r = _findFieldInScope(name, ctx);
      f = r?.$1;
      owner = r?.$2;
      if (f == null) {
        // static imports
        for (final si in ctx.file.staticImports) {
          final dot = si.lastIndexOf('.');
          final member = si.substring(dot + 1);
          if (member == name || member == '*') {
            final cc = _classByFqn(si.substring(0, dot));
            if (cc != null) {
              final rr = _fieldInChain(cc, name, 0);
              if (rr != null) {
                f = rr.$1;
                owner = rr.$2;
                break;
              }
            }
          }
        }
      }
    } else {
      final qc = idx.resolveClass(qual, ctx.file, context: ctx);
      if (qc != null) {
        final rr = _fieldInChain(qc, name, 0);
        f = rr?.$1;
        owner = rr?.$2;
      }
    }
    if (f == null || owner == null) return null;
    final key = '${owner.file.path}#${owner.qualifiedName}.${f.name}';
    if (_fieldCache.containsKey(key)) return _fieldCache[key];
    _fieldCache[key] = null; // cycle guard
    final p = _parseDecl(f, owner, depth);
    _fieldCache[key] = p;
    return p;
  }

  JavaClass? _classByFqn(String fqn) {
    final f = idx.fileForFqn(fqn);
    if (f != null) return f.classes.where((c) => fqn.endsWith('.${c.name}')).firstOrNull;
    final i = fqn.lastIndexOf('.');
    if (i > 0) {
      final outer = _classByFqn(fqn.substring(0, i));
      if (outer != null) {
        for (final n in outer.nested) {
          if (n.name == fqn.substring(i + 1)) return n;
        }
      }
    }
    return null;
  }

  (JavaField, JavaClass)? _findFieldInScope(String name, JavaClass ctx) {
    JavaClass? c = ctx;
    while (c != null) {
      final r = _fieldInChain(c, name, 0);
      if (r != null) return r;
      c = c.outer;
    }
    return null;
  }

  (JavaField, JavaClass)? _fieldInChain(JavaClass c, String name, int depth) {
    if (depth > 10) return null;
    final f = c.field(name);
    if (f != null) return (f, c);
    final s = _super(c);
    if (s != null) {
      final r = _fieldInChain(s, name, depth + 1);
      if (r != null) return r;
    }
    for (final i in c.interfaces) {
      final ic = idx.resolveClass(i, c.file, context: c);
      if (ic != null) {
        final r = _fieldInChain(ic, name, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  PropDef? _parseDecl(JavaField f, JavaClass owner, int depth) {
    var init = f.init.trim();
    init = init.replaceFirst(RegExp(r'^\(\s*[\w<>?,\s]+\)\s*'), '');
    final m = RegExp(r'^(Boolean|Integer|Enum|Direction)Property\s*(?:<[^>]*>)?\s*\.\s*create\s*\(').firstMatch(init);
    final src = '${owner.name}.${f.name}';
    if (m == null) {
      // alias?
      if (RegExp(r'^[\w.]+$').hasMatch(init)) {
        final p = resolveProp(init, owner, depth + 1);
        return p;
      }
      return null;
    }
    final cl = matchClose(init, m.end - 1);
    final args = splitArgs(init.substring(m.end, cl));
    final kindName = m.group(1);
    final pname = stringLiteral(args[0]);
    if (pname == null) return null;
    if (kindName == 'Boolean') {
      return PropDef(pname, 'bool', const ['true', 'false'], source: src);
    }
    if (kindName == 'Integer') {
      final lo = ip.evalText(args[1], const {}, owner);
      final hi = ip.evalText(args[2], const {}, owner);
      if (lo is! int || hi is! int) {
        return PropDef(pname, 'int', const [], source: src, verified: false, note: 'range not evaluable: ${args[1]}..${args[2]}');
      }
      return PropDef(pname, 'int', [for (var i = lo; i <= hi; i++) '$i'], source: src);
    }
    if (kindName == 'Direction') {
      return PropDef(pname, 'enum', const [], source: src, verified: false, note: 'DirectionProperty not supported');
    }
    // EnumProperty
    final tm = RegExp(r'^([\w.]+)\.class$').firstMatch(args[1].trim());
    if (tm == null) return null;
    final ec = idx.resolveClass(tm.group(1)!, owner.file, context: owner);
    final vals = ec == null ? null : ip.enumValues(ec);
    if (ec == null || vals == null) {
      return PropDef(pname, 'enum', const [], source: src, verified: false, note: 'enum ${tm.group(1)} not found');
    }
    String sn(EnumVal v) => v.serialized ?? v.name.toLowerCase();
    var verified = vals.every((v) => v.serialized != null);
    String? note = verified ? null : 'serialized names not resolved for ${ec.name}; lower-cased constant names used';
    List<EnumVal> chosen;
    final rest = args.skip(2).toList();
    if (rest.isEmpty) {
      chosen = vals;
    } else if (rest.length == 1 && RegExp(r'^Direction\.Plane\.(HORIZONTAL|VERTICAL)$').hasMatch(rest[0].trim())) {
      final horizontal = rest[0].contains('HORIZONTAL');
      final set = horizontal ? {'NORTH', 'EAST', 'SOUTH', 'WEST'} : {'UP', 'DOWN'};
      chosen = vals.where((v) => set.contains(v.name)).toList();
    } else if (rest.length == 1 && parseLambda(rest[0]) != null) {
      final lam = parseLambda(rest[0])!;
      chosen = [];
      for (final v in vals) {
        final env = {lam.params.first: Bound('${ec.name}.${v.name}', const {}, ec)};
        // evaluate with ctx = owner so imports resolve the enum type
        final res = ip.evalText(lam.body, {lam.params.first: Bound('${tm.group(1)}.${v.name}', const {}, owner)}, owner);
        env.clear();
        if (res is! bool) {
          chosen = vals;
          verified = false;
          note = 'filter predicate not evaluable (${rest[0]}); all values assumed';
          break;
        }
        if (res) chosen.add(v);
      }
    } else {
      var items = rest;
      if (items.length == 1) {
        final lm = RegExp(r'^(?:List\.of|Arrays\.asList|ImmutableList\.of)\((.*)\)$', dotAll: true).firstMatch(items[0].trim());
        if (lm != null) items = splitArgs(lm.group(1)!);
      }
      chosen = [];
      for (final it in items) {
        final v = ip.evalText(it, const {}, owner);
        if (v is EnumVal) {
          chosen.add(v);
        } else {
          final bare = ec.enumConstants.indexWhere((c) => c.name == it.trim().split('.').last);
          if (bare >= 0) {
            chosen.add(vals[bare]);
          } else {
            verified = false;
            note = 'value list not evaluable: $it';
          }
        }
      }
    }
    return PropDef(pname, 'enum', chosen.map(sn).toList(), enumCls: ec, source: src, verified: verified, note: note);
  }

  // --------------------------------------------------------------- defaults
  void _defaults(JavaClass cls, PropResult r) {
    // class chain, root first
    final chain = <JavaClass>[];
    JavaClass? c = cls;
    while (c != null && chain.length < 14) {
      chain.insert(0, c);
      c = _super(c);
    }
    final cur = <String, String>{};
    void applyCall(String callText, JavaClass owner) {
      final ch = parseChain(callText);
      if (ch.calls.any((x) => x.key == 'any')) cur.clear();
      for (final sv in ch.calls.where((x) => x.key == 'setValue')) {
        final a = splitArgs(sv.value);
        if (a.length != 2) continue;
        final p = resolveProp(a[0], owner);
        if (p == null) {
          r.notes.add('default: unresolved property `${a[0]}` in ${owner.name}');
          r.verified = false;
          continue;
        }
        if (!r.props.containsKey(p.name)) {
          // property of a parent not re-declared? still a valid error to flag
          r.notes.add('default sets ${p.name} which is not in the state definition (${owner.name})');
          continue;
        }
        final v = _valueString(p, a[1], owner);
        if (v == null) {
          r.notes.add('default value for ${p.name} not evaluable in ${owner.name}: ${a[1]}');
          r.verified = false;
          continue;
        }
        if (!p.values.contains(v)) {
          r.notes.add('default ${p.name}=$v not in value list ${p.values}');
          r.verified = false;
        }
        cur[p.name] = v;
      }
    }

    for (final k in chain) {
      final withReg = k.ctors.where((ct) => ct.body.contains('registerDefaultState(')).toList();
      if (withReg.isEmpty) continue;
      final results = <Map<String, String>>[];
      for (final ct in withReg) {
        final snapshot = Map<String, String>.from(cur);
        for (final m in RegExp(r'registerDefaultState\s*\(').allMatches(ct.body)) {
          final cl = matchClose(ct.body, m.end - 1);
          if (cl < 0) continue;
          applyCall(ct.body.substring(m.end, cl), k);
        }
        results.add(Map<String, String>.from(cur));
        cur
          ..clear()
          ..addAll(snapshot);
      }
      cur
        ..clear()
        ..addAll(results.first);
      for (final other in results.skip(1)) {
        if (!_mapEq(other, results.first)) {
          r.notes.add('${k.name}: multiple constructors register different default states; first used');
        }
      }
    }
    for (final p in r.props.values) {
      r.defaults[p.name] = cur[p.name] ?? (p.values.isEmpty ? '?' : p.values.first);
    }
  }

  bool _mapEq(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  String? _valueString(PropDef p, String expr, JavaClass ctx) {
    expr = expr.trim();
    final v = ip.evalText(expr, const {}, ctx);
    if (p.kind == 'bool') return v is bool ? '$v' : null;
    if (p.kind == 'int') return v is int ? '$v' : null;
    if (v is EnumVal) return v.serialized ?? v.name.toLowerCase();
    if (p.enumCls != null) {
      final last = expr.split('.').last;
      final vals = ip.enumValues(p.enumCls!);
      if (vals != null) {
        for (final ev in vals) {
          if (ev.name == last) return ev.serialized ?? ev.name.toLowerCase();
        }
      }
    }
    return null;
  }
}

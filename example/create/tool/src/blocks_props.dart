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

/// Folds one constructor body's effect on the default state.
///
/// Java's default state of a registered block is whatever the constructor chain
/// leaves behind: vanilla `Block(Properties)` seeds it with
/// `stateDefinition.any()` (the first value of every property, i.e. the
/// [`start`] map), and a constructor may then override it. Two shapes are easy
/// to miss and both are handled here:
///
/// * the state is staged on a **local variable** first -
///   `BlockState s = defaultBlockState(); if (...) s = s.setValue(P, false);`
///   `registerDefaultState(s.setValue(Q, false));` - so only looking inside the
///   `registerDefaultState(...)` argument drops `P` (`PackagerBlock.LINKED`);
/// * the constructor **registers nothing**, and the block keeps `any()`
///   (`TableClothBlock`'s `String type` constructor).
///
/// [start] is the state inherited from the super constructors. The callbacks
/// abstract the interpreter so this is unit-testable without the Java sources.
Map<String, String> foldConstructorDefaults(
  String body,
  Map<String, String> start, {
  required String ownerName,
  required PropDef? Function(String expr) resolveProp,
  required String? Function(PropDef p, String expr) valueOf,
  required bool Function(String propName) declares,
  void Function(String msg)? note,
  void Function(String msg)? problem,
}) {
  var cur = Map<String, String>.from(start);
  final locals = <String, Map<String, String>?>{};

  bool? evalCondition(String cond) {
    final c = cond.trim();
    final hp = RegExp(r'^([\w.]+)\.hasProperty\s*\(\s*([\w.]+)\s*\)$').firstMatch(c);
    if (hp != null) {
      final p = resolveProp(hp.group(2)!);
      if (p != null) return declares(p.name);
    }
    // Constant sub-expressions, enough for the vanilla `Block` guard
    // `SharedConstants.IS_RUNNING_IN_IDE && false`.
    if (RegExp(r'(&&\s*false\b)|(\bfalse\s*&&)').hasMatch(c)) return false;
    if (RegExp(r'(\|\|\s*true\b)|(\btrue\s*\|\|)').hasMatch(c)) return true;
    return null;
  }

  Map<String, String>? evalState(String expr) {
    final t = expr.trim();
    if (t.isEmpty) return null;

    Map<String, String> applyCalls(Map<String, String> base, String tail) {
      var out = base;
      for (final c in parseChain(tail).calls) {
        if (c.key == 'any') {
          out = <String, String>{};
          continue;
        }
        if (c.key != 'setValue') continue;
        final a = splitArgs(c.value);
        if (a.length != 2) continue;
        final p = resolveProp(a[0]);
        if (p == null) {
          problem?.call('default: unresolved property `${a[0]}` in $ownerName');
          continue;
        }
        if (!declares(p.name)) {
          // property of a parent not re-declared? still a valid error to flag
          note?.call('default sets ${p.name} which is not in the state definition ($ownerName)');
          continue;
        }
        final v = valueOf(p, a[1]);
        if (v == null) {
          problem?.call('default value for ${p.name} not evaluable in $ownerName: ${a[1]}');
          continue;
        }
        if (!p.values.contains(v)) {
          problem?.call('default ${p.name}=$v not in value list ${p.values}');
        }
        out[p.name] = v;
      }
      return out;
    }

    // `defaultBlockState()` / `this.defaultBlockState()`: the state registered
    // by the super constructors, i.e. [cur].
    final dm = RegExp(r'^(?:(?:this|super)\.)?defaultBlockState\s*\(\s*\)').firstMatch(t);
    if (dm != null) return applyCalls(Map<String, String>.from(cur), t.substring(dm.end));

    final ch = parseChain(t);
    final root = ch.root;
    if (root.isEmpty) return null;
    final tail = t.substring(root.length);
    // `stateDefinition.any()` / `this.stateDefinition.any()`: vanilla's first
    // value of every property.
    if (ch.calls.isNotEmpty && ch.calls.first.key == 'any') {
      return applyCalls(<String, String>{}, tail);
    }
    // a state staged on a local variable (`s = s.setValue(..)`)
    final localKey = locals.containsKey(root)
        ? root
        : (locals.containsKey(root.split('.').last) ? root.split('.').last : null);
    if (localKey != null) {
      final l = locals[localKey];
      if (l == null) return null;
      return applyCalls(Map<String, String>.from(l), tail);
    }
    if (root == 'defaultBlockState' || root.endsWith('.defaultBlockState')) {
      return applyCalls(Map<String, String>.from(cur), tail);
    }
    return null;
  }

  late void Function(String raw) apply;

  void applyBlock(String rest) {
    if (rest.startsWith('{')) {
      final bcl = matchClose(rest, 0);
      if (bcl < 0) return;
      for (final st in splitJavaStatements(rest.substring(1, bcl))) {
        apply(st);
      }
    } else {
      apply(rest);
    }
  }

  apply = (String raw) {
    var s = raw.trim();
    if (s.isEmpty) return;
    final ifm = RegExp(r'^if\s*\(').firstMatch(s);
    if (ifm != null) {
      final op = s.indexOf('(', ifm.start);
      final cl = matchClose(s, op);
      if (cl < 0) return;
      final cond = s.substring(op + 1, cl);
      final rest = s.substring(cl + 1).trim();
      final truth = evalCondition(cond);
      if (truth == false) return;
      if (truth == null) note?.call('default condition not evaluable in $ownerName: $cond');
      applyBlock(rest);
      return;
    }
    if (s.startsWith('else')) {
      applyBlock(s.substring(4).trim());
      return;
    }
    if (RegExp(r'^(for|while|do|switch|try)\b').hasMatch(s)) {
      // A loop that does not touch the state definition (e.g. `LiquidBlock`'s
      // state cache fill) is irrelevant; one that does cannot be unrolled.
      if (s.contains('registerDefaultState') || RegExp(r'\.setValue\s*\(').hasMatch(s)) {
        problem?.call('default mutated inside a loop/switch in $ownerName; not modelled');
      }
      return;
    }
    final rm = RegExp(r'^(?:this\.)?registerDefaultState\s*\(').firstMatch(s);
    if (rm != null) {
      final op = rm.end - 1;
      final cl = matchClose(s, op);
      if (cl < 0) return;
      final folded = evalState(s.substring(op + 1, cl));
      if (folded == null) {
        problem?.call('registerDefaultState argument not modelled in $ownerName');
        return;
      }
      cur = folded;
      return;
    }
    final eq = topLevelAssignment(s);
    if (eq < 0) return; // method call, super(...), declaration without initialiser
    final lhs = s.substring(0, eq).trimRight();
    final rhs = s.substring(eq + 1).trim();
    final vm = RegExp(r'([A-Za-z_$][\w$]*)$').firstMatch(lhs);
    if (vm == null) return;
    final before = lhs.substring(0, vm.start).trimRight();
    if (before.endsWith('.') || before.endsWith(']')) return; // field / array element
    locals[vm.group(1)!] = rhs.isEmpty ? null : evalState(rhs);
  };

  for (final st in splitJavaStatements(body)) {
    apply(st);
  }
  return cur;
}

/// Splits a Java method body into top-level statements: on `;` at bracket depth
/// 0, and at a `}` that closes a top-level `if`/`else`/`for`/... block (which
/// has no trailing `;`).
List<String> splitJavaStatements(String body) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  var i = 0;
  final n = body.length;
  void flush(int end) {
    final t = body.substring(start, end).trim();
    if (t.isNotEmpty) out.add(t);
    start = end;
  }

  while (i < n) {
    final c = body[i];
    if (c == '"') {
      i = _skipQuoted(body, i, '"');
      continue;
    }
    if (c == "'") {
      i = _skipQuoted(body, i, "'");
      continue;
    }
    if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
      if (c == '}' && depth == 0) {
        final head = body.substring(start, i + 1).trimLeft();
        if (RegExp(r'^(if|else|for|while|do|switch|try|\{)').hasMatch(head)) {
          flush(i + 1);
        }
      }
    } else if (c == ';' && depth == 0) {
      flush(i + 1);
    }
    i++;
  }
  flush(n);
  return out;
}

/// Index after the closing quote of the string/char literal starting at [i].
int _skipQuoted(String s, int i, String quote) {
  i++; // opening quote
  while (i < s.length) {
    if (s[i] == '\\') {
      i += 2;
      continue;
    }
    if (s[i] == quote) return i + 1;
    i++;
  }
  return s.length;
}

/// Index of the `=` of a simple assignment at bracket depth 0, or -1. Skips
/// `==`, compound assignments and comparisons.
int topLevelAssignment(String s) {
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      i = _skipQuoted(s, i, '"') - 1;
      continue;
    }
    if (c == "'") {
      i = _skipQuoted(s, i, "'") - 1;
      continue;
    }
    if ('([{'.contains(c)) {
      depth++;
      continue;
    }
    if (')]}'.contains(c)) {
      depth--;
      continue;
    }
    if (c == '=' && depth == 0) {
      final prev = i > 0 ? s[i - 1] : '';
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (next == '=' || '=!<>+-*/%&|^'.contains(prev)) continue;
      return i;
    }
  }
  return -1;
}

/// The index of the default state within the block's states, numbered the same
/// way the host is (`docs/block-registry.md`): the properties sorted by name,
/// the alphabetically first most significant, each property's values indexed in
/// `Property.getPossibleValues()` order (bool: true,false; int: min..max; enum:
/// declaration or list order). `0` is `stateDefinition.any()`.
///
/// A `setblock create:packager` with no state produces exactly this index, so
/// the extractor's dump prints it to make a wrong default state visible.
int defaultStateIndex(Map<String, String> defaults, Iterable<PropDef> props) {
  final sorted = props.toList()..sort((a, b) => a.name.compareTo(b.name));
  var index = 0;
  var stride = 1;
  for (var i = sorted.length - 1; i >= 0; i--) {
    final p = sorted[i];
    final vi = p.values.indexOf(defaults[p.name] ?? '');
    index += (vi < 0 ? 0 : vi) * stride;
    stride *= p.values.isEmpty ? 1 : p.values.length;
  }
  return index;
}

class PropResolver {
  PropResolver(this.ip);
  final Interp ip;
  SourceIndex get idx => ip.idx;
  final Map<String, Map<String, PropDef>> _collectCache = {};
  final Map<String, PropDef?> _fieldCache = {};

  PropResult resolve(JavaClass cls, {JavaMethod? ctor}) {
    final r = PropResult();
    final notes = <String>[];
    final props = _collect(cls, 0, notes);
    r.props.addAll({for (final e in props.entries) e.key: e.value.copy()});
    r.notes.addAll(notes);
    for (final p in r.props.values) {
      if (!p.verified) r.verified = false;
    }
    _defaults(cls, r, ctor: ctor);
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
  /// Resolves the default state of a block whose registered class is [cls].
  ///
  /// [ctor] is the constructor the registration actually invokes, when it could
  /// be determined (see `BlockBuilderStage._registrationCtor`). Without it the
  /// resolver has to guess, and a class whose constructors disagree - or where
  /// only some register a default state - is flagged unverified rather than
  /// silently using one of them.
  void _defaults(JavaClass cls, PropResult r, {JavaMethod? ctor}) {
    // class chain, root first
    final chain = <JavaClass>[];
    JavaClass? c = cls;
    while (c != null && chain.length < 14) {
      chain.insert(0, c);
      c = _super(c);
    }
    var cur = <String, String>{};

    Map<String, String> fold(String body, JavaClass owner) => foldConstructorDefaults(
      body,
      cur,
      ownerName: owner.name,
      resolveProp: (e) => resolveProp(e, owner),
      valueOf: (p, e) => _valueString(p, e, owner),
      declares: (n) => r.props.containsKey(n),
      note: r.notes.add,
      problem: (m) {
        r.notes.add(m);
        r.verified = false;
      },
    );

    for (final k in chain) {
      final isRegistered = identical(k, cls);
      final List<JavaMethod> candidates;
      if (isRegistered && ctor != null) {
        candidates = [ctor];
      } else {
        candidates = k.ctors.where((ct) => ct.body.contains('registerDefaultState(')).toList();
        final nonReg = k.ctors.length - candidates.length;
        if (candidates.isNotEmpty && nonReg > 0) {
          // The registration's constructor is unknown and the class mixes
          // "registers a default state" with "registers nothing" - the default
          // depends on which one is used (e.g. `TableClothBlock`).
          r.notes.add(
            '${k.name}: ${k.ctors.length} constructors, only ${candidates.length} register a '
            'default state and the registration constructor is unknown',
          );
          r.verified = false;
        }
      }
      if (candidates.isEmpty) continue;
      final results = <Map<String, String>>[];
      for (final ct in candidates) {
        final snapshot = Map<String, String>.from(cur);
        cur = fold(ct.body, k);
        results.add(Map<String, String>.from(cur));
        cur = snapshot;
      }
      cur = Map<String, String>.from(results.first);
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

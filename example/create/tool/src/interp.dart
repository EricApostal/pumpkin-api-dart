// Registrate-builder "flattening interpreter" shared by the block / item extractors.
//
// It turns a builder expression such as
//   REGISTRATE.block("x", X::new).initialProperties(..).transform(foo()).register()
// (including helper methods that return builders and BuilderTransformers-style
// `b -> b.properties(..)` operators) into a flat, ordered list of [Call]s.
import 'expr.dart';
import 'java.dart';

/// Marker for "the builder chain built so far" bound to a transformer parameter.
class Bound {
  Bound(this.text, this.env, this.ctx, {this.isBuilder = false});
  final String text;
  final Map<String, Bound> env;
  final JavaClass? ctx;
  final bool isBuilder;
}

class Call {
  Call(this.name, this.args, this.env, this.ctx);
  final String name;
  final String args;
  final Map<String, Bound> env;
  final JavaClass? ctx;
  @override
  String toString() => '$name($args)';
}

class Interp {
  Interp(this.idx);
  final SourceIndex idx;
  final List<String> warnings = [];

  // ---------------------------------------------------------------- enums
  final Map<String, List<EnumVal>> _enumCache = {};

  List<EnumVal>? enumValues(JavaClass cls) {
    if (cls.kind != 'enum') return null;
    final key = '${cls.file.path}#${cls.qualifiedName}';
    final hit = _enumCache[key];
    if (hit != null) return hit;
    final consts = cls.enumConstants;
    // locate serialized-name logic
    final out = <EnumVal>[];
    final sn = _enumMethodValues(cls, 'getSerializedName');
    final ts = _enumMethodValues(cls, 'toString', serialized: sn);
    for (var i = 0; i < consts.length; i++) {
      out.add(EnumVal(cls.name, consts[i].name, i, sn?[i], ts?[i]));
    }
    _enumCache[key] = out;
    return out;
  }

  /// Best effort value of a no-arg method returning a String (getSerializedName / toString).
  List<String?>? _enumMethodValues(JavaClass cls, String methodName, {List<String?>? serialized}) {
    final consts = cls.enumConstants;
    JavaMethod? m;
    for (final x in cls.methods) {
      if (x.name == methodName && splitArgs(x.params).isEmpty) {
        m = x;
        break;
      }
    }
    if (m == null) return null;
    final rm = RegExp(r'return\s+(.*?);', dotAll: true).firstMatch(m.body);
    if (rm == null) return null;
    final retExpr = rm.group(1)!.trim();
    // field -> ctor param index / assigned expression
    final fieldParam = <String, int>{};
    final fieldExpr = <String, String>{};
    for (final c in cls.ctors) {
      final ps = splitArgs(c.params).map((p) => p.trim().split(RegExp(r'\s+')).last).toList();
      for (final am in RegExp(r'(?:this\.)?(\w+)\s*=\s*([^;]+);').allMatches(c.body)) {
        final rhs = am.group(2)!.trim();
        final pi = ps.indexOf(rhs);
        if (pi >= 0) {
          fieldParam[am.group(1)!] = pi;
        } else {
          fieldExpr[am.group(1)!] = rhs;
        }
      }
    }
    final out = <String?>[];
    for (var ci = 0; ci < consts.length; ci++) {
      final ec = consts[ci];
      final args = splitArgs(ec.args);
      Object? evalExpr(String expr, int depth) {
        final ev = Evaluator(
          resolve: (id) {
            if (id == 'this') return EnumVal(cls.name, ec.name, ci, serialized?[ci]);
            final cix = consts.indexWhere((x) => x.name == id);
            if (cix >= 0) return EnumVal(cls.name, id, cix, serialized?[cix]);
            final nm = id.startsWith('this.') ? id.substring(5) : id;
            final pi = fieldParam[nm];
            if (pi != null && pi < args.length) {
              return evalText(args[pi], const {}, cls);
            }
            final fe = fieldExpr[nm];
            if (fe != null && depth < 4) return evalExpr(fe, depth + 1);
            return null;
          },
          method: (t, n, a, raw) {
            if (n == 'name' && a.isEmpty && (t == null && (raw.isEmpty || raw == 'this'))) return ec.name;
            if (raw == 'Lang' && n == 'asId') return a.isNotEmpty && a[0] is String ? (a[0] as String).toLowerCase() : null;
            if (raw == 'Lang' && n == 'nonPluralId' && a.isNotEmpty && a[0] is String) {
              final s = (a[0] as String).toLowerCase();
              return s.endsWith('s') ? s.substring(0, s.length - 1) : s;
            }
            return defaultMethodHook(t, n, a, raw);
          },
        );
        return ev.eval(expr);
      }

      final v = evalExpr(retExpr, 0);
      out.add(v is String ? v : null);
    }
    return out;
  }

  EnumVal? enumConst(JavaClass cls, String name) {
    final vals = enumValues(cls);
    if (vals == null) return null;
    for (final v in vals) {
      if (v.name == name) return v;
    }
    return null;
  }

  // ----------------------------------------------------------- evaluation
  Object? evalText(String text, Map<String, Bound> env, JavaClass? ctx, {int depth = 0}) {
    if (depth > 12) return null;
    final ev = Evaluator(
      resolve: (id) => _resolveIdent(id, env, ctx, depth),
      method: (t, n, a, raw) {
        if (raw == 'Lang') {
          if (n == 'asId' && a.isNotEmpty && a[0] is String) return (a[0] as String).toLowerCase();
          if (n == 'nonPluralId' && a.isNotEmpty && a[0] is String) {
            final s = (a[0] as String).toLowerCase();
            return s.endsWith('s') ? s.substring(0, s.length - 1) : s;
          }
        }
        if (raw == 'String' && n == 'valueOf' && a.isNotEmpty && a[0] != null) return a[0].toString();
        if (t is EnumVal && n == 'getSerializedName') {
          return t.serialized ?? t.name.toLowerCase();
        }
        if (t is EnumVal && n == 'getName') return t.serialized ?? t.name.toLowerCase();
        if (t is EnumVal && n == 'getDurability' && a.length == 1 && a[0] is int) {
          // ArmorType.getDurability(mult) = unitDurability * mult (2nd ctor arg)
          final ec = idx.bySimpleName(t.type);
          if (ec != null && ec.kind == 'enum') {
            final k = ec.enumConstants.where((x) => x.name == t.name).firstOrNull;
            if (k != null) {
              final unit = evalText(splitArgs(k.args)[1], const {}, ec);
              if (unit is int) return unit * (a[0] as int);
            }
          }
        }
        return defaultMethodHook(t, n, a, raw);
      },
    );
    return ev.eval(text);
  }

  Object? _resolveIdent(String id, Map<String, Bound> env, JavaClass? ctx, int depth) {
    final dot = id.indexOf('.');
    final first = dot < 0 ? id : id.substring(0, dot);
    final b = env[first];
    if (b != null && dot < 0) {
      if (b.isBuilder) return null;
      return evalText(b.text, b.env, b.ctx ?? ctx, depth: depth + 1);
    }
    if (b != null) return null;
    if (ctx != null) {
      if (dot > 0) {
        // Type.CONST for enums
        final typeName = id.substring(0, id.lastIndexOf('.'));
        final cname = id.substring(id.lastIndexOf('.') + 1);
        final tc = idx.resolveClass(typeName, ctx.file, context: ctx);
        if (tc != null && tc.kind == 'enum') {
          return enumConst(tc, cname);
        }
        if (tc != null) {
          final f = _findField(tc, cname, 0);
          if (f != null && f.init.isNotEmpty) {
            // record-like constant: register(new WoodType("oak", ..))
            final rm = RegExp('^(?:\\w+\\()?\\s*new\\s+${tc.name}\\(\\s*"([^"]*)"').firstMatch(f.init.trim());
            if (rm != null) return EnumVal(tc.name, rm.group(1)!, -1, rm.group(1)!);
            return evalText(f.init, const {}, tc, depth: depth + 1);
          }
        }
        return null;
      }
      final f = _findField(ctx, id, 0);
      if (f != null && f.init.isNotEmpty) {
        return evalText(f.init, const {}, ctx, depth: depth + 1);
      }
      // statically imported constants (enum constants / static finals)
      for (final si in ctx.file.staticImports) {
        final dot = si.lastIndexOf('.');
        final member = si.substring(dot + 1);
        if (member != id && member != '*') continue;
        final cc = _classByFqn(si.substring(0, dot));
        if (cc == null) continue;
        if (cc.kind == 'enum') {
          final ev = enumConst(cc, id);
          if (ev != null) return ev;
        }
        final sf = _findField(cc, id, 0);
        if (sf != null && sf.init.isNotEmpty) return evalText(sf.init, const {}, cc, depth: depth + 1);
      }
    }
    return null;
  }

  JavaField? _findField(JavaClass c, String name, int depth) {
    if (depth > 6) return null;
    final f = c.field(name);
    if (f != null) return f;
    final sup = c.superName;
    if (sup != null) {
      final sc = idx.resolveClass(sup, c.file, context: c);
      if (sc != null) return _findField(sc, name, depth + 1);
    }
    return null;
  }

  // ------------------------------------------------------------- methods
  /// Finds a (static) method by name given an optional qualifier root.
  ({JavaMethod method, JavaClass cls})? findMethod(String? qualifier, String name, JavaClass ctx, {int? argc}) {
    _argc = argc;
    try {
      return _findMethod(qualifier, name, ctx);
    } finally {
      _argc = null;
    }
  }

  int? _argc;
  final Set<JavaMethod> _excluded = {};

  ({JavaMethod method, JavaClass cls})? _findMethod(String? qualifier, String name, JavaClass ctx) {
    JavaClass? q;
    if (qualifier != null && qualifier.isNotEmpty) {
      q = idx.resolveClass(qualifier, ctx.file, context: ctx);
      if (q == null) return null;
      final r = _methodIn(q, name);
      return r;
    }
    // same class (and outers)
    JavaClass? c = ctx;
    while (c != null) {
      final r = _methodIn(c, name);
      if (r != null) return r;
      c = c.outer;
    }
    // static imports
    for (final si in ctx.file.staticImports) {
      final lastDot = si.lastIndexOf('.');
      final member = si.substring(lastDot + 1);
      final clsName = si.substring(0, lastDot);
      if (member == name || member == '*') {
        final sc = _classByFqn(clsName);
        if (sc != null) {
          final r = _methodIn(sc, name);
          if (r != null) return r;
        }
      }
    }
    return null;
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

  ({JavaMethod method, JavaClass cls})? _methodIn(JavaClass c, String name, [int depth = 0]) {
    JavaMethod? first;
    for (final m in c.methods) {
      if (m.name != name) continue;
      if (_excluded.contains(m)) continue;
      first ??= m;
      if (_argc != null && _paramNames(m.params).length == _argc) return (method: m, cls: c);
    }
    if (first != null) return (method: first, cls: c);
    if (depth > 4) return null;
    final sup = c.superName;
    if (sup != null) {
      final sc = idx.resolveClass(sup, c.file, context: c);
      if (sc != null) return _methodIn(sc, name, depth + 1);
    }
    return null;
  }

  /// All overloads (by arity) of method [name] in [c].
  JavaMethod? pickOverload(JavaClass c, String name, int argc) {
    JavaMethod? any;
    for (final m in c.methods) {
      if (m.name != name) continue;
      any ??= m;
      if (_paramNames(m.params).length == argc) return m;
    }
    return any;
  }

  static List<String> _paramNames(String params) =>
      splitArgs(params).map((p) => p.trim().replaceAll(RegExp(r'\bfinal\s+'), '').split(RegExp(r'\s+')).last).where((e) => e.isNotEmpty).toList();

  List<String> paramNames(String params) => _paramNames(params);

  // ----------------------------------------------------- statement helpers
  /// Splits a method / lambda body into top-level statements.
  List<String> statements(String body) {
    final members = splitMembers('$body\n');
    // splitMembers splits on ';' and on braces -> works for flat statements
    return members.map((m) => m.text.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// Returns (locals, returnExpr) for a body. Locals are ordered; a `+=` append is
  /// represented with a leading '+' on the name.
  ({List<MapEntry<String, String>> locals, String? ret}) analyseBody(String body) {
    final locals = <MapEntry<String, String>>[];
    String? ret;
    if (splitTop(body, ';').where((e) => e.trim().isNotEmpty).length <= 1 && !RegExp(r'^\s*return\b').hasMatch(body)) {
      return (locals: locals, ret: body.trim());
    }
    for (var s in statements(body)) {
      if (s.endsWith(';')) s = s.substring(0, s.length - 1).trim();
      final rm = RegExp(r'^return\s+(.*)$', dotAll: true).firstMatch(s);
      if (rm != null) {
        ret = rm.group(1)!.trim();
        continue;
      }
      final am = RegExp(r'^(\w+)\s*\+=\s*(.*)$', dotAll: true).firstMatch(s);
      if (am != null) {
        locals.add(MapEntry('+${am.group(1)}', am.group(2)!.trim()));
        continue;
      }
      final fm = parseFieldMember('$s;');
      if (fm.length == 1 && fm.first.init.isNotEmpty && !s.startsWith('if') && !s.startsWith('for') && !s.startsWith('while')) {
        locals.add(MapEntry(fm.first.name, fm.first.init));
      }
    }
    return (locals: locals, ret: ret);
  }

  /// Binds [locals] into [env] (in order) as lazily evaluated expressions.
  void bindLocals(Map<String, Bound> env, List<MapEntry<String, String>> locals, JavaClass owner) {
    var n = 0;
    for (final l in locals) {
      if (l.key.startsWith('+')) {
        final nm = l.key.substring(1);
        final prev = env[nm];
        if (prev == null) continue;
        final hidden = '__prev${n++}_$nm';
        env[hidden] = prev;
        env[nm] = Bound('$hidden + (${l.value})', env, owner);
      } else {
        env[l.key] = Bound(l.value, env, owner);
      }
    }
  }

  static const _sentinel = '\u0000BUILDER';

  // ------------------------------------------------------------ flattening
  /// Flatten a builder expression into an ordered call list.
  List<Call> flatten(String expr, Map<String, Bound> env, JavaClass ctx, {List<Call>? prefix, int depth = 0}) {
    if (depth > 14) {
      warnings.add('flatten depth exceeded: ${expr.length > 60 ? expr.substring(0, 60) : expr}');
      return [];
    }
    expr = expr.trim();
    // lambda / block bodies passed directly
    final chain = parseChain(expr);
    final result = <Call>[];
    var start = 0;
    final root = chain.root;
    final calls = chain.calls;
    const regRoots = {'REGISTRATE', 'registrate', 'super', 'Create', 'this'};
    if (root.isEmpty && calls.isNotEmpty) {
      // helper-method call: foo(args).bar()
      final first = calls.first;
      final found = findMethod(null, first.key, ctx, argc: splitArgs(first.value).length);
      if (found != null) {
        result.addAll(_inlineMethod(found.method, found.cls, first.value, env, ctx, prefix, depth));
        start = 1;
      } else if (first.key == 'registrate') {
        start = 1;
      } else {
        warnings.add('unresolved helper ${first.key}');
        start = 1;
      }
    } else if (regRoots.contains(root.split('.').first) && root != 'this') {
      // registrate call; if root path longer (Create.registrate()) handled by calls
      if (calls.isNotEmpty && calls.first.key == 'registrate') start = 1;
    } else if (env.containsKey(root)) {
      final b = env[root]!;
      if (b.isBuilder) {
        result.addAll(prefix ?? const []);
      } else {
        result.addAll(flatten(b.text, b.env, b.ctx ?? ctx, prefix: prefix, depth: depth + 1));
      }
    } else if (root.isNotEmpty) {
      // maybe ClassName.staticHelper(...) or registrate-like variable `r`
      final lastSeg = root.contains('.') ? root.substring(root.lastIndexOf('.') + 1) : root;
      if (calls.isNotEmpty) {
        var found = findMethod(root, calls.first.key, ctx, argc: splitArgs(calls.first.value).length);
        if (found == null && !root.contains('.')) {
          // instance helper on registrate-like variable (e.g. `r.paletteStoneBlock`)
          final cr = idx.bySimpleName('CreateRegistrate');
          if (cr != null) {
            final m = findMethod(null, calls.first.key, cr, argc: splitArgs(calls.first.value).length);
            if (m != null) found = m;
          }
        }
        if (found != null) {
          result.addAll(_inlineMethod(found.method, found.cls, calls.first.value, env, ctx, prefix, depth));
          start = 1;
        } else {
          warnings.add('unresolved root $root.${calls.first.key} ($lastSeg)');
        }
      }
    }
    for (var i = start; i < calls.length; i++) {
      final c = calls[i];
      if (c.key == 'transform') {
        final sm = RegExp(r'^\s*CStress\s*\.\s*(setImpact|setCapacity|setNoImpact)\s*\((.*)\)\s*$', dotAll: true).firstMatch(c.value);
        if (sm != null) {
          result.add(Call(sm.group(1) == 'setCapacity' ? 'stress:capacity' : 'stress:impact', sm.group(1) == 'setNoImpact' ? '0' : sm.group(2)!, env, ctx));
          continue;
        }
        final expanded = _expandTransform(c.value, env, ctx, result, depth);
        if (expanded != null) {
          result
            ..clear()
            ..addAll(expanded);
          continue;
        }
        result.add(Call('transform?', c.value, env, ctx));
        continue;
      }
      result.add(Call(c.key, c.value, env, ctx));
    }
    return result;
  }

  List<Call> _inlineMethod(JavaMethod m, JavaClass owner, String argsRaw, Map<String, Bound> callerEnv, JavaClass callerCtx,
      List<Call>? prefix, int depth) {
    final names = _paramNames(m.params);
    final args = splitArgs(argsRaw);
    final env = <String, Bound>{};
    for (var i = 0; i < names.length && i < args.length; i++) {
      final a = args[i];
      // a builder passthrough?
      final ar = parseChain(a);
      if (ar.calls.isEmpty && callerEnv[ar.root]?.isBuilder == true) {
        env[names[i]] = Bound('', callerEnv, callerCtx, isBuilder: true);
      } else {
        env[names[i]] = Bound(a, callerEnv, callerCtx);
      }
    }
    final an = analyseBody(m.body);
    bindLocals(env, an.locals, owner);
    if (an.ret == null) {
      warnings.add('method ${m.name} has no return');
      return [];
    }
    return flatten(an.ret!, env, owner, prefix: prefix, depth: depth + 1);
  }

  /// Returns the new chain after applying transformer [argExpr] to [chainSoFar],
  /// or null if the transformer cannot be resolved.
  List<Call>? _expandTransform(String argExpr, Map<String, Bound> env, JavaClass ctx, List<Call> chainSoFar, int depth) {
    argExpr = argExpr.trim();
    final lam = parseLambda(argExpr);
    if (lam != null && lam.params.length == 1) {
      final env2 = Map<String, Bound>.from(env);
      env2[lam.params.first] = Bound('', env, ctx, isBuilder: true);
      return _flattenLambdaBody(lam.body, env2, ctx, chainSoFar, depth);
    }
    // method call: foo(args) / Cls.foo(args)
    final ch = parseChain(argExpr);
    if (ch.calls.length == 1) {
      final qual = ch.root.isEmpty ? null : ch.root;
      final found = findMethod(qual, ch.calls.first.key, ctx, argc: splitArgs(ch.calls.first.value).length);
      if (found != null) {
        final names = _paramNames(found.method.params);
        final args = splitArgs(ch.calls.first.value);
        final menv = <String, Bound>{};
        for (var i = 0; i < names.length && i < args.length; i++) {
          menv[names[i]] = Bound(args[i], env, ctx);
        }
        final an = analyseBody(found.method.body);
        bindLocals(menv, an.locals, found.cls);
        final ret = an.ret;
        if (ret == null) return null;
        final rl = parseLambda(ret);
        if (rl != null && rl.params.length == 1) {
          menv[rl.params.first] = Bound('', menv, found.cls, isBuilder: true);
          return _flattenLambdaBody(rl.body, menv, found.cls, chainSoFar, depth);
        }
        // returns another transformer call -> recurse (skipping this overload)
        if (_excluded.length < 6) {
          _excluded.add(found.method);
          try {
            return _expandTransform(ret, menv, found.cls, chainSoFar, depth + 1);
          } finally {
            _excluded.remove(found.method);
          }
        }
        return null;
      }
    }
    return null;
  }

  List<Call> _flattenLambdaBody(String body, Map<String, Bound> env, JavaClass ctx, List<Call> chainSoFar, int depth) {
    final an = analyseBody(body);
    final env2 = Map<String, Bound>.from(env);
    bindLocals(env2, an.locals, ctx);
    final expr = an.ret ?? body;
    return flatten(expr, env2, ctx, prefix: chainSoFar, depth: depth + 1);
  }
}

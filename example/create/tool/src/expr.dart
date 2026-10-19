// Tiny Java expression evaluator (strings, numbers, booleans, enum constants).
// Returns `null` for anything it cannot evaluate; callers decide what that means.
import 'java.dart';

/// A resolved enum constant.
class EnumVal {
  EnumVal(this.type, this.name, this.ordinal, [this.serialized, this.str]);
  final String type;
  final String name;
  final int ordinal;
  final String? serialized;
  final String? str; // result of a toString() override, if any
  @override
  String toString() => '$type.$name';
  @override
  bool operator ==(Object other) => other is EnumVal && other.type == type && other.name == name;
  @override
  int get hashCode => Object.hash(type, name);
}

typedef Resolver = Object? Function(String ident);
typedef MethodHook = Object? Function(Object? target, String name, List<Object?> args, String rawTarget);

class _Tok {
  _Tok(this.kind, this.text);
  final String kind; // str num id op
  final String text;
  @override
  String toString() => '$kind:$text';
}

List<_Tok> _lex(String s) {
  final out = <_Tok>[];
  var i = 0;
  final n = s.length;
  while (i < n) {
    final c = s[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == '"') {
      final sb = StringBuffer();
      i++;
      while (i < n && s[i] != '"') {
        if (s[i] == '\\' && i + 1 < n) {
          final e = s[i + 1];
          sb.write(e == 'n' ? '\n' : e == 't' ? '\t' : e);
          i += 2;
        } else {
          sb.write(s[i]);
          i++;
        }
      }
      i++;
      out.add(_Tok('str', sb.toString()));
      continue;
    }
    if (c == "'") {
      final sb = StringBuffer();
      i++;
      while (i < n && s[i] != "'") {
        if (s[i] == '\\' && i + 1 < n) {
          sb.write(s[i + 1]);
          i += 2;
        } else {
          sb.write(s[i]);
          i++;
        }
      }
      i++;
      out.add(_Tok('chr', sb.toString()));
      continue;
    }
    final nm = RegExp(r'(0[xX][0-9a-fA-F_]+[lL]?|(\d[\d_]*\.?\d*|\.\d+)([eE][+-]?\d+)?[fFdDlL]?)').matchAsPrefix(s, i);
    if (nm != null && (RegExp(r'[0-9]').hasMatch(c) || (c == '.' && i + 1 < n && RegExp(r'[0-9]').hasMatch(s[i + 1])))) {
      out.add(_Tok('num', nm.group(0)!));
      i = nm.end;
      continue;
    }
    final idm = RegExp(r'[A-Za-z_$][\w$]*').matchAsPrefix(s, i);
    if (idm != null) {
      out.add(_Tok('id', idm.group(0)!));
      i = idm.end;
      continue;
    }
    // operators
    final two = i + 1 < n ? s.substring(i, i + 2) : '';
    if (['==', '!=', '<=', '>=', '&&', '||', '->', '::', '<<', '>>'].contains(two)) {
      out.add(_Tok('op', two));
      i += 2;
      continue;
    }
    out.add(_Tok('op', c));
    i++;
  }
  return out;
}

num? parseJavaNumber(String t) {
  var x = t.replaceAll('_', '');
  if (x.startsWith('0x') || x.startsWith('0X')) {
    x = x.substring(2).replaceAll(RegExp(r'[lL]$'), '');
    return int.tryParse(x, radix: 16);
  }
  final isFloat = RegExp(r'[fFdD]$').hasMatch(x) || x.contains('.') || RegExp(r'[eE]').hasMatch(x);
  x = x.replaceAll(RegExp(r'[fFdDlL]$'), '');
  if (x.startsWith('.')) x = '0$x';
  if (x.endsWith('.')) x = '${x}0';
  if (isFloat) return double.tryParse(x);
  return int.tryParse(x);
}

class Evaluator {
  Evaluator({required this.resolve, this.method});
  final Resolver resolve;
  final MethodHook? method;

  List<_Tok> _t = const [];
  int _p = 0;
  bool _failed = false;

  Object? eval(String expr) {
    _t = _lex(expr);
    _p = 0;
    _failed = false;
    try {
      final v = _ternary();
      if (_failed) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  _Tok? get _peek => _p < _t.length ? _t[_p] : null;
  bool _isOp(String o) => _peek != null && _peek!.kind == 'op' && _peek!.text == o;

  Object? _ternary() {
    final c = _or();
    if (_isOp('?')) {
      _p++;
      final a = _ternary();
      if (_isOp(':')) _p++;
      final b = _ternary();
      if (c is bool) return c ? a : b;
      return null;
    }
    return c;
  }

  Object? _or() {
    var l = _and();
    while (_isOp('||')) {
      _p++;
      final r = _and();
      l = (l is bool && r is bool) ? (l || r) : null;
    }
    return l;
  }

  Object? _and() {
    var l = _cmp();
    while (_isOp('&&')) {
      _p++;
      final r = _cmp();
      l = (l is bool && r is bool) ? (l && r) : null;
    }
    return l;
  }

  Object? _cmp() {
    var l = _add();
    while (_peek != null && _peek!.kind == 'op' && ['==', '!=', '<', '>', '<=', '>='].contains(_peek!.text)) {
      final op = _peek!.text;
      _p++;
      final r = _add();
      if (l == null || r == null) {
        l = null;
        continue;
      }
      if (op == '==') {
        l = l == r;
      } else if (op == '!=') {
        l = l != r;
      } else if (l is num && r is num) {
        l = op == '<' ? l < r : op == '>' ? l > r : op == '<=' ? l <= r : l >= r;
      } else {
        l = null;
      }
    }
    return l;
  }

  Object? _add() {
    var l = _mul();
    while (_peek != null && _peek!.kind == 'op' && (_peek!.text == '+' || _peek!.text == '-')) {
      final op = _peek!.text;
      _p++;
      final r = _mul();
      if (op == '+') {
        if (l is String || r is String) {
          if (l == null || r == null) {
            l = null;
          } else {
            l = '${_str(l)}${_str(r)}';
          }
        } else if (l is num && r is num) {
          l = l + r;
        } else {
          l = null;
        }
      } else {
        l = (l is num && r is num) ? l - r : null;
      }
    }
    return l;
  }

  String _str(Object o) {
    if (o is double && o == o.truncateToDouble()) return o.toString();
    if (o is EnumVal) return o.str ?? o.name;
    return o.toString();
  }

  Object? _mul() {
    var l = _unary();
    while (_peek != null && _peek!.kind == 'op' && (_peek!.text == '*' || _peek!.text == '/' || _peek!.text == '%')) {
      final op = _peek!.text;
      _p++;
      final r = _unary();
      if (l is num && r is num) {
        if (op == '*') {
          l = l * r;
        } else if (op == '/') {
          l = (l is int && r is int) ? (r == 0 ? null : l ~/ r) : l / r;
        } else {
          l = l % r;
        }
      } else {
        l = null;
      }
    }
    return l;
  }

  Object? _unary() {
    if (_isOp('-')) {
      _p++;
      final v = _unary();
      return v is num ? -v : null;
    }
    if (_isOp('+')) {
      _p++;
      return _unary();
    }
    if (_isOp('!')) {
      _p++;
      final v = _unary();
      return v is bool ? !v : null;
    }
    // cast: (int) x  /  (float) x
    if (_isOp('(') && _p + 2 < _t.length && _t[_p + 1].kind == 'id' && _t[_p + 2].kind == 'op' && _t[_p + 2].text == ')') {
      final ty = _t[_p + 1].text;
      if (['int', 'float', 'double', 'long', 'short', 'byte'].contains(ty) && _p + 3 < _t.length) {
        _p += 3;
        final v = _unary();
        if (v is num) {
          if (ty == 'int' || ty == 'long' || ty == 'short' || ty == 'byte') return v.toInt();
          return v.toDouble();
        }
        return v;
      }
    }
    return _postfix();
  }

  Object? _postfix() {
    final tk = _peek;
    if (tk == null) {
      _failed = true;
      return null;
    }
    Object? cur;
    var raw = '';
    if (tk.kind == 'str') {
      _p++;
      cur = tk.text;
    } else if (tk.kind == 'chr') {
      _p++;
      cur = tk.text;
    } else if (tk.kind == 'num') {
      _p++;
      cur = parseJavaNumber(tk.text);
    } else if (tk.kind == 'op' && tk.text == '(') {
      _p++;
      cur = _ternary();
      if (_isOp(')')) _p++;
    } else if (tk.kind == 'id') {
      if (tk.text == 'true' || tk.text == 'false') {
        _p++;
        cur = tk.text == 'true';
      } else if (tk.text == 'null') {
        _p++;
        cur = null;
      } else if (tk.text == 'new') {
        // unsupported: skip to the end of the expression
        _failed = true;
        _p = _t.length;
        return null;
      } else {
        // dotted identifier path, possibly with method calls
        _p++;
        var path = tk.text;
        // handle `a.b.c` and `a.b(x).c`
        if (_isOp('(')) {
          // plain function call f(args)
          final args = _args();
          cur = method?.call(null, tk.text, args, '');
          raw = tk.text;
          return _chain(cur, raw);
        }
        while (_isOp('.') && _p + 1 < _t.length && _t[_p + 1].kind == 'id') {
          // lookahead: if next is method call, resolve path so far first
          final nm = _t[_p + 1].text;
          if (_p + 2 < _t.length && _t[_p + 2].kind == 'op' && _t[_p + 2].text == '(') {
            break;
          }
          path = '$path.$nm';
          _p += 2;
        }
        cur = resolve(path);
        raw = path;
        return _chain(cur, raw);
      }
    } else {
      _failed = true;
      _p++;
      return null;
    }
    return _chain(cur, raw);
  }

  Object? _chain(Object? cur, String raw) {
    while (_isOp('.') && _p + 1 < _t.length && _t[_p + 1].kind == 'id') {
      final name = _t[_p + 1].text;
      _p += 2;
      if (_isOp('(')) {
        final args = _args();
        cur = method?.call(cur, name, args, raw);
        raw = '$raw.$name()';
      } else {
        // field access on a value we cannot model
        cur = resolve('$raw.$name');
        raw = '$raw.$name';
      }
    }
    return cur;
  }

  List<Object?> _args() {
    // current token is '('
    final args = <Object?>[];
    _p++; // (
    if (_isOp(')')) {
      _p++;
      return args;
    }
    while (_p < _t.length) {
      // a lambda or something unparsable inside args: skip balanced to ',' or ')'
      final start = _p;
      final v = _argValue();
      args.add(v);
      if (_isOp(',')) {
        _p++;
        continue;
      }
      if (_isOp(')')) {
        _p++;
        break;
      }
      // skip junk until , or )
      var depth = 0;
      while (_p < _t.length) {
        final t = _t[_p];
        if (t.kind == 'op' && (t.text == '(' || t.text == '[' || t.text == '{')) depth++;
        if (t.kind == 'op' && (t.text == ')' || t.text == ']' || t.text == '}')) {
          if (depth == 0) break;
          depth--;
        }
        if (t.kind == 'op' && t.text == ',' && depth == 0) break;
        _p++;
      }
      if (_p == start) _p++;
      if (_isOp(',')) {
        _p++;
        continue;
      }
      if (_isOp(')')) {
        _p++;
      }
      break;
    }
    return args;
  }

  Object? _argValue() {
    final saveFailed = _failed;
    _failed = false;
    final v = _ternary();
    final f = _failed;
    _failed = saveFailed;
    return f ? null : v;
  }
}

/// Evaluate a standalone expression with a local environment.
Object? evalWith(String expr, Map<String, Object?> env, {Resolver? fallback, MethodHook? method}) {
  final ev = Evaluator(
    resolve: (id) {
      if (env.containsKey(id)) return env[id];
      return fallback?.call(id);
    },
    method: method ?? defaultMethodHook,
  );
  return ev.eval(expr);
}

/// Built-in handling of common methods on strings/enum values.
Object? defaultMethodHook(Object? target, String name, List<Object?> args, String rawTarget) {
  if (target is EnumVal) {
    switch (name) {
      case 'name':
        return target.name;
      case 'ordinal':
        return target.ordinal;
      case 'getSerializedName':
        return target.serialized ?? target.name.toLowerCase();
    }
    return null;
  }
  if (target is String) {
    switch (name) {
      case 'toLowerCase':
        return target.toLowerCase();
      case 'toUpperCase':
        return target.toUpperCase();
      case 'length':
        return target.length;
      case 'equals':
        return args.isNotEmpty && args[0] != null ? target == args[0] : null;
      case 'replace':
        if (args.length == 2 && args[0] is String && args[1] is String) {
          return target.replaceAll(args[0] as String, args[1] as String);
        }
        return null;
    }
    return null;
  }
  if (target == null && rawTargetIsLang(rawTarget, name)) return null;
  return null;
}

bool rawTargetIsLang(String raw, String name) => false;

/// Helper: extract a Java string literal's value if [expr] is exactly one.
String? stringLiteral(String expr) {
  final m = RegExp(r'^\s*"((?:[^"\\]|\\.)*)"\s*$').firstMatch(expr);
  if (m == null) return null;
  return m.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (x) => x.group(1) == 'n' ? '\n' : x.group(1)!);
}

String unescapeJava(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (x) => x.group(1) == 'n' ? '\n' : x.group(1)!);

/// Splits a lambda "a -> body" / "(a, b) -> body" into (params, body). Null if not a lambda.
({List<String> params, String body})? parseLambda(String expr) {
  final t = expr.trim();
  final m = RegExp(r'^(\(([^()]*)\)|[A-Za-z_$][\w$]*)\s*->\s*', dotAll: true).firstMatch(t);
  if (m == null) return null;
  final pr = m.group(2) ?? m.group(1)!;
  final params = pr.split(',').map((e) => e.trim().split(RegExp(r'\s+')).last).where((e) => e.isNotEmpty).toList();
  var body = t.substring(m.end).trim();
  if (body.startsWith('{')) {
    final cl = matchClose(body, 0);
    if (cl > 0) body = body.substring(1, cl);
  }
  return (params: params, body: body);
}

// Minimal, forgiving Java source scanner used by tool/extract_manifest.dart.
//
// It is NOT a Java parser. It understands just enough structure (comments,
// string literals, bracket nesting, class/field/method member boundaries) to
// let the extractor read the Create / Minecraft sources reliably.
import 'dart:io';

/// Replaces comments with spaces (keeping newlines so offsets/lines survive)
/// and leaves string / char literals untouched.
String stripComments(String s) {
  final out = StringBuffer();
  var i = 0;
  final n = s.length;
  while (i < n) {
    final c = s[i];
    if (c == '"') {
      // text block?
      if (s.startsWith('"""', i)) {
        final end = s.indexOf('"""', i + 3);
        final stop = end < 0 ? n : end + 3;
        out.write(s.substring(i, stop));
        i = stop;
        continue;
      }
      var j = i + 1;
      while (j < n && s[j] != '"') {
        if (s[j] == '\\') j++;
        j++;
      }
      out.write(s.substring(i, (j + 1).clamp(0, n)));
      i = j + 1;
    } else if (c == "'") {
      var j = i + 1;
      while (j < n && s[j] != "'") {
        if (s[j] == '\\') j++;
        j++;
      }
      out.write(s.substring(i, (j + 1).clamp(0, n)));
      i = j + 1;
    } else if (c == '/' && i + 1 < n && s[i + 1] == '/') {
      while (i < n && s[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (c == '/' && i + 1 < n && s[i + 1] == '*') {
      final end = s.indexOf('*/', i + 2);
      final stop = end < 0 ? n : end + 2;
      for (var k = i; k < stop; k++) {
        out.write(s[k] == '\n' ? '\n' : ' ');
      }
      i = stop;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

const _open = '([{';
const _close = ')]}';

/// Index of the bracket matching the opener at [openIdx], or -1.
int matchClose(String s, int openIdx) {
  var depth = 0;
  final n = s.length;
  var i = openIdx;
  while (i < n) {
    final c = s[i];
    if (c == '"') {
      if (s.startsWith('"""', i)) {
        final end = s.indexOf('"""', i + 3);
        if (end < 0) return -1;
        i = end + 3;
        continue;
      }
      i++;
      while (i < n && s[i] != '"') {
        if (s[i] == '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c == "'") {
      i++;
      while (i < n && s[i] != "'") {
        if (s[i] == '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (_open.contains(c)) {
      depth++;
    } else if (_close.contains(c)) {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

/// Splits [s] on [sep] (single char) at bracket depth 0. Generic `<...>` after
/// an identifier is also treated as a bracket.
List<String> splitTop(String s, String sep) {
  final parts = <String>[];
  var depth = 0;
  var angle = 0;
  var start = 0;
  final n = s.length;
  var i = 0;
  while (i < n) {
    final c = s[i];
    if (c == '"') {
      if (s.startsWith('"""', i)) {
        final end = s.indexOf('"""', i + 3);
        i = end < 0 ? n : end + 3;
        continue;
      }
      i++;
      while (i < n && s[i] != '"') {
        if (s[i] == '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c == "'") {
      i++;
      while (i < n && s[i] != "'") {
        if (s[i] == '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (_open.contains(c)) {
      depth++;
    } else if (_close.contains(c)) {
      depth--;
    } else if (c == '<' && depth >= 0) {
      // generic opener heuristic: identifier immediately before, and the
      // matching '>' closes over a type-ish body.
      if (i > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(s[i - 1])) {
        final glen = _genericLen(s, i);
        if (glen > 0 && !RegExp(r'^[a-z_0-9]+$').hasMatch(_identBefore(s, i))) {
          i += glen;
          continue;
        }
      }
    } else if (c == sep && depth == 0 && angle == 0) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
    i++;
  }
  parts.add(s.substring(start));
  return parts;
}

/// Length of a balanced generic argument list starting at s[i] == '<', or 0.
int _genericLen(String s, int i) {
  var d = 0;
  for (var j = i; j < s.length; j++) {
    final c = s[j];
    if (c == '<') {
      d++;
    } else if (c == '>') {
      d--;
      if (d == 0) return j - i + 1;
    } else if (!RegExp(r'[\w\s,.?\[\]&]').hasMatch(c)) {
      return 0;
    }
  }
  return 0;
}

String _identBefore(String s, int i) {
  var j = i;
  while (j > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(s[j - 1])) {
    j--;
  }
  return s.substring(j, i);
}

/// Splits call arguments "a, b(c, d), e" -> [a, b(c, d), e] (trimmed).
List<String> splitArgs(String s) {
  if (s.trim().isEmpty) return const [];
  return splitTop(s, ',').map((e) => e.trim()).toList();
}

class Member {
  Member(this.text, this.start);
  final String text; // full member text incl. trailing ; or block
  final int start; // offset in body
  // classification
  String kind = 'field'; // field | method | ctor | class | init
  String name = '';
  String header = '';
}

final _classKw = RegExp(r'\b(class|enum|interface|record|@interface)\s+([A-Za-z_]\w*)');

/// Splits a class body (text between the braces) into members.
List<Member> splitMembers(String body, {bool enumHead = false}) {
  final members = <Member>[];
  var i = 0;
  final n = body.length;
  if (enumHead) {
    // enum constants end at first depth-0 ';'
    var depth = 0;
    var j = 0;
    while (j < n) {
      final c = body[j];
      if (c == '"') {
        j++;
        while (j < n && body[j] != '"') {
          if (body[j] == '\\') j++;
          j++;
        }
      } else if (_open.contains(c)) {
        depth++;
      } else if (_close.contains(c)) {
        depth--;
      } else if (c == ';' && depth == 0) {
        break;
      }
      j++;
    }
    final m = Member(body.substring(0, j.clamp(0, n)), 0)..kind = 'enumconsts';
    members.add(m);
    i = (j + 1).clamp(0, n);
  }
  var start = i;
  var depth = 0;
  var sawEquals = false;
  var sawParen = false;
  while (i < n) {
    final c = body[i];
    if (c == '"') {
      if (body.startsWith('"""', i)) {
        final end = body.indexOf('"""', i + 3);
        i = end < 0 ? n : end + 3;
        continue;
      }
      i++;
      while (i < n && body[i] != '"') {
        if (body[i] == '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c == "'") {
      i++;
      while (i < n && body[i] != "'") {
        if (body[i] == '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (depth == 0) {
      if (c == '=' && !sawParen && i + 1 < n && body[i + 1] != '=') {
        // ignore '==' '>=' '<=' '!=' (previous char)
        final p = i > 0 ? body[i - 1] : ' ';
        if (!'=!<>'.contains(p)) sawEquals = true;
      }
      if (c == '(') sawParen = true;
      if (c == ';') {
        _push(members, body, start, i + 1);
        start = i + 1;
        sawEquals = false;
        sawParen = false;
        i++;
        continue;
      }
      if (c == '{') {
        final close = matchClose(body, i);
        if (close < 0) break;
        if (sawEquals) {
          // field with initializer containing braces: continue to ';'
          i = close + 1;
          continue;
        }
        _push(members, body, start, close + 1);
        start = close + 1;
        sawEquals = false;
        sawParen = false;
        i = close + 1;
        continue;
      }
    }
    if (_open.contains(c)) {
      final close = matchClose(body, i);
      if (close < 0) break;
      i = close + 1;
      continue;
    }
    i++;
  }
  return members;
}

void _push(List<Member> out, String body, int start, int end) {
  final text = body.substring(start, end);
  if (text.trim().isEmpty || text.trim() == ';') return;
  final m = Member(text, start);
  _classify(m);
  out.add(m);
}

void _classify(Member m) {
  final t = m.text;
  // header: up to first '(' '{' '=' ';' at depth 0 (ignoring annotations' parens)
  var depth = 0;
  var i = 0;
  var end = t.length;
  final n = t.length;
  // skip annotations
  final sb = StringBuffer();
  while (i < n) {
    final c = t[i];
    if (c == '@' && i + 1 < n && RegExp(r'[A-Za-z]').hasMatch(t[i + 1])) {
      // annotation (maybe with args)
      var j = i + 1;
      while (j < n && RegExp(r'[\w.]').hasMatch(t[j])) {
        j++;
      }
      if (t.substring(i + 1, j) == 'interface') {
        sb.write(t.substring(i, j));
        i = j;
        continue;
      }
      var k = j;
      while (k < n && t[k] == ' ') {
        k++;
      }
      if (k < n && t[k] == '(') {
        final cl = matchClose(t, k);
        i = cl < 0 ? n : cl + 1;
      } else {
        i = j;
      }
      sb.write(' ');
      continue;
    }
    if (c == '"') break;
    if (c == '(' || c == '{' || c == '=' || c == ';') {
      if (depth == 0) {
        end = i;
        break;
      }
    }
    sb.write(c);
    i++;
  }
  final head = sb.toString();
  m.header = head.trim();
  final km = _classKw.firstMatch(head);
  if (km != null && !head.contains('=')) {
    m.kind = 'class';
    m.name = km.group(2)!;
    return;
  }
  final afterHeadChar = end < n ? t[end] : ';';
  if (afterHeadChar == '(') {
    // method or ctor: last identifier of header is name
    final nm = RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(head);
    m.name = nm?.group(1) ?? '';
    final tokens = head.trim().split(RegExp(r'\s+'));
    // constructor: no return type -> header (minus modifiers) is a single ident
    final mods = {'public', 'private', 'protected', 'static', 'final', 'abstract', 'synchronized', 'native', 'default', 'strictfp'};
    final rest = tokens.where((e) => !mods.contains(e) && e.isNotEmpty).toList();
    // generic method <T> ...
    m.kind = (rest.length <= 1) ? 'ctor' : 'method';
    return;
  }
  if (afterHeadChar == '{' && head.trim().isEmpty || head.trim() == 'static') {
    m.kind = 'init';
    return;
  }
  // field
  m.kind = 'field';
  // name = last identifier of head
  final nm = RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(head);
  m.name = nm?.group(1) ?? '';
}

class JavaField {
  JavaField(this.name, this.type, this.init, this.modifiers);
  final String name;
  final String type;
  final String init; // initializer expression (trimmed) or ''
  final Set<String> modifiers;
  bool get isStatic => modifiers.contains('static');
}

class JavaMethod {
  JavaMethod(this.name, this.header, this.params, this.body, this.modifiers);
  final String name;
  final String header;
  final String params; // raw parameter list
  final String body; // text inside braces ('' if abstract)
  final Set<String> modifiers;
  bool get isStatic => modifiers.contains('static');
  String get returnType {
    final h = header.replaceAll(RegExp(r'<[^()]*?>\s*(?=[A-Za-z])'), ' ');
    final toks = h.trim().split(RegExp(r'\s+'));
    final mods = {'public', 'private', 'protected', 'static', 'final', 'abstract', 'synchronized'};
    final r = toks.where((e) => !mods.contains(e) && e.isNotEmpty).toList();
    if (r.length < 2) return '';
    return r[r.length - 2];
  }
}

const _modifiers = {
  'public', 'private', 'protected', 'static', 'final', 'abstract', 'synchronized', 'volatile', 'transient', 'native', 'default', 'strictfp'
};

class JavaClass {
  JavaClass({
    required this.name,
    required this.kind,
    required this.file,
    required this.header,
    required this.body,
    this.outer,
  });
  final String name;
  final String kind; // class enum interface record
  final JavaFile file;
  final String header;
  final String body;
  final JavaClass? outer;

  String get qualifiedName => outer == null ? name : '${outer!.qualifiedName}.$name';

  late final String? superName = _superName();
  late final List<String> interfaces = _interfaces();

  /// Header with all `<...>` generic argument lists removed.
  late final String headerNoGenerics = _stripAngles(header);

  static String _stripAngles(String h) {
    final sb = StringBuffer();
    var d = 0;
    for (var i = 0; i < h.length; i++) {
      final c = h[i];
      if (c == '<') {
        d++;
      } else if (c == '>') {
        if (d > 0) d--;
      } else if (d == 0) {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  String? _superName() {
    final m = RegExp(r'\bextends\s+([\w.]+)').firstMatch(headerNoGenerics);
    if (kind == 'interface') return null;
    return m?.group(1);
  }

  List<String> _interfaces() {
    final key = kind == 'interface' ? 'extends' : 'implements';
    final m = RegExp('\\b$key\\s+(.+?)(?:\\bpermits\\b|\$)', dotAll: true).firstMatch(headerNoGenerics);
    if (m == null) return const [];
    return splitTop(m.group(1)!, ',').map((e) => e.trim().replaceAll(RegExp(r'<.*'), '')).where((e) => e.isNotEmpty).toList();
  }

  late final List<Member> members = splitMembers(body, enumHead: kind == 'enum');

  late final List<JavaClass> nested = [
    for (final m in members)
      if (m.kind == 'class') ?_buildNested(m)
  ];

  JavaClass? _buildNested(Member m) {
    final t = m.text;
    final km = _classKw.firstMatch(t);
    if (km == null) return null;
    final ob = t.indexOf('{', km.end);
    if (ob < 0) return null;
    final cb = matchClose(t, ob);
    if (cb < 0) return null;
    return JavaClass(
      name: km.group(2)!,
      kind: km.group(1)!,
      file: file,
      header: t.substring(km.start, ob),
      body: t.substring(ob + 1, cb),
      outer: this,
    );
  }

  late final List<JavaField> fields = _fields();
  late final List<JavaMethod> methods = _methods();
  late final List<JavaMethod> ctors = _ctors();

  List<JavaField> _fields() {
    final out = <JavaField>[];
    for (final m in members) {
      if (m.kind != 'field') continue;
      out.addAll(parseFieldMember(m.text));
    }
    // enum constants are handled separately (enumConstants)
    return out;
  }

  List<JavaMethod> _methods() {
    final out = <JavaMethod>[];
    for (final m in members) {
      if (m.kind != 'method') continue;
      final jm = _parseMethod(m);
      if (jm != null) out.add(jm);
    }
    return out;
  }

  List<JavaMethod> _ctors() {
    final out = <JavaMethod>[];
    for (final m in members) {
      if (m.kind != 'ctor') continue;
      final jm = _parseMethod(m);
      if (jm != null) out.add(jm);
    }
    return out;
  }

  JavaMethod? _parseMethod(Member m) {
    final t = m.text;
    final op = _firstParenAfterHeader(t);
    if (op < 0) return null;
    final cp = matchClose(t, op);
    if (cp < 0) return null;
    final params = t.substring(op + 1, cp);
    var rest = t.substring(cp + 1);
    final ob = rest.indexOf('{');
    var body = '';
    if (ob >= 0 && !rest.substring(0, ob).contains(';')) {
      final cb = matchClose(rest, ob);
      if (cb > 0) body = rest.substring(ob + 1, cb);
    }
    final mods = <String>{};
    for (final w in m.header.split(RegExp(r'\s+'))) {
      if (_modifiers.contains(w)) mods.add(w);
    }
    return JavaMethod(m.name, m.header, params, body, mods);
  }

  int _firstParenAfterHeader(String t) {
    // first '(' not belonging to an annotation
    var i = 0;
    final n = t.length;
    while (i < n) {
      final c = t[i];
      if (c == '@') {
        var j = i + 1;
        while (j < n && RegExp(r'[\w.]').hasMatch(t[j])) {
          j++;
        }
        var k = j;
        while (k < n && t[k] == ' ') {
          k++;
        }
        if (k < n && t[k] == '(') {
          final cl = matchClose(t, k);
          i = cl < 0 ? n : cl + 1;
        } else {
          i = j;
        }
        continue;
      }
      if (c == '(') return i;
      i++;
    }
    return -1;
  }

  /// Enum constants (name -> raw argument text), in declaration order.
  late final List<EnumConstant> enumConstants = _enumConstants();

  List<EnumConstant> _enumConstants() {
    if (kind != 'enum') return const [];
    final first = members.isNotEmpty && members.first.kind == 'enumconsts' ? members.first.text : '';
    final out = <EnumConstant>[];
    for (final part in splitTop(first, ',')) {
      var p = part.trim();
      if (p.isEmpty) continue;
      // strip annotations
      p = p.replaceAll(RegExp(r'@\w+(\([^)]*\))?\s*'), '');
      final m = RegExp(r'^([A-Za-z_]\w*)\s*(\(.*\))?', dotAll: true).firstMatch(p);
      if (m == null) continue;
      var args = '';
      if (m.group(2) != null) {
        final raw = m.group(2)!;
        final cl = matchClose(raw, 0);
        args = cl > 0 ? raw.substring(1, cl) : raw.substring(1);
      }
      out.add(EnumConstant(m.group(1)!, args));
    }
    return out;
  }

  JavaField? field(String n) {
    for (final f in fields) {
      if (f.name == n) return f;
    }
    return null;
  }

  Iterable<JavaMethod> methodsNamed(String n) => methods.where((m) => m.name == n);
}

class EnumConstant {
  EnumConstant(this.name, this.args);
  final String name;
  final String args;
}

List<JavaField> parseFieldMember(String text) {
  var t = text.trim();
  if (t.endsWith(';')) t = t.substring(0, t.length - 1);
  // strip annotations
  var i = 0;
  final sb = StringBuffer();
  final n = t.length;
  while (i < n) {
    if (t[i] == '@' && i + 1 < n && RegExp(r'[A-Za-z]').hasMatch(t[i + 1])) {
      var j = i + 1;
      while (j < n && RegExp(r'[\w.]').hasMatch(t[j])) {
        j++;
      }
      var k = j;
      while (k < n && t[k] == ' ') {
        k++;
      }
      if (k < n && t[k] == '(') {
        final cl = matchClose(t, k);
        i = cl < 0 ? n : cl + 1;
      } else {
        i = j;
      }
      sb.write(' ');
      continue;
    }
    sb.write(t[i]);
    i++;
  }
  t = sb.toString().trim();
  // modifiers
  final mods = <String>{};
  while (true) {
    final m = RegExp(r'^([a-z]+)\s+').firstMatch(t);
    if (m != null && _modifiers.contains(m.group(1))) {
      mods.add(m.group(1)!);
      t = t.substring(m.end);
    } else {
      break;
    }
  }
  // type: identifier with optional generics / arrays
  final tm = RegExp(r'^[\w.]+').firstMatch(t);
  if (tm == null) return const [];
  var p = tm.end;
  if (p < t.length && t[p] == '<') {
    var d = 0;
    var q = p;
    while (q < t.length) {
      if (t[q] == '<') d++;
      if (t[q] == '>') {
        d--;
        if (d == 0) break;
      }
      q++;
    }
    p = q + 1;
  }
  while (p < t.length && (t[p] == '[' || t[p] == ']')) {
    p++;
  }
  final type = t.substring(0, p).trim();
  final rest = t.substring(p).trim();
  final out = <JavaField>[];
  for (final decl in splitTop(rest, ',')) {
    final d = decl.trim();
    if (d.isEmpty) continue;
    final eq = d.indexOf('=');
    final nm = (eq < 0 ? d : d.substring(0, eq)).trim().replaceAll(RegExp(r'\[\s*\]'), '');
    final init = eq < 0 ? '' : d.substring(eq + 1).trim();
    if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(nm)) continue;
    out.add(JavaField(nm, type, init, mods));
  }
  return out;
}

class JavaFile {
  JavaFile(this.path, String raw) : text = stripComments(raw) {
    final pm = RegExp(r'^\s*package\s+([\w.]+)\s*;', multiLine: true).firstMatch(text);
    package = pm?.group(1) ?? '';
    for (final m in RegExp(r'^\s*import\s+(static\s+)?([\w.*]+)\s*;', multiLine: true).allMatches(text)) {
      final isStatic = m.group(1) != null;
      final q = m.group(2)!;
      if (isStatic) {
        staticImports.add(q);
      } else {
        imports[q.substring(q.lastIndexOf('.') + 1)] = q;
      }
    }
  }
  final String path;
  final String text;
  late final String package;
  final Map<String, String> imports = {};
  final List<String> staticImports = [];

  late final List<JavaClass> classes = _topClasses();

  List<JavaClass> _topClasses() {
    // Parse the whole file as a pseudo-body; top-level types are 'class' members.
    final stripped = text;
    final members = splitMembers(stripped);
    final out = <JavaClass>[];
    for (final m in members) {
      if (m.kind != 'class') continue;
      final t = m.text;
      final km = _classKw.firstMatch(t);
      if (km == null) continue;
      final ob = t.indexOf('{', km.end);
      if (ob < 0) continue;
      final cb = matchClose(t, ob);
      if (cb < 0) continue;
      out.add(JavaClass(
        name: km.group(2)!,
        kind: km.group(1)!,
        file: this,
        header: t.substring(km.start, ob),
        body: t.substring(ob + 1, cb),
      ));
    }
    return out;
  }
}

/// Index of all java files under one or more roots.
class SourceIndex {
  SourceIndex(this.roots);
  final List<Directory> roots;
  final Map<String, JavaFile> _filesByPath = {};
  final Map<String, List<String>> _pathsBySimple = {}; // simple class name -> file paths
  final Map<String, String> _pathsByFqn = {};

  void build() {
    for (final r in roots) {
      for (final e in r.listSync(recursive: true, followLinks: false)) {
        if (e is File && e.path.endsWith('.java')) {
          final p = e.path;
          final simple = p.substring(p.lastIndexOf('/') + 1, p.length - 5);
          _pathsBySimple.putIfAbsent(simple, () => []).add(p);
          final rel = p.substring(r.path.length + 1, p.length - 5).replaceAll('/', '.');
          _pathsByFqn[rel] = p;
        }
      }
    }
  }

  JavaFile? fileAt(String path) {
    return _filesByPath.putIfAbsent(path, () => JavaFile(path, File(path).readAsStringSync()));
  }

  JavaFile? fileForFqn(String fqn) {
    final p = _pathsByFqn[fqn];
    return p == null ? null : fileAt(p);
  }

  /// Resolve a (possibly qualified, possibly nested) class name seen in [from].
  JavaClass? resolveClass(String name, JavaFile from, {JavaClass? context}) {
    name = name.replaceAll(RegExp(r'<.*'), '').trim();
    if (name.isEmpty) return null;
    final parts = name.split('.');
    // 1. nested in context chain
    JavaClass? c = _lookupSimple(parts.first, from, context);
    if (c == null) return null;
    for (var i = 1; i < parts.length; i++) {
      final nxt = _findNested(c!, parts[i]);
      if (nxt == null) return null;
      c = nxt;
    }
    return c;
  }

  JavaClass? _findNested(JavaClass c, String name) {
    for (final n in c.nested) {
      if (n.name == name) return n;
    }
    // inherited nested types
    return null;
  }

  JavaClass? _lookupSimple(String simple, JavaFile from, JavaClass? context) {
    // nested classes visible from context (and its outers / supers)
    var ctx = context;
    while (ctx != null) {
      if (ctx.name == simple) return ctx;
      for (final n in ctx.nested) {
        if (n.name == simple) return n;
      }
      ctx = ctx.outer;
    }
    for (final c in from.classes) {
      if (c.name == simple) return c;
      for (final n in c.nested) {
        if (n.name == simple) return n;
      }
    }
    // explicit import
    final imp = from.imports[simple];
    if (imp != null) {
      // maybe nested: a.b.Outer.Inner
      final f = fileForFqn(imp);
      if (f != null) {
        return f.classes.where((c) => c.name == simple).firstOrNull;
      }
      final idx = imp.lastIndexOf('.');
      if (idx > 0) {
        final outer = imp.substring(0, idx);
        final f2 = fileForFqn(outer);
        if (f2 != null) {
          final oc = f2.classes.where((c) => c.name == outer.substring(outer.lastIndexOf('.') + 1)).firstOrNull;
          if (oc != null) {
            return _findNested(oc, simple);
          }
        }
      }
    }
    // same package
    final samePkg = fileForFqn('${from.package}.$simple');
    if (samePkg != null) {
      final c = samePkg.classes.where((c) => c.name == simple).firstOrNull;
      if (c != null) return c;
    }
    // wildcard imports
    for (final m in RegExp(r'^\s*import\s+([\w.]+)\.\*\s*;', multiLine: true).allMatches(from.text)) {
      final f = fileForFqn('${m.group(1)}.$simple');
      if (f != null) return f.classes.where((c) => c.name == simple).firstOrNull;
    }
    // unique simple-name fallback
    final cands = _pathsBySimple[simple];
    if (cands != null && cands.length == 1) {
      final f = fileAt(cands.first);
      return f?.classes.where((c) => c.name == simple).firstOrNull;
    }
    if (cands != null && cands.length > 1) {
      // prefer the one in a Create namespace
      for (final p in cands) {
        if (p.contains('/com/simibubi/create/')) {
          final f = fileAt(p);
          return f?.classes.where((c) => c.name == simple).firstOrNull;
        }
      }
      final f = fileAt(cands.first);
      return f?.classes.where((c) => c.name == simple).firstOrNull;
    }
    return null;
  }

  /// Direct lookup by simple name only (for names that are unique).
  JavaClass? bySimpleName(String simple) {
    final cands = _pathsBySimple[simple];
    if (cands == null) return null;
    for (final p in cands) {
      final f = fileAt(p);
      final c = f?.classes.where((c) => c.name == simple).firstOrNull;
      if (c != null) return c;
    }
    return null;
  }

  Iterable<String> get allSimpleNames => _pathsBySimple.keys;
}

/// Extract the `a.b(c).d(e)` call chain found at the start of [expr].
/// Returns list of (name, args-raw) for each `.name(args)` segment along with
/// the root token (text before the first '.').
class CallChain {
  CallChain(this.root, this.calls);
  final String root;
  final List<MapEntry<String, String>> calls;
  Iterable<String> argsOf(String name) => calls.where((c) => c.key == name).map((c) => c.value);
  bool has(String name) => calls.any((c) => c.key == name);
  String? first(String name) {
    for (final c in calls) {
      if (c.key == name) return c.value;
    }
    return null;
  }
}

/// Parses a fluent chain: `X.foo(a).bar(b)` (possibly `X.foo(a)\n.bar(b)`).
CallChain parseChain(String expr) {
  final t = expr.trim();
  var i = 0;
  final n = t.length;
  // root: up to first '.' + ident + '(' pattern... take identifier path until first '('
  final rootBuf = StringBuffer();
  final calls = <MapEntry<String, String>>[];
  // Scan tokens
  var pos = 0;
  while (pos < n) {
    // read ident path segment
    final m = RegExp(r'\s*\.?\s*([A-Za-z_]\w*)\s*(<[^()]*?>)?\s*(\()?').matchAsPrefix(t, pos);
    if (m == null) break;
    final name = m.group(1)!;
    if (m.group(3) != null) {
      final op = m.end - 1;
      final cl = matchClose(t, op);
      if (cl < 0) break;
      calls.add(MapEntry(name, t.substring(op + 1, cl)));
      pos = cl + 1;
    } else {
      if (calls.isEmpty) {
        if (rootBuf.isNotEmpty) rootBuf.write('.');
        rootBuf.write(name);
      } else {
        break;
      }
      pos = m.end;
    }
    i = pos;
  }
  return CallChain(rootBuf.toString(), calls);
}

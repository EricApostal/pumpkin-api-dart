// Decoder for Minecraft/Catnip/Create `StreamCodec` expressions. It turns the
// Java source of a codec into a [NetType] tree (see lib/src/manifest/types_network.dart).
// Anything it cannot resolve is recorded in [Decoder.issues] so the caller can
// mark the payload `verified: false`.
import 'java.dart';
import '../../lib/src/manifest/types_network.dart';

class CodecCtx {
  CodecCtx(this.file, this.cls, [this.env = const {}]);
  final JavaFile file;
  final JavaClass? cls;
  final Map<String, NetType> env;
}

class Seg {
  Seg(this.name, [this.args]);
  final String name;
  final String? args;
}

List<Seg>? parseSegs(String e) {
  final t = e.trim();
  final n = t.length;
  var i = 0;
  final segs = <Seg>[];
  void ws() {
    while (i < n && t[i].trim().isEmpty) {
      i++;
    }
  }

  while (i < n) {
    ws();
    if (i < n && t[i] == '.') i++;
    ws();
    if (i < n && t[i] == '<') {
      var d = 0;
      while (i < n) {
        if (t[i] == '<') d++;
        if (t[i] == '>') {
          d--;
          if (d == 0) {
            i++;
            break;
          }
        }
        i++;
      }
      ws();
    }
    final m = RegExp(r'[A-Za-z_$][\w$]*').matchAsPrefix(t, i);
    if (m == null) return null;
    final name = m.group(0)!;
    i = m.end;
    ws();
    String? args;
    if (i < n && t[i] == '(') {
      final cl = matchClose(t, i);
      if (cl < 0) return null;
      args = t.substring(i + 1, cl);
      i = cl + 1;
    }
    segs.add(Seg(name, args));
    ws();
    if (i < n && t[i] != '.') return null;
  }
  return segs;
}

// ---------------------------------------------------------------- leaves

const _bool = NetType(NetKind.bool);
const _int = NetType(NetKind.int);
const _varint = NetType(NetKind.varint);

final Map<String, NetType> leafTable = {
  'ByteBufCodecs.BOOL': _bool,
  'ByteBufCodecs.BYTE': const NetType(NetKind.byte),
  'ByteBufCodecs.SHORT': const NetType(NetKind.short),
  'ByteBufCodecs.UNSIGNED_SHORT': const NetType(NetKind.short, className: 'unsigned'),
  'ByteBufCodecs.INT': _int,
  'ByteBufCodecs.LONG': const NetType(NetKind.long),
  'ByteBufCodecs.FLOAT': const NetType(NetKind.float),
  'ByteBufCodecs.DOUBLE': const NetType(NetKind.double),
  'ByteBufCodecs.VAR_INT': _varint,
  'ByteBufCodecs.VAR_LONG': const NetType(NetKind.varlong),
  'ByteBufCodecs.STRING_UTF8': const NetType(NetKind.string, maxLength: 32767),
  'ByteBufCodecs.COMPOUND_TAG': const NetType(NetKind.nbtCompound),
  'ByteBufCodecs.TAG': const NetType(NetKind.nbtTag),
  'ByteBufCodecs.OPTIONAL_COMPOUND_TAG': const NetType(NetKind.optional, element: NetType(NetKind.nbtCompound), nullable: true),
  'ByteBufCodecs.BYTE_ARRAY': const NetType(NetKind.bytes),
  'UUIDUtil.STREAM_CODEC': const NetType(NetKind.uuid),
  'BlockPos.STREAM_CODEC': const NetType(NetKind.blockPos),
  'Identifier.STREAM_CODEC': const NetType(NetKind.resourceLocation),
  'ResourceLocation.STREAM_CODEC': const NetType(NetKind.resourceLocation),
  'Direction.STREAM_CODEC': const NetType(NetKind.direction),
  'ItemStack.STREAM_CODEC': const NetType(NetKind.itemStack),
  'ItemStack.OPTIONAL_STREAM_CODEC': const NetType(NetKind.itemStackOptional),
  'ItemStack.OPTIONAL_LIST_STREAM_CODEC': const NetType(NetKind.list, element: NetType(NetKind.itemStackOptional)),
  'ItemStack.LIST_STREAM_CODEC': const NetType(NetKind.list, element: NetType(NetKind.itemStack)),
  'FluidStack.STREAM_CODEC': const NetType(NetKind.fluidStack),
  'FluidStack.OPTIONAL_STREAM_CODEC': const NetType(NetKind.fluidStackOptional),
  'ComponentSerialization.STREAM_CODEC': const NetType(NetKind.component),
  'ComponentSerialization.TRUSTED_STREAM_CODEC': const NetType(NetKind.component),
  'CatnipStreamCodecs.VEC3': const NetType(NetKind.vec3),
  'CatnipStreamCodecs.VEC3I': const NetType(NetKind.vec3i),
  'CatnipStreamCodecs.HAND': const NetType(NetKind.bool, className: 'InteractionHand'),
  'CatnipStreamCodecs.CHAR': const NetType(NetKind.short, className: 'char'),
  'CatnipStreamCodecs.BLOCK_STATE': const NetType(NetKind.blockState),
  'CatnipStreamCodecs.NULLABLE_BLOCK_POS': const NetType(NetKind.optional, element: NetType(NetKind.blockPos), nullable: true),
  'CatnipStreamCodecs.COMPOUND_LIST_TAG': const NetType(NetKind.list, element: NetType(NetKind.nbtCompound)),
  'CatnipStreamCodecs.COMPOUND_AS_TAG': const NetType(NetKind.nbtCompound),
  'CatnipStreamCodecs.ROTATION': const NetType(NetKind.enumeration, className: 'Rotation'),
  'CatnipStreamCodecs.MIRROR': const NetType(NetKind.enumeration, className: 'Mirror'),
  'CatnipStreamCodecs.AXIS': const NetType(NetKind.enumeration, className: 'Direction.Axis'),
  'CatnipStreamCodecs.FLUID': const NetType(NetKind.varint, className: 'Fluid'),
  'CatnipStreamCodecs.HOLDER_FLUID': const NetType(NetKind.varint, className: 'Holder<Fluid>'),
};

const _instanceOps = {'map', 'apply', 'dispatch', 'cast', 'flatMap', 'mapStream'};

String _last2(String q) {
  final p = q.split('.');
  return p.length <= 2 ? q : p.sublist(p.length - 2).join('.');
}

int? _maxOf(String? arg) {
  if (arg == null) return null;
  final v = int.tryParse(arg.trim().replaceAll('_', ''));
  return v;
}

NetType _copyName(NetType t, String className) => NetType(
      t.kind,
      element: t.element,
      key: t.key,
      value: t.value,
      className: className,
      fields: t.fields,
      maxLength: t.maxLength,
      nullable: t.nullable,
    );

String getterName(String g, int index) {
  g = g.trim();
  var m = RegExp(r'::\s*(?:get|is)?([A-Za-z_]\w*)$').firstMatch(g);
  if (m != null) {
    final raw = RegExp(r'::\s*([A-Za-z_]\w*)$').firstMatch(g)!.group(1)!;
    final stripped = RegExp(r'^(get|is)([A-Z]\w*)$').firstMatch(raw);
    if (stripped != null) {
      final s = stripped.group(2)!;
      return s[0].toLowerCase() + s.substring(1);
    }
    return raw;
  }
  m = RegExp(r'->\s*[\w.]*?\b\w+\.([A-Za-z_]\w*)\s*(\(\s*\))?$').firstMatch(g);
  if (m != null) {
    final raw = m.group(1)!;
    if (m.group(2) != null) {
      final stripped = RegExp(r'^(get|is)([A-Z]\w*)$').firstMatch(raw);
      if (stripped != null) {
        final s = stripped.group(2)!;
        return s[0].toLowerCase() + s.substring(1);
      }
    }
    return raw;
  }
  return 'field$index';
}

class Decoder {
  Decoder(this.idx);
  final SourceIndex idx;
  final List<String> issues = [];
  int _depth = 0;
  final Set<String> _active = {};

  NetType _unresolved(String what, [String? className]) {
    issues.add(what);
    return NetType(NetKind.custom, className: className ?? '?');
  }

  /// Decodes a codec expression to its wire type.
  NetType decode(String expr, CodecCtx c) {
    final segs = parseSegs(expr);
    if (segs == null || segs.isEmpty) return _unresolved('cannot parse codec expression: ${expr.replaceAll(RegExp(r"\s+"), " ")}');
    return _decodeSegs(segs, c, expr);
  }

  NetType _decodeSegs(List<Seg> segs, CodecCtx c, String raw) {
    NetType? cur;
    final q = <String>[];
    for (final s in segs) {
      if (s.args == null) {
        if (cur != null) return _unresolved('unexpected member after call in: $raw');
        q.add(s.name);
        continue;
      }
      if (cur == null) {
        if (q.isNotEmpty && _instanceOps.contains(s.name) && !RegExp(r'^[A-Z][a-z]').hasMatch(q.last)) {
          cur = _ref(q.join('.'), c);
          cur = _instance(cur, s.name, s.args!, c);
        } else {
          cur = _static(q.join('.'), s.name, s.args!, c);
        }
        q.clear();
      } else {
        cur = _instance(cur, s.name, s.args!, c);
      }
    }
    return cur ?? _ref(q.join('.'), c);
  }

  NetType _instance(NetType cur, String op, String args, CodecCtx c) {
    switch (op) {
      case 'map':
      case 'cast':
      case 'flatMap':
      case 'mapStream':
        return cur;
      case 'apply':
        final segs = parseSegs(args);
        if (segs == null || segs.isEmpty || segs.last.args == null) return _unresolved('unknown apply(): $args');
        final last = segs.last;
        final a = splitArgs(last.args!);
        switch (last.name) {
          case 'list':
          case 'nonNullList':
            return NetType(NetKind.list, element: cur, maxLength: a.isEmpty ? null : _maxOf(a.first));
          case 'vector':
            return NetType(NetKind.list, element: cur, className: 'Vector');
          case 'optional':
            return NetType(NetKind.optional, element: cur);
          case 'nullable':
            return NetType(NetKind.optional, element: cur, nullable: true);
        }
        return _unresolved('unknown codec operation: ${last.name}()');
      case 'dispatch':
        return _unresolved('dispatch codec (tagged union)', 'dispatch');
    }
    return _unresolved('unknown instance codec call .$op()');
  }

  NetType _composite(String args, CodecCtx c) {
    final parts = splitArgs(args);
    final fields = <NetField>[];
    final n = parts.length - 1; // last = constructor
    if (n < 0 || n.isOdd) {
      return _unresolved('composite() with odd argument count');
    }
    for (var i = 0; i < n; i += 2) {
      final t = decode(parts[i], c);
      fields.add(NetField(getterName(parts[i + 1], i ~/ 2), t));
    }
    return NetType(NetKind.custom, fields: fields);
  }

  NetType _static(String q, String name, String args, CodecCtx c) {
    final key = q.isEmpty ? name : '${_last2(q)}.$name';
    final a = splitArgs(args);
    switch (name) {
      case 'composite':
        if (q.endsWith('StreamCodec') || q.endsWith('StreamCodecs') || q.endsWith('CatnipLargerStreamCodecs')) {
          return _composite(args, c);
        }
        break;
      case 'unit':
        if (q.endsWith('StreamCodec')) return const NetType(NetKind.custom, fields: []);
        break;
      case 'of':
        if (q.endsWith('StreamCodec')) {
          if (args.contains('writeWithCodec')) return const NetType(NetKind.nbtTag, className: 'codec-as-nbt');
          return _unresolved('StreamCodec.of(...) with hand written encode/decode', 'custom-codec');
        }
        break;
      case 'stringUtf8':
        return NetType(NetKind.string, maxLength: _maxOf(a.isEmpty ? null : a.first));
      case 'byteArray':
        return NetType(NetKind.bytes, maxLength: _maxOf(a.isEmpty ? null : a.first));
      case 'nullable':
        if (q.endsWith('CatnipStreamCodecBuilders') && a.length == 1) {
          return NetType(NetKind.optional, element: decode(a[0], c), nullable: true);
        }
        break;
      case 'optional':
        if (q.endsWith('ByteBufCodecs') && a.length == 1) return NetType(NetKind.optional, element: decode(a[0], c));
        break;
      case 'list':
      case 'nonNullList':
        if ((q.endsWith('CatnipStreamCodecBuilders')) && a.isNotEmpty) {
          return NetType(NetKind.list, element: decode(a[0], c), maxLength: a.length > 1 ? _maxOf(a[1]) : null);
        }
        break;
      case 'collection':
        if (q.endsWith('ByteBufCodecs') && a.length >= 2) {
          return NetType(NetKind.list, element: decode(a[1], c), maxLength: a.length > 2 ? _maxOf(a[2]) : null);
        }
        break;
      case 'array':
        if (q.endsWith('CatnipStreamCodecBuilders') && a.isNotEmpty) return NetType(NetKind.list, element: decode(a[0], c));
        break;
      case 'map':
        if (q.endsWith('ByteBufCodecs') && a.length >= 3) {
          return NetType(NetKind.map, key: decode(a[1], c), value: decode(a[2], c), maxLength: a.length > 3 ? _maxOf(a[3]) : null);
        }
        break;
      case 'pair':
        if (q.endsWith('CatnipStreamCodecBuilders') && a.length == 2) {
          return NetType(NetKind.custom, className: 'Pair', fields: [
            NetField('first', decode(a[0], c)),
            NetField('second', decode(a[1], c)),
          ]);
        }
        break;
      case 'either':
        if (q.endsWith('ByteBufCodecs') && a.length == 2) {
          return NetType(NetKind.either, key: decode(a[0], c), value: decode(a[1], c));
        }
        break;
      case 'ofEnum':
      case 'enumCodec':
        final m = RegExp(r'^([\w.]+)\.class$').firstMatch(a.isEmpty ? '' : a[0]);
        if (m != null) {
          final cls = idx.resolveClass(m.group(1)!, c.file, context: c.cls);
          return NetType(NetKind.enumeration, className: cls?.qualifiedName ?? m.group(1));
        }
        break;
      case 'idMapper':
        if (q.endsWith('ByteBufCodecs')) return const NetType(NetKind.varint, className: 'idMapper');
        break;
      case 'registry':
      case 'holderRegistry':
        if (q.endsWith('ByteBufCodecs')) return NetType(NetKind.varint, className: 'registry:${a.isEmpty ? "" : a[0]}');
        break;
      case 'streamCodec':
        if (q.endsWith('ResourceKey')) return NetType(NetKind.resourceLocation, className: 'ResourceKey<${a.isEmpty ? "" : a[0]}>');
        break;
      case 'ofLegacyNbtWithRegistries':
        return const NetType(NetKind.nbtTag, className: 'legacyNbtWithRegistries');
      case 'tagKey':
        if (q.endsWith('CatnipStreamCodecBuilders')) return const NetType(NetKind.resourceLocation, className: 'TagKey');
        break;
    }
    // user defined static helper (e.g. IntAttached.streamCodec(x), codec(Foo::new))
    final found = _findMethod(q, name, c);
    if (found != null) return _callMethod(found.$1, found.$2, a, c, key);
    return _unresolved('unresolved codec call $key(...)', key);
  }

  (JavaClass, JavaMethod)? _findMethod(String q, String name, CodecCtx c) {
    JavaClass? start;
    if (q.isEmpty) {
      start = c.cls;
    } else {
      start = idx.resolveClass(q, c.file, context: c.cls);
      if (start == null) return null;
    }
    var cls = start;
    final seen = <String>{};
    while (cls != null && seen.add(cls.qualifiedName)) {
      for (final m in cls.methodsNamed(name)) {
        if (m.isStatic) return (cls, m);
      }
      // unqualified: also look in outer classes, then super classes
      if (q.isEmpty && cls.outer != null) {
        final o = cls.outer!;
        for (final m in o.methodsNamed(name)) {
          if (m.isStatic) return (o, m);
        }
        // outer's supers handled via loop below on outer chain
      }
      final sn = cls.superName;
      JavaClass? next;
      if (sn != null) next = idx.resolveClass(sn, cls.file, context: cls);
      if (next == null && q.isEmpty && cls.outer != null) next = cls.outer;
      cls = next;
    }
    return null;
  }

  List<String> _paramNames(String params, List<String> typesOut) {
    var p = params;
    var prev = '';
    while (prev != p) {
      prev = p;
      p = p.replaceAll(RegExp(r'<[^<>]*>'), '');
    }
    final names = <String>[];
    for (final part in p.split(',')) {
      final toks = part.trim().split(RegExp(r'\s+'));
      if (toks.isEmpty || toks.first.isEmpty) continue;
      names.add(toks.last);
      typesOut.add(part.trim());
    }
    return names;
  }

  NetType _callMethod(JavaClass cls, JavaMethod m, List<String> args, CodecCtx caller, String key) {
    final types = <String>[];
    final names = _paramNames(m.params, types);
    // also the raw (generic-bearing) type text for StreamCodec detection
    final env = <String, NetType>{};
    final rawParams = splitArgs(m.params);
    for (var i = 0; i < names.length && i < args.length; i++) {
      final raw = i < rawParams.length ? rawParams[i] : types[i];
      if (raw.contains('StreamCodec') || raw.contains('CodecOperation')) {
        env[names[i]] = decode(args[i], caller);
      }
    }
    final body = m.body.trim();
    final rm = RegExp(r'^return\s+([\s\S]*?);?\s*$').firstMatch(body);
    if (rm == null) return _unresolved('helper $key is not a single return statement');
    final guard = 'M:${cls.qualifiedName}.${m.name}:${env.hashCode}';
    if (_depth > 8) return _unresolved('codec nesting too deep at $key');
    _depth++;
    try {
      return decode(rm.group(1)!, CodecCtx(cls.file, cls, env));
    } finally {
      _depth--;
      _active.remove(guard);
    }
  }

  JavaField? _findField(JavaClass cls, String name) {
    final seen = <String>{};
    JavaClass? cur = cls;
    while (cur != null && seen.add(cur.qualifiedName)) {
      final f = cur.field(name);
      if (f != null) return f;
      final sn = cur.superName;
      cur = sn == null ? null : idx.resolveClass(sn, cur.file, context: cur);
    }
    return null;
  }

  NetType _ref(String q, CodecCtx c) {
    if (q.isEmpty) return _unresolved('empty codec reference');
    if (c.env.containsKey(q)) return c.env[q]!;
    final l2 = _last2(q);
    if (leafTable.containsKey(l2)) return leafTable[l2]!;
    final parts = q.split('.');
    JavaClass? cls;
    String member;
    if (parts.length == 1) {
      member = parts[0];
      // unqualified: search enclosing classes and their supers
      var ctx = c.cls;
      JavaField? f;
      while (ctx != null && f == null) {
        f = _findField(ctx, member);
        if (f != null) {
          cls = ctx;
          break;
        }
        ctx = ctx.outer;
      }
      if (f == null) return _unresolved('unresolved codec reference $q');
    } else {
      member = parts.last;
      final clsName = parts.sublist(0, parts.length - 1).join('.');
      cls = idx.resolveClass(clsName, c.file, context: c.cls);
      if (cls == null) return _unresolved('unresolved class $clsName for codec $q', q);
    }
    final f = _findField(cls!, member);
    if (f == null || f.init.isEmpty) {
      if (cls.kind == 'enum') {
        issues.add('enum ${cls.qualifiedName} has no $member field; assumed ordinal');
        return NetType(NetKind.enumeration, className: cls.qualifiedName);
      }
      return _unresolved('class ${cls.qualifiedName} has no codec field $member', q);
    }
    final key = '${cls.qualifiedName}.$member';
    if (_active.contains(key)) return _unresolved('recursive codec $key', cls.qualifiedName);
    if (_depth > 8) return _unresolved('codec nesting too deep at $key', cls.qualifiedName);
    _active.add(key);
    _depth++;
    NetType r;
    try {
      r = decode(f.init, CodecCtx(cls.file, cls));
    } finally {
      _depth--;
      _active.remove(key);
    }
    if (r.className == null && RegExp(r'CODEC$|^CODEC', caseSensitive: false).hasMatch(member)) {
      r = _copyName(r, cls.qualifiedName);
    }
    return r;
  }
}

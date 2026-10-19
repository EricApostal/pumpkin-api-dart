// Config defaults (infrastructure/config/*), stress table (AllBlocks +
// BuilderTransformers) and tag json extraction.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../lib/src/manifest/types_network.dart';
import 'expr.dart';
import 'java.dart';

class ConfigResult {
  ConfigResult(this.entries, this.stress, this.constants, this.log);
  final List<ConfigEntry> entries;
  final List<StressEntry> stress;
  final Map<String, Object> constants;
  final List<String> log;
}

class TagResult {
  TagResult(this.tags, this.fileCount);
  final List<TagDef> tags;
  final int fileCount;
}

/// The double a Java `float` widens to (what ModConfigSpec actually stores).
double _f32(double v) {
  final b = ByteData(4)..setFloat32(0, v);
  return b.getFloat32(0);
}

const _intMax = 2147483647;
const _intMin = -2147483648;
const _floatMax = 3.4028234663852886e+38;

class _Item {
  _Item(this.kind, this.name, {this.depth = 0});
  final String kind; // value | group | nested
  String name;
  final int depth;
  ConfigValueType? type;
  Object? def;
  num? min, max;
  String? enumClass;
  List<String>? enumValues;
  List<String> comment = [];
  String javaField = '';
  JavaClass? nestedClass;
}

Object? _resolveConst(String id, JavaClass cls, Map<String, String> comments) {
  switch (id) {
    case 'Integer.MAX_VALUE':
      return _intMax;
    case 'Integer.MIN_VALUE':
      return _intMin;
    case 'Float.MAX_VALUE':
      return _floatMax;
    case 'Double.MAX_VALUE':
      return double.maxFinite;
  }
  if (id.startsWith('Comments.')) return comments[id.substring(9)];
  if (!id.contains('.')) {
    final f = cls.field(id);
    if (f != null && f.init.isNotEmpty) return _eval(f.init, cls, comments);
  }
  return null;
}

Object? _eval(String expr, JavaClass cls, Map<String, String> comments) {
  return evalWith(expr, const {}, fallback: (id) => _resolveConst(id, cls, comments));
}

Map<String, String> _commentsOf(JavaClass cls) {
  final out = <String, String>{};
  for (final n in cls.nested) {
    if (n.name != 'Comments') continue;
    for (final f in n.fields) {
      if (f.init.isEmpty) continue;
      final v = evalWith(f.init, const {}, fallback: (id) => id.startsWith('Comments.') ? out[id.substring(9)] : null);
      if (v is String) out[f.name] = v;
    }
  }
  return out;
}

String _configName(JavaClass cls, List<String> log) {
  for (final m in cls.methodsNamed('getName')) {
    final r = RegExp(r'return\s+([\s\S]*?);').firstMatch(m.body);
    if (r != null) {
      final v = _eval(r.group(1)!, cls, _commentsOf(cls));
      if (v is String) return v;
    }
  }
  log.add('cannot resolve getName() of ${cls.name}');
  return cls.name;
}

List<_Item> _items(JavaClass cls, SourceIndex idx, List<String> log) {
  final comments = _commentsOf(cls);
  final items = <_Item>[];
  num num0(String a, String where) {
    final v = _eval(a, cls, comments);
    if (v is num) return v;
    log.add('$where: cannot evaluate number `$a`');
    return 0;
  }

  String cm(String a, String where) {
    final lit = stringLiteral(a);
    if (lit != null) return lit;
    final v = _eval(a, cls, comments);
    if (v is String) return v;
    log.add('$where: cannot resolve comment `$a`');
    return a;
  }

  for (final f in cls.fields) {
    if (f.isStatic) continue;
    final init = f.init.trim();
    final m = RegExp(r'^(b|i|f|e|group|nested)\s*\(').firstMatch(init);
    if (m == null) continue;
    final kind = m.group(1)!;
    final close = matchClose(init, m.end - 1);
    final args = splitArgs(init.substring(m.end, close));
    final where = '${cls.name}.${f.name}';
    if (kind == 'group') {
      final it = _Item('group', stringLiteral(args[1]) ?? args[1], depth: num0(args[0], where).toInt());
      it.comment = args.skip(2).map((a) => cm(a, where)).toList();
      items.add(it);
    } else if (kind == 'nested') {
      final depth = num0(args[0], where).toInt();
      final cn = RegExp(r'^(\w+)::new$').firstMatch(args[1])!.group(1)!;
      final child = idx.resolveClass(cn, cls.file, context: cls);
      if (child == null) {
        log.add('cannot resolve nested config $cn');
        continue;
      }
      final it = _Item('nested', _configName(child, log), depth: depth)..nestedClass = child;
      it.comment = args.skip(2).map((a) => cm(a, where)).toList();
      items.add(it);
    } else {
      final nameIdx = args.indexWhere((a) => stringLiteral(a) != null);
      if (nameIdx < 0) {
        log.add('$where: no name literal');
        continue;
      }
      final it = _Item('value', stringLiteral(args[nameIdx])!)..javaField = f.name;
      final lead = args.sublist(0, nameIdx);
      it.comment = args.skip(nameIdx + 1).map((a) => cm(a, where)).toList();
      switch (kind) {
        case 'b':
          it.type = ConfigValueType.boolean;
          it.def = args[0].trim() == 'true';
        case 'i':
          it.type = ConfigValueType.integer;
          it.def = num0(lead[0], where).toInt();
          it.min = lead.length >= 2 ? num0(lead[1], where).toInt() : _intMin;
          it.max = lead.length >= 3 ? num0(lead[2], where).toInt() : _intMax;
        case 'f':
          it.type = ConfigValueType.decimal;
          it.def = _f32(num0(lead[0], where).toDouble());
          it.min = _f32(lead.length >= 2 ? num0(lead[1], where).toDouble() : -_floatMax);
          it.max = _f32(lead.length >= 3 ? num0(lead[2], where).toDouble() : _floatMax);
        case 'e':
          it.type = ConfigValueType.enumeration;
          final em = RegExp(r'^([\w.]+)\.(\w+)$').firstMatch(lead[0].trim());
          if (em == null) {
            log.add('$where: cannot parse enum default `${lead[0]}`');
            continue;
          }
          final ecls = idx.resolveClass(em.group(1)!, cls.file, context: cls);
          it.enumClass = ecls?.qualifiedName ?? em.group(1);
          it.def = em.group(2)!;
          it.enumValues = ecls?.enumConstants.map((e) => e.name).toList();
          if (ecls == null) log.add('$where: enum ${em.group(1)} not resolved');
      }
      items.add(it);
    }
  }
  return items;
}

class _Builder {
  _Builder(this.idx, this.log, this.stress);
  final SourceIndex idx;
  final List<String> log;
  final List<StressEntry> stress;
  final List<ConfigEntry> entries = [];
  final List<String> stack = [];
  final Map<String, int> depth = {};

  void pop(int n) {
    for (var i = 0; i < n && stack.isNotEmpty; i++) {
      stack.removeLast();
    }
  }

  void registerAll(JavaClass cls, ConfigSide side) {
    final key = cls.qualifiedName;
    if (cls.name == 'CStress') {
      _registerStress(cls, side);
      return;
    }
    for (final it in _items(cls, idx, log)) {
      switch (it.kind) {
        case 'group':
          final d = depth[key] ?? 0;
          if (d > it.depth) pop(d - it.depth);
          depth[key] = it.depth;
          stack.add(it.name);
          depth[key] = it.depth + 1;
        case 'nested':
          // the nested() helper first creates a group named like the child config...
          {
            final d = depth[key] ?? 0;
            if (d > it.depth) pop(d - it.depth);
            depth[key] = it.depth;
            stack.add(it.name);
            depth[key] = it.depth + 1;
          }
          // ...then a marker that registers the child in place.
          final child = it.nestedClass!;
          depth[child.qualifiedName] = it.depth;
          registerAll(child, side);
          final cd = depth[child.qualifiedName]!;
          if (cd > it.depth) pop(cd - it.depth);
        default:
          final path = [...stack, it.name].join('.');
          entries.add(ConfigEntry(
            side: side,
            path: path,
            type: it.type!,
            defaultValue: it.def!,
            javaClass: cls.name,
            javaField: it.javaField,
            min: it.type == ConfigValueType.integer || it.type == ConfigValueType.decimal ? it.min : null,
            max: it.type == ConfigValueType.integer || it.type == ConfigValueType.decimal ? it.max : null,
            enumClass: it.enumClass,
            enumValues: it.enumValues,
            comment: it.comment,
          ));
      }
    }
  }

  void _registerStress(JavaClass cls, ConfigSide side) {
    final comments = _commentsOf(cls);
    void section(String name, double? Function(StressEntry) get, String field) {
      stack.add(name);
      for (final s in stress) {
        final v = get(s);
        if (v == null) continue;
        entries.add(ConfigEntry(
          side: side,
          path: [...stack, s.block].join('.'),
          type: ConfigValueType.decimal,
          defaultValue: v,
          javaClass: cls.name,
          javaField: field,
          comment: ['[in Stress Units]', name == 'impact' ? comments['impact']! : comments['capacity']!],
        ));
      }
      pop(1);
    }

    section('impact', (s) => s.impact, 'impacts');
    section('capacity', (s) => s.capacity, 'capacities');
  }
}

// ----------------------------------------------------------------- stress

class _Op {
  _Op(this.kind, this.value, [this.value2]);
  final String kind; // impact | capacity | rpm
  final double value;
  final bool? value2;
}

List<_Op> _scanOps(String text, JavaClass? helpers, Set<String> helperNames, SourceIndex idx, JavaClass owner, int depth) {
  final ops = <_Op>[];
  final re = RegExp(r'CStress\.setNoImpact\s*\(\s*\)|CStress\.setImpact\s*\(|CStress\.setCapacity\s*\(|setGeneratorSpeed\s*\('
      r'|BuilderTransformers\.(\w+)\s*\(|\b(\w+)\s*\(');
  for (final m in re.allMatches(text)) {
    final s = m.group(0)!;
    double numArg(String a) {
      final v = evalWith(a, const {}, fallback: (id) => null);
      return v is num ? v.toDouble() : double.nan;
    }

    String argsAt() {
      final open = m.end - 1;
      final cl = matchClose(text, open);
      return cl < 0 ? '' : text.substring(open + 1, cl);
    }

    if (s.startsWith('CStress.setNoImpact')) {
      ops.add(_Op('impact', 0));
    } else if (s.startsWith('CStress.setImpact')) {
      ops.add(_Op('impact', numArg(argsAt())));
    } else if (s.startsWith('CStress.setCapacity')) {
      ops.add(_Op('capacity', numArg(argsAt())));
    } else if (s.startsWith('setGeneratorSpeed')) {
      final a = splitArgs(argsAt());
      ops.add(_Op('rpm', numArg(a[0]), a.length > 1 ? a[1].trim() == 'true' : false));
    } else if (m.group(1) != null && helpers != null && depth < 5) {
      final name = m.group(1)!;
      for (final meth in helpers.methodsNamed(name)) {
        ops.addAll(_scanOps(meth.body, helpers, helperNames, idx, owner, depth + 1));
        break;
      }
    } else if (m.group(2) != null && helpers != null && depth >= 1 && depth < 5 && helperNames.contains(m.group(2)!)) {
      // call of another helper inside BuilderTransformers
      final name = m.group(2)!;
      for (final meth in helpers.methodsNamed(name)) {
        // avoid self-recursion on the declaration itself (we only scan bodies)
        ops.addAll(_scanOps(meth.body, helpers, helperNames, idx, owner, depth + 1));
        break;
      }
    }
  }
  return ops;
}

List<StressEntry> _extractStress(SourceIndex idx, String root, List<String> log) {
  final all = idx.fileAt('$root/src/main/java/com/simibubi/create/AllBlocks.java')!;
  final allBlocks = all.classes.firstWhere((c) => c.name == 'AllBlocks');
  final bt = idx.fileAt('$root/src/main/java/com/simibubi/create/foundation/data/BuilderTransformers.java')!;
  final btc = bt.classes.firstWhere((c) => c.name == 'BuilderTransformers');
  final names = {for (final m in btc.methods) m.name};
  final byBlock = <String, double?>{};
  final impact = <String, double>{};
  final capacity = <String, double>{};
  final rpm = <String, int>{};
  final less = <String, bool>{};
  final order = <String>[];
  var blockCount = 0;
  for (final f in allBlocks.fields) {
    final m = RegExp(r'\.block\(\s*"([^"]+)"').firstMatch(f.init);
    if (m == null) continue;
    blockCount++;
    final name = m.group(1)!;
    final ops = _scanOps(f.init, btc, names, idx, allBlocks, 0);
    for (final op in ops) {
      if (op.value.isNaN) {
        log.add('stress: non numeric argument for $name (${op.kind})');
        continue;
      }
      if (!order.contains(name)) order.add(name);
      switch (op.kind) {
        case 'impact':
          impact[name] = op.value;
        case 'capacity':
          capacity[name] = op.value;
        case 'rpm':
          rpm[name] = op.value.toInt();
          less[name] = op.value2 ?? false;
      }
    }
  }
  byBlock.clear();
  log.add('stress: scanned $blockCount block declarations in AllBlocks');
  return [
    for (final n in order)
      StressEntry(n,
          impact: impact[n],
          capacity: capacity[n],
          generatedRpm: rpm[n],
          mayGenerateLess: rpm.containsKey(n) ? less[n] : null),
  ];
}

ConfigResult extractConfig(String root) {
  final log = <String>[];
  final idx = SourceIndex([Directory('$root/src/main/java')])..build();
  final stress = _extractStress(idx, root, log);
  final b = _Builder(idx, log, stress);
  final cfgDir = '$root/src/main/java/com/simibubi/create/infrastructure/config';
  for (final entry in const [
    ('CServer', ConfigSide.server),
    ('CCommon', ConfigSide.common),
    ('CClient', ConfigSide.client),
  ]) {
    final f = idx.fileAt('$cfgDir/${entry.$1}.java')!;
    final cls = f.classes.firstWhere((c) => c.name == entry.$1);
    b.stack.clear();
    b.depth.clear();
    b.depth[cls.qualifiedName] = 0;
    b.registerAll(cls, entry.$2);
  }
  // constants
  final constants = <String, Object>{};
  ConfigEntry? e(String path) {
    for (final x in b.entries) {
      if (x.side == ConfigSide.server && x.path == path) return x;
    }
    return null;
  }

  final mrs = e('kinetics.maxRotationSpeed');
  if (mrs != null) {
    constants['maxRotationSpeedDefault'] = mrs.defaultValue;
    constants['maxRotationSpeedMin'] = mrs.min!;
  }
  int? fieldInt(String file, String cls, String field) {
    final jf = idx.fileAt('$root/src/main/java/$file');
    final c = jf?.classes.where((c) => c.name == cls).firstOrNull;
    final fl = c?.field(field);
    final v = fl == null ? null : evalWith(fl.init, const {}, fallback: (id) => null);
    return v is int ? v : null;
  }

  final cm = 'com/simibubi/create/content/kinetics/motor/CreativeMotorBlockEntity.java';
  final sc = 'com/simibubi/create/content/kinetics/speedController/SpeedControllerBlockEntity.java';
  final cs = 'com/simibubi/create/infrastructure/config/CStress.java';
  void c(String name, int? v) {
    if (v != null) constants[name] = v;
  }

  c('creativeMotorMaxSpeed', fieldInt(cm, 'CreativeMotorBlockEntity', 'MAX_SPEED'));
  c('creativeMotorDefaultSpeed', fieldInt(cm, 'CreativeMotorBlockEntity', 'DEFAULT_SPEED'));
  c('speedControllerDefaultSpeed', fieldInt(sc, 'SpeedControllerBlockEntity', 'DEFAULT_SPEED'));
  c('stressConfigVersion', fieldInt(cs, 'CStress', 'VERSION'));
  for (final k in const ['mediumSpeed', 'fastSpeed', 'mediumStressImpact', 'highStressImpact', 'mediumCapacity', 'highCapacity']) {
    final x = e('kinetics.stats.$k');
    if (x != null) constants['kinetics${k[0].toUpperCase()}${k.substring(1)}'] = x.defaultValue;
  }
  return ConfigResult(b.entries, stress, constants, log);
}

// ------------------------------------------------------------------- tags

const _knownCategories = {
  'block', 'item', 'fluid', 'entity_type', 'damage_type', 'enchantment', 'recipe_serializer', 'game_event', 'biome',
  'worldgen', 'point_of_interest_type', 'banner_pattern', 'cat_variant', 'painting_variant', 'instrument', 'potion',
};

TagResult extractTags(String root) {
  final data = Directory('$root/src/generated/resources/data');
  final tags = <TagDef>[];
  var files = 0;
  final nsDirs = data.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final nsDir in nsDirs) {
    final ns = nsDir.path.substring(nsDir.path.lastIndexOf('/') + 1);
    final tagsDir = Directory('${nsDir.path}/tags');
    if (!tagsDir.existsSync()) continue;
    final list = tagsDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in list) {
      files++;
      final rel = f.path.substring(tagsDir.path.length + 1, f.path.length - 5);
      final parts = rel.split('/');
      var catLen = 1;
      if (!_knownCategories.contains(parts[0]) && parts.length > 2) catLen = 2;
      final category = parts.sublist(0, catLen).join('/');
      final path = parts.sublist(catLen).join('/');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final entries = <TagEntry>[];
      for (final v in (j['values'] as List? ?? const [])) {
        String id;
        var required = true;
        if (v is String) {
          id = v;
        } else {
          final m = v as Map<String, dynamic>;
          id = m['id'] as String;
          required = (m['required'] as bool?) ?? true;
        }
        final isTag = id.startsWith('#');
        entries.add(TagEntry(isTag ? id.substring(1) : id, isTag: isTag, required: required));
      }
      tags.add(TagDef(category: category, id: '$ns:$path', entries: entries, replace: (j['replace'] as bool?) ?? false));
    }
  }
  return TagResult(tags, files);
}

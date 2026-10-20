// Extracts the non-block/item registries of Create into
// lib/src/manifest/registries.g.dart and REPORT_registries.md.
//
//   dart run tool/extract_registries.dart [/path/to/Create]
//
// Only dart:io / dart:convert. Reuses tool/src/java.dart (source scanner).
import 'dart:convert';
import 'dart:io';

import 'src/java.dart';

const _defaultRoot = '/Users/eric/Documents/development/languages/java/Create';
const _pkg = 'com.simibubi.create';
const _dyes = [
  'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray', //
  'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black',
];

late String root;
late String javaRoot;
late String res;
late SourceIndex idx;
late Map<String, dynamic> lang;
final uncertain = <String>[];
final notes = <String>[];
final counts = <String, int>{};

void unsure(String what) {
  uncertain.add(what);
}

// ---------------------------------------------------------------- literals

String q(String s) {
  final b = StringBuffer("'");
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    switch (c) {
      case '\\':
        b.write('\\\\');
      case "'":
        b.write("\\'");
      case r'$':
        b.write(r'\$');
      case '\n':
        b.write('\\n');
      case '\r':
        b.write('\\r');
      case '\t':
        b.write('\\t');
      default:
        b.write(c);
    }
  }
  b.write("'");
  return b.toString();
}

/// Marker for typed object emission.
class T {
  T(this.type, this.fields);
  final String type;
  final Map<String, Object?> fields;
}

String lit(Object? v, [int ind = 0]) {
  if (v == null) return 'null';
  if (v is String) return q(v);
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return v.toString();
  if (v is T) {
    final pad = '  ' * (ind + 1);
    final parts = <String>[];
    v.fields.forEach((k, val) {
      if (val == null) return;
      if (val is List && val.isEmpty) return;
      if (val is Map && val.isEmpty) return;
      parts.add('$pad$k: ${lit(val, ind + 1)},');
    });
    return '${v.type}(\n${parts.join('\n')}\n${'  ' * ind})';
  }
  if (v is List) {
    if (v.isEmpty) return '[]';
    final simple = v.every((e) => e is String || e is num || e is bool) && v.length <= 4;
    if (simple) return '[${v.map((e) => lit(e)).join(', ')}]';
    final pad = '  ' * (ind + 1);
    return '[\n${v.map((e) => '$pad${lit(e, ind + 1)},').join('\n')}\n${'  ' * ind}]';
  }
  if (v is Map) {
    if (v.isEmpty) return '{}';
    final pad = '  ' * (ind + 1);
    return '{\n${v.entries.map((e) => '$pad${lit(e.key, ind + 1)}: ${lit(e.value, ind + 1)},').join('\n')}\n${'  ' * ind}}';
  }
  throw 'cannot emit $v';
}

// ----------------------------------------------------------------- helpers

String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

double? jnum(String s) {
  var t = s.trim();
  t = t.replaceAll('_', '');
  t = t.replaceAll(RegExp(r'[fFdDlL]$'), '');
  return double.tryParse(t);
}

String langId(String enumName) => enumName.toLowerCase();

JavaFile jf(String rel) => idx.fileAt('$javaRoot/com/simibubi/create/$rel')!;
JavaClass topClass(String rel) {
  final f = jf(rel);
  final base = rel.substring(rel.lastIndexOf('/') + 1).replaceAll('.java', '');
  return f.classes.firstWhere((c) => c.name == base);
}

JavaClass? resolve(String name, JavaFile from, {JavaClass? ctx}) {
  name = name.replaceAll(RegExp(r'<.*'), '').trim();
  if (name.isEmpty) return null;
  final first = name.split('.').first;
  final imp = from.imports[first];
  if (imp != null && !imp.startsWith(_pkg)) return null;
  return idx.resolveClass(name, from, context: ctx);
}

String fqn(String name, JavaFile from, {JavaClass? ctx}) {
  name = name.replaceAll(RegExp(r'<.*'), '').trim();
  final c = resolve(name, from, ctx: ctx);
  if (c != null) return '${c.file.package}.${c.qualifiedName}';
  final first = name.split('.').first;
  final imp = from.imports[first];
  if (imp != null) return name.contains('.') ? '$imp${name.substring(first.length)}' : imp;
  return name;
}

String relPath(JavaFile f) => f.path.substring(javaRoot.length + 1);

/// `Foo::new` / `Foo.Bar::new` -> class expression (without ::new).
String? ctorRef(String arg) {
  final m = RegExp(r'([A-Za-z_][\w.]*)::new').firstMatch(arg);
  return m?.group(1);
}

String? firstString(String s) => RegExp(r'"((?:[^"\\]|\\.)*)"').firstMatch(s)?.group(1);

String unescapeJava(String s) => s.replaceAll(r'\"', '"').replaceAll(r'\\', '\\').replaceAll(r'\n', '\n');

List<String> allStrings(String s) => RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(s).map((m) => unescapeJava(m.group(1)!)).toList();

String readRes(String rel) => File('$res/$rel').readAsStringSync();

String compactJson(String raw) => jsonEncode(jsonDecode(raw));

List<File> filesUnder(String rel, {String ext = '.json'}) {
  final d = Directory('$res/$rel');
  if (!d.existsSync()) return [];
  final l = d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith(ext)).toList();
  l.sort((a, b) => a.path.compareTo(b.path));
  return l;
}

bool langHas(String k) => lang.containsKey(k);

// ------------------------------------------------------------ block lookup

/// constant name -> block key for AllBlocks (+ AllPaletteBlocks fallback)
final Map<String, String> blockKeyByConst = {};
final Map<String, List<String>> dyedLists = {};
final Set<String> blockConstsVerified = {};
final Map<String, String> itemKeyByConst = {};

String? firstKeyLiteral(String init) {
  final m = RegExp(r'"([a-z][a-z0-9_]*)"').firstMatch(init);
  return m?.group(1);
}

void buildBlockMaps() {
  final ab = topClass('AllBlocks.java');
  for (final f in ab.fields) {
    if (!f.type.startsWith('BlockEntry') && !f.type.startsWith('DyedBlockList')) continue;
    if (f.type.startsWith('DyedBlockList')) {
      final sm = RegExp(r'colourName\s*\+\s*"(_\w+)"').firstMatch(f.init);
      final out = <String>[];
      final special = RegExp(r'colour\s*==\s*DyeColor\.(\w+)\)\s*return\s+(\w+)\s*;').firstMatch(f.init);
      for (final d in _dyes) {
        if (special != null && d == special.group(1)!.toLowerCase()) {
          out.add('@${special.group(2)}'); // resolved later
        } else if (sm != null) {
          out.add('$d${sm.group(1)}');
        }
      }
      dyedLists[f.name] = out;
      continue;
    }
    final m = RegExp(r'\.\s*block\(\s*"([^"]+)"').firstMatch(f.init);
    if (m != null) {
      blockKeyByConst[f.name] = m.group(1)!;
      blockConstsVerified.add(f.name);
    }
  }
  for (final e in dyedLists.entries) {
    e.value.replaceRange(0, e.value.length, [
      for (final k in e.value) k.startsWith('@') ? (blockKeyByConst[k.substring(1)] ?? k) : k
    ]);
  }
  // palette blocks: first string literal heuristics
  try {
    final pb = topClass('content/decoration/palettes/AllPaletteBlocks.java');
    for (final f in pb.fields) {
      if (!f.type.startsWith('BlockEntry')) continue;
      final k = firstKeyLiteral(f.init);
      if (k != null) blockKeyByConst.putIfAbsent('palette:${f.name}', () => k);
    }
  } catch (_) {}
  final ai = topClass('AllItems.java');
  for (final f in ai.fields) {
    if (!f.type.startsWith('ItemEntry')) continue;
    final cm = RegExp(r'compatCrushedOre\((\w+)\)').firstMatch(f.init);
    final k = cm != null ? 'crushed_raw_${cm.group(1)!.toLowerCase()}' : firstKeyLiteral(f.init);
    if (k != null) itemKeyByConst[f.name] = k;
  }
}

// -------------------------------------------------------- BLOCK ENTITIES

List<T> extractBlockEntityTypes() {
  final f = jf('AllBlockEntityTypes.java');
  final cls = topClass('AllBlockEntityTypes.java');
  final out = <T>[];
  for (final fld in cls.fields) {
    if (!fld.type.startsWith('BlockEntityEntry')) continue;
    final ch = parseChain(fld.init);
    final be = ch.calls.firstWhere((c) => c.key == 'blockEntity', orElse: () => const MapEntry('', ''));
    if (be.key.isEmpty) {
      unsure('BlockEntityType ${fld.name}: no blockEntity() call');
      continue;
    }
    final args = splitArgs(be.value);
    final key = firstString(args[0])!;
    final ref = ctorRef(args[1]) ?? args[1];
    final valid = <String>[];
    final srcParts = <String>[];
    var ok = true;
    for (final c in ch.calls) {
      if (c.key != 'validBlocks' && c.key != 'validBlock' && c.key != 'validBlocksDeferred') continue;
      srcParts.add('${c.key}(${norm(c.value)})');
      if (c.key == 'validBlocksDeferred') {
        if (norm(c.value) == 'TrackMaterial::allBlocks') {
          valid.add('track'); // TrackMaterial.ALL only contains ANDESITE (-> AllBlocks.TRACK) in Create itself
          notes.add('BlockEntityType track: validBlocksDeferred(TrackMaterial::allBlocks) resolved to [track] '
              '(only TrackMaterial.ANDESITE exists in Create; addons append materials at runtime).');
        } else {
          ok = false;
        }
        continue;
      }
      for (final a in splitArgs(c.value)) {
        final m = RegExp(r'^AllBlocks\.(\w+)(\.toArray\(\))?$').firstMatch(a);
        if (m == null) {
          ok = false;
          unsure('BlockEntityType $key: unresolved block argument `$a`');
          continue;
        }
        if (m.group(2) != null) {
          final l = dyedLists[m.group(1)];
          if (l == null) {
            ok = false;
            unsure('BlockEntityType $key: unknown dyed list ${m.group(1)}');
          } else {
            valid.addAll(l);
          }
        } else {
          final k = blockKeyByConst[m.group(1)];
          if (k == null) {
            ok = false;
            unsure('BlockEntityType $key: unresolved AllBlocks.${m.group(1)}');
          } else {
            valid.add(k);
          }
        }
      }
    }
    // cross check against lang
    for (final b in valid) {
      if (!langHas('block.create.$b')) {
        ok = false;
        unsure('BlockEntityType $key: block `$b` has no block.create lang entry');
      }
    }
    String? ds, dt;
    final dsm = ch.first('displaySource');
    if (dsm != null) ds = norm(dsm);
    final dtm = ch.first('displayTarget');
    if (dtm != null) dt = norm(dtm);
    out.add(T('BlockEntityTypeDef', {
      'key': key,
      'javaClass': fqn(ref, f, ctx: cls),
      'validBlocks': valid.toSet().toList(),
      'validBlocksSource': srcParts.join(' '),
      'displaySource': ds == null ? null : _displayKey(ds),
      'displayTarget': dt == null ? null : _displayKey(dt),
      'hasVisual': ch.has('visual'),
      'hasRenderer': ch.has('renderer'),
      'verified': ok,
    }));
  }
  return out;
}

final Map<String, String> _displayConstKey = {};

String _displayKey(String expr) {
  // AllDisplaySources.NIXIE_TUBE -> nixie_tube
  final m = RegExp(r'^All(DisplaySources|DisplayTargets)\.(\w+)$').firstMatch(expr);
  if (m == null) return expr;
  return _displayConstKey['${m.group(1)}.${m.group(2)}'] ?? expr;
}

// ----------------------------------------------------------- ENTITY TYPES

/// Superclass name with generic parameters stripped from the header first
/// (JavaClass.superName trips over `class X<T extends Y> extends Z`).
String? superOf(JavaClass c) {
  if (c.kind == 'interface') return null;
  var h = c.header;
  var prev = '';
  while (prev != h) {
    prev = h;
    h = h.replaceAll(RegExp(r'<[^<>]*>'), '');
  }
  return RegExp(r'\bextends\s+([\w.]+)').firstMatch(h)?.group(1);
}

bool _implementsDeep(JavaClass? c, String iface) {
  var cur = c;
  var guard = 0;
  while (cur != null && guard++ < 20) {
    if (cur.interfaces.any((i) => i == iface || i.endsWith('.$iface'))) return true;
    final s = superOf(cur);
    if (s == null) return false;
    cur = resolve(s, cur.file, ctx: cur);
  }
  return false;
}

List<T> extractEntityTypes() {
  final f = jf('AllEntityTypes.java');
  final cls = topClass('AllEntityTypes.java');
  final out = <T>[];
  for (final fld in cls.fields) {
    if (!fld.type.startsWith('EntityEntry')) continue;
    final ch = parseChain(fld.init);
    final first = ch.calls.first;
    final a = splitArgs(first.value);
    late String key;
    late String factory;
    late String category;
    late int range, freq;
    late bool vel, fire;
    late String buildRef;
    var tp = false;
    if (first.key == 'contraption') {
      key = firstString(a[0])!;
      factory = ctorRef(a[1])!;
      category = 'MISC';
      range = int.parse(a[3]);
      freq = int.parse(a[4]);
      vel = a[5] == 'true';
      fire = true;
      buildRef = 'AbstractContraptionEntity::build';
      tp = true;
    } else if (first.key == 'register') {
      key = firstString(a[0])!;
      factory = ctorRef(a[1])!;
      category = a[3].replaceAll('MobCategory.', '');
      range = a[4] == 'Integer.MAX_VALUE' ? 2147483647 : int.parse(a[4]);
      freq = a[5] == 'Integer.MAX_VALUE' ? 2147483647 : int.parse(a[5]);
      vel = a[6] == 'true';
      fire = a[7] == 'true';
      buildRef = a[8];
    } else {
      unsure('EntityType ${fld.name}: unknown factory ${first.key}');
      continue;
    }
    // tracking range/update interval order: register(name,factory,renderer,group,range,updateFrequency,...)
    final cc = resolve(factory, f, ctx: cls);
    var w = 0.6, h = 1.8;
    var defaulted = true;
    var ok = true;
    final bm = RegExp(r'^(\w[\w.]*)::build$').firstMatch(buildRef.trim());
    if (bm != null) {
      final bc = resolve(bm.group(1)!, f, ctx: cls);
      final bmeth = bc?.methodsNamed('build').firstOrNull;
      if (bmeth != null) {
        final sm = RegExp(r'\.sized\(\s*([^,]+?)\s*,\s*([^)]+?)\s*\)').firstMatch(bmeth.body);
        if (sm != null) {
          w = jnum(sm.group(1)!)!;
          h = jnum(sm.group(2)!)!;
          defaulted = false;
        }
      } else {
        ok = false;
        unsure('EntityType $key: build method not found');
      }
    } else {
      ok = false;
    }
    if (defaulted) {
      notes.add('EntityType $key: width/height are the vanilla EntityType.Builder defaults (0.6 x 1.8) because the build hook never calls sized(); eyeHeight derived as height*0.85.');
    }
    final eye = double.parse((h * 0.85).toStringAsPrecision(7));
    final superName = cc == null ? null : superOf(cc);
    out.add(T('EntityTypeDef', {
      'key': key,
      'javaClass': fqn(factory, f, ctx: cls),
      'superClass': superName == null ? '' : fqn(superName, cc!.file, ctx: cc),
      'category': category,
      'width': w,
      'height': h,
      'eyeHeight': eye,
      'trackingRange': range,
      'updateInterval': freq,
      'sendVelocity': vel,
      'fireImmune': fire,
      'summonable': true,
      'complexSpawnData': _implementsDeep(cc, 'IEntityWithComplexSpawn'),
      'dimensionsDefaulted': defaulted,
      'teleportingNotSupportedTag': tp,
      'verified': ok,
    }));
  }
  return out;
}

// ------------------------------------------------------------- MENU TYPES

List<T> extractMenuTypes() {
  final f = jf('AllMenuTypes.java');
  final cls = topClass('AllMenuTypes.java');
  final out = <T>[];
  for (final fld in cls.fields) {
    if (!fld.type.startsWith('MenuEntry')) continue;
    final ch = parseChain(fld.init);
    final c = ch.calls.first;
    final a = splitArgs(c.value);
    out.add(T('MenuTypeDef', {
      'key': firstString(a[0])!,
      'menuClass': fqn(ctorRef(a[1])!, f, ctx: cls),
      'screenClass': ctorRef(a[2]) == null ? '' : fqn(ctorRef(a[2])!, f, ctx: cls),
      'factory': 'ForgeMenuFactory',
    }));
  }
  return out;
}

// -------------------------------------------------------- DATA COMPONENTS

String recordComponents(JavaClass c) {
  if (c.kind == 'enum') {
    return 'enum ${c.name}{${c.enumConstants.map((e) => e.name).join(', ')}}';
  }
  final m = RegExp(r'record\s+\w+\s*(?:<[^>]*>)?\s*\(').firstMatch(c.header);
  if (m == null) {
    // class: list non-static instance fields
    final fl = c.fields.where((f) => !f.isStatic).map((f) => '${f.type} ${f.name}').toList();
    return fl.isEmpty ? '' : 'class fields: ${fl.join(', ')}';
  }
  final op = m.end - 1;
  final cl = matchClose(c.header, op);
  return 'record(${norm(c.header.substring(op + 1, cl))})';
}

List<T> extractDataComponents() {
  final f = jf('AllDataComponents.java');
  final cls = topClass('AllDataComponents.java');
  final out = <T>[];
  for (final fld in cls.fields) {
    if (!fld.type.startsWith('DataComponentType')) continue;
    if (!fld.init.trimLeft().startsWith('register(')) continue;
    final ch = parseChain(fld.init);
    final a = splitArgs(ch.calls.first.value);
    final key = firstString(a[0])!;
    final lam = a[1];
    final arrow = lam.indexOf('->');
    final body = lam.substring(arrow + 2);
    final bc = parseChain(body);
    final pers = bc.first('persistent');
    final net = bc.first('networkSynchronized');
    final gen = RegExp(r'DataComponentType<(.*)>$').firstMatch(fld.type)?.group(1) ?? fld.type;
    // deprecated?
    final kidx = f.text.indexOf('"$key"');
    final prevSemi = f.text.lastIndexOf(';', kidx);
    final deprecated = f.text.substring(prevSemi < 0 ? 0 : prevSemi, kidx).contains('@Deprecated');
    String codecClass = '', codecField = '', codecFile = '', desc = '', shape = '';
    var ok = true;
    if (pers != null) {
      final p = norm(pers);
      final m = RegExp(r'^([A-Z]\w*(?:\.[A-Z]\w*)*)\.([A-Z_]+)(\..*)?$').firstMatch(p);
      if (m != null) {
        final cc = resolve(m.group(1)!, f, ctx: cls);
        if (cc != null) {
          final cf = cc.field(m.group(2)!);
          if (cf != null) {
            codecClass = '${cc.file.package}.${cc.qualifiedName}';
            codecField = m.group(2)!;
            codecFile = relPath(cc.file);
            desc = norm(cf.init);
            if (m.group(3) != null) desc = '${m.group(3)!.substring(1)} applied to: $desc';
            shape = recordComponents(cc);
            if (desc.isEmpty) {
              ok = false;
              unsure('DataComponent $key: codec ${cc.name}.${m.group(2)} has no initializer');
            }
          } else {
            ok = false;
            unsure('DataComponent $key: codec field ${m.group(1)}.${m.group(2)} not found in ${cc.name}');
          }
        } else {
          desc = 'library codec ${m.group(1)}.${m.group(2)}${m.group(3) ?? ''}';
        }
      } else {
        desc = 'expression: $p';
        ok = false;
        unsure('DataComponent $key: codec expression not understood: $p');
      }
    }
    out.add(T('DataComponentDef', {
      'key': key,
      'javaType': gen,
      'persistent': pers != null,
      'networkSynced': net != null,
      'persistentCodec': pers == null ? '' : norm(pers),
      'networkCodec': net == null ? '' : norm(net),
      'codecJavaClass': codecClass,
      'codecField': codecField,
      'codecSourceFile': codecFile,
      'codecDescription': desc,
      'valueShape': shape,
      'deprecated': deprecated,
      'verified': ok,
    }));
  }
  return out;
}

// ------------------------------------------------------------------ FLUIDS

List<T> extractFluids() {
  final f = jf('AllFluids.java');
  final cls = topClass('AllFluids.java');
  final out = <T>[];
  for (final fld in cls.fields) {
    if (!fld.type.startsWith('FluidEntry')) continue;
    final ch = parseChain(fld.init);
    final c0 = ch.calls.first;
    final a = splitArgs(c0.value);
    final key = firstString(a[0])!;
    final virtual = c0.key == 'virtualFluid';
    final attrs = <String, String>{};
    final explicit = <String>[];
    void grab(String name, String re) {
      for (final c in ch.calls) {
        if (c.key == 'properties' || c.key == 'fluidProperties') {
          final m = RegExp(re).firstMatch(c.value);
          if (m != null) {
            attrs[name] = m.group(1)!.trim();
            explicit.add(name);
            return;
          }
        }
      }
    }

    String? lang0;
    final tags = <String>[];
    final bucketTags = <String>[];
    var afterBucket = false;
    for (final c in ch.calls) {
      if (c.key == 'bucket') afterBucket = true;
      if (c.key == 'lang') lang0 ??= firstString(c.value);
      if (c.key == 'tag') (afterBucket ? bucketTags : tags).add(norm(c.value));
    }
    var fluidClass = '', flowingClass = '', typeClass = '';
    if (virtual) {
      if (a.length >= 4) {
        typeClass = fqn(ctorRef(a[1])!, f, ctx: cls);
        final sc = a[2].split('::').first;
        final fc = a[3].split('::').first;
        fluidClass = fqn(sc, f, ctx: cls);
        flowingClass = fqn(fc, f, ctx: cls);
      } else {
        typeClass = 'net.neoforged.neoforge.fluids.FluidType';
        fluidClass = fqn('VirtualFluid', f, ctx: cls);
        flowingClass = fluidClass;
      }
    } else {
      fluidClass = 'net.neoforged.neoforge.fluids.BaseFlowingFluid.Source';
      flowingClass = 'net.neoforged.neoforge.fluids.BaseFlowingFluid.Flowing';
      typeClass = '$_pkg.AllFluids.SolidRenderedPlaceableFluidType';
      attrs['density'] = '1000';
      attrs['viscosity'] = '1000';
      attrs['levelDecreasePerBlock'] = '1';
      attrs['tickRate'] = '5';
      attrs['slopeFindDistance'] = '4';
      attrs['explosionResistance'] = '1.0';
      final defaults = Map.of(attrs);
      for (final nm in ['viscosity', 'density']) {
        grab(nm, '$nm\\(([^)]*)\\)');
      }
      for (final nm in ['levelDecreasePerBlock', 'tickRate', 'slopeFindDistance', 'explosionResistance']) {
        grab(nm, '$nm\\(([^)]*)\\)');
      }
      attrs['defaultsForUnlisted'] = defaults.entries.map((e) => '${e.key}=${e.value}').join(';');
      final fi = fld.init.indexOf('SolidRenderedPlaceableFluidType.create(');
      if (fi >= 0) {
        final op = fld.init.indexOf('(', fi);
        final cl = matchClose(fld.init, op);
        final fa = splitArgs(fld.init.substring(op + 1, cl));
        attrs['fogColor'] = fa[0];
        attrs['fogDistanceModifier'] = norm(fa[1]);
      }
      final mc = RegExp(r'mapColor\(MapColor\.(\w+)\)').firstMatch(fld.init);
      if (mc != null) attrs['mapColor'] = 'MapColor.${mc.group(1)}';
      attrs['explicit'] = explicit.join(',');
    }
    if (tags.isNotEmpty) attrs['fluidTags'] = tags.join(' | ');
    if (bucketTags.isNotEmpty) attrs['bucketItemTags'] = bucketTags.join(' | ');
    final hasBucket = ch.has('bucket');
    final hasBlock = ch.has('block');
    final lk = 'fluid.create.$key';
    var ok = true;
    if (!langHas(lk)) {
      ok = false;
      unsure('Fluid $key: no $lk lang entry');
    } else if (lang0 != null && lang[lk] != lang0) {
      ok = false;
      unsure('Fluid $key: lang mismatch');
    }
    if (virtual) {
      attrs['potionSpecial'] = key == 'potion' ? 'PotionFluid carries potion contents via data components' : '';
      if (attrs['potionSpecial']!.isEmpty) attrs.remove('potionSpecial');
    }
    out.add(T('FluidDef', {
      'key': key,
      'kind': virtual ? 'virtual' : 'standard',
      'sourceKey': key,
      'flowingKey': 'flowing_$key',
      'bucketKey': hasBucket ? '${key}_bucket' : null,
      'blockKey': hasBlock ? key : null,
      'fluidTypeKey': key,
      'lang': lang0 ?? '',
      'sourceClass': fluidClass,
      'flowingClass': flowingClass,
      'fluidTypeClass': typeClass,
      'attributes': attrs,
      'verified': ok,
    }));
  }
  return out;
}

// ------------------------------------------------------------ RECIPE TYPES

int? _retInt(JavaClass? c, String m) {
  var cur = c;
  var guard = 0;
  while (cur != null && guard++ < 20) {
    final me = cur.methodsNamed(m).firstOrNull;
    if (me != null) {
      final r = RegExp(r'return\s+(\d+|true|false)\s*;').firstMatch(me.body);
      if (r != null) return r.group(1) == 'true' ? 1 : r.group(1) == 'false' ? 0 : int.parse(r.group(1)!);
      return null;
    }
    final s = superOf(cur);
    if (s == null) return null;
    cur = resolve(s, cur.file, ctx: cur);
  }
  return null;
}

bool _isProcessing(JavaClass? c) {
  var cur = c;
  var guard = 0;
  while (cur != null && guard++ < 20) {
    if (cur.name == 'ProcessingRecipe') return true;
    final s = superOf(cur);
    if (s == null) return false;
    if (s.startsWith('ProcessingRecipe') || s.startsWith('StandardProcessingRecipe')) return true;
    cur = resolve(s, cur.file, ctx: cur);
  }
  return false;
}

List<T> extractRecipeTypes() {
  final f = jf('AllRecipeTypes.java');
  final cls = topClass('AllRecipeTypes.java');
  // recipe json counts
  final counts = <String, int>{};
  for (final file in filesUnder('data/create/recipe')) {
    final t = (jsonDecode(file.readAsStringSync()) as Map)['type'] as String;
    counts[t] = (counts[t] ?? 0) + 1;
  }
  final out = <T>[];
  for (final ec in cls.enumConstants) {
    final key = langId(ec.name);
    final a = splitArgs(ec.args);
    final a0 = a[0];
    var rc = ctorRef(a0);
    var summarySer = '';
    var registersType = true;
    var vanilla = '';
    var ok = true;
    var processing = false;
    JavaClass? rcls;
    if (a.length == 3) {
      registersType = false;
      vanilla = 'minecraft:crafting';
      summarySer = 'SimpleCustomRecipeSerializer (special crafting recipe, no extra data) wrapping ${rc ?? a0}; '
          'recipe type is minecraft:crafting (no create:$key recipe type registered)';
    }
    if (a0.contains('MechanicalCraftingRecipe.Serializer')) {
      rc = 'MechanicalCraftingRecipe';
      summarySer = 'RecipeSerializer(MechanicalCraftingRecipe.Serializer.CODEC, STREAM_CODEC): a vanilla shaped recipe '
          'codec plus boolean `accept_mirrored`';
    } else if (a0.contains('SequencedAssemblyRecipeSerializer')) {
      rc = 'SequencedAssemblyRecipe';
      summarySer = 'SequencedAssemblyRecipeSerializer: fields ingredient (Ingredient), transitional_item (ProcessingOutput), '
          'sequence (list of SequencedRecipe), results (list of ProcessingOutput), loops (int >= 0, default 1)';
    }
    if (rc != null) {
      rcls = resolve(rc, f, ctx: cls);
      processing = _isProcessing(rcls);
    }
    if (processing) {
      final isItemApp = rcls != null && (() {
        var cur = rcls;
        var g = 0;
        while (cur != null && g++ < 10) {
          if (cur.name == 'ItemApplicationRecipe') return true;
          cur = superOf(cur) == null ? null : resolve(superOf(cur)!, cur.file, ctx: cur);
        }
        return false;
      })();
      summarySer = 'ProcessingRecipe.Serializer over ${isItemApp ? 'ItemApplicationRecipeParams' : 'ProcessingRecipeParams'}: '
          'json fields `ingredients` (items and/or sized fluid ingredients, mixed list), `results` (item ProcessingOutput and/or fluid stacks, mixed list), '
          '`processing_time` (int, default 0)'
          ', `heat_requirement` (none/heated/superheated, default none)'
          '${isItemApp ? ', `keep_held_item` (bool, default false)' : ''}';
    }
    final mi = _retInt(rcls, 'getMaxInputCount');
    final mo = _retInt(rcls, 'getMaxOutputCount');
    var mfi = _retInt(rcls, 'getMaxFluidInputCount');
    var mfo = _retInt(rcls, 'getMaxFluidOutputCount');
    final hasFluidOverride = mfi != null || mfo != null;
    if (processing) {
      mfi ??= 0; // ProcessingRecipe default
      mfo ??= 0;
    }
    var crh = _retInt(rcls, 'canRequireHeat');
    var csd = _retInt(rcls, 'canSpecifyDuration');
    if (processing) {
      if (crh == null || csd == null) {
        ok = false;
        unsure('RecipeType $key: canRequireHeat/canSpecifyDuration not resolvable');
      }
    }
    String ins = '', outs = '';
    if (processing) {
      ins = 'up to ${mi ?? '?'} item ingredient(s)${(mfi ?? 0) > 0 ? ' and up to $mfi fluid ingredient(s)' : ''}';
      outs = 'up to ${mo ?? '?'} item result(s)${(mfo ?? 0) > 0 ? ' and up to $mfo fluid result(s)' : ''}';
      if (mi == null || mo == null) {
        ok = false;
        unsure('RecipeType $key: getMaxInput/OutputCount not resolvable');
      }
    } else if (key == 'mechanical_crafting') {
      ins = 'shaped pattern up to 9x9 (ShapedRecipePattern.setCraftingSize(9, 9)) of ingredients';
      outs = '1 result item stack';
    } else if (key == 'sequenced_assembly') {
      ins = 'one ingredient item';
      outs = 'weighted pool of ProcessingOutput results; intermediate transitional_item';
    } else if (key == 'toolbox_dyeing') {
      ins = 'exactly one toolbox block item and exactly one dye (crafting grid, shapeless)';
      outs = 'the toolbox of the dye colour (AllBlocks.TOOLBOXES.get(color)), components copied';
    } else if (key == 'item_copying') {
      ins = 'one SupportsItemCopying item holding data + n identical blank items';
      outs = 'n+1 copies of the item (createCopy, enchantments stripped)';
    }
        if (hasFluidOverride && !processing) unsure('RecipeType $key: fluid counts found on non-processing recipe');
    out.add(T('RecipeTypeDef', {
      'key': key,
      'enumName': ec.name,
      'recipeClass': rcls == null ? (rc ?? a0) : '${rcls.file.package}.${rcls.qualifiedName}',
      'serializerSummary': summarySer.isEmpty ? 'RecipeSerializer ${norm(a0)}' : summarySer,
      'registersRecipeType': registersType,
      'vanillaRecipeType': vanilla,
      'processing': processing,
      'maxItemInputs': processing ? mi : null,
      'maxItemOutputs': processing ? mo : null,
      'maxFluidInputs': processing ? mfi : null,
      'maxFluidOutputs': processing ? mfo : null,
      'canRequireHeat': processing && crh != null ? crh == 1 : null,
      'canSpecifyDuration': processing && csd != null ? csd == 1 : null,
      'inputSummary': ins,
      'outputSummary': outs,
      'generatedRecipeCount': counts['create:$key'] ?? 0,
      'verified': ok && rcls != null,
    }));
  }
  final known = {for (final e in out) 'create:${(e.fields['key'])}'};
  final extra = counts.keys.where((k) => k.startsWith('create:') && !known.contains(k)).toList();
  if (extra.isNotEmpty) unsure('Recipe json types without enum entry: $extra');
  notes.add('Recipe json type counts in generated data: ${(counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key}=${e.value}').join(', ')}');
  return out;
}

// ----------------------------------------------------- DAMAGE / ENCHANTMENT

List<T> extractDamageTypes() {
  final cls = topClass('AllDamageTypes.java');
  final consts = <String, String>{}; // key -> constant
  for (final m in RegExp(r'(\w+)\s*=\s*key\("([^"]+)"\)').allMatches(cls.body)) {
    consts[m.group(2)!] = m.group(1)!;
  }
  final out = <T>[];
  for (final key in consts.keys) {
    final p = 'data/create/damage_type/$key.json';
    if (!File('$res/$p').existsSync()) {
      unsure('DamageType $key: json missing');
      continue;
    }
    final raw = readRes(p);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    out.add(T('DamageTypeDef', {
      'key': key,
      'messageId': j['message_id'],
      'exhaustion': (j['exhaustion'] as num).toDouble(),
      'scaling': j['scaling'],
      'effects': j['effects'],
      'deathMessageType': j['death_message_type'],
      'rawJson': raw,
      'javaConstant': consts[key],
      'verified': langHas('death.attack.create.$key') || langHas('death.attack.${j['message_id']}'),
    }));
  }
  final files = filesUnder('data/create/damage_type').length;
  if (files != out.length) unsure('DamageType json count $files != java count ${out.length}');
  return out;
}

List<T> extractEnchantments() {
  final cls = topClass('AllEnchantments.java');
  final consts = <String, String>{};
  for (final m in RegExp(r'(\w+)\s*=\s*key\("([^"]+)"\)').allMatches(cls.body)) {
    consts[m.group(2)!] = m.group(1)!;
  }
  final out = <T>[];
  for (final key in consts.keys) {
    final raw = readRes('data/create/enchantment/$key.json');
    out.add(T('EnchantmentDef', {
      'key': key,
      'rawJson': raw,
      'javaConstant': consts[key],
      'verified': langHas('enchantment.create.$key'),
    }));
  }
  final j = jsonDecode(readRes('data/create/enchantment/potato_recovery.json')) as Map;
  final items = (j['effects'] as Map).values.first;
  if (jsonEncode(items).contains('"items":[]')) {
    unsure('Enchantment potato_recovery: generated json has an empty `items` predicate in the ammo_use '
        'match_tool requirement (Java passes ItemPredicate.Builder.item().of(getter, POTATO_CANNON)); copied verbatim');
    out.firstWhere((t) => t.fields['key'] == 'potato_recovery').fields['verified'] = false;
  }
  return out;
}

// ------------------------------------------------------------ SOUND EVENTS

List<T> extractSounds() {
  final cls = topClass('AllSoundEvents.java');
  final text = cls.body;
  final soundsJson = jsonDecode(readRes('assets/create/sounds.json')) as Map<String, dynamic>;
  final starts = RegExp(r'(\w+)\s*=\s*create\("([^"]+)"\)').allMatches(text).toList();
  final end = text.indexOf('private static SoundEntryBuilder create');
  final out = <T>[];
  final seenEvents = <String>{};
  for (var i = 0; i < starts.length; i++) {
    final s = starts[i];
    final chunkEnd = i + 1 < starts.length ? starts[i + 1].start : end;
    final chunk = text.substring(s.end, chunkEnd);
    final key = s.group(2)!;
    String? subtitle;
    final sm = RegExp(r'\.subtitle\("((?:[^"\\]|\\.)*)"\)').firstMatch(chunk);
    if (sm != null) subtitle = unescapeJava(sm.group(1)!);
    final cat = RegExp(r'SoundSource\.(\w+)').firstMatch(chunk)?.group(1) ?? 'BLOCKS';
    final att = int.tryParse(RegExp(r'attenuationDistance\((\d+)\)').firstMatch(chunk)?.group(1) ?? '') ?? 0;
    final variants = [for (final m in RegExp(r'addVariant\("([^"]+)"\)').allMatches(chunk)) m.group(1)!];
    final wrapped = <T>[];
    var pos = 0;
    while (true) {
      final pi = chunk.indexOf('.playExisting(', pos);
      if (pi < 0) break;
      final op = pi + '.playExisting'.length;
      final cl = matchClose(chunk, op);
      final args = splitArgs(chunk.substring(op + 1, cl));
      var ev = norm(args[0]).replaceAll(RegExp(r'\.value\(\)$'), '').replaceAll(RegExp(r'::value$'), '');
      wrapped.add(T('WrappedSoundDef', {
        'javaEvent': ev,
        'volume': args.length > 1 ? jnum(args[1])! : 1.0,
        'pitch': args.length > 2 ? jnum(args[2])! : 1.0,
      }));
      pos = cl;
    }
    final registered = <String>[];
    if (wrapped.isEmpty) {
      registered.add(key);
    } else {
      for (var w = 0; w < wrapped.length; w++) {
        registered.add(w == 0 ? key : '${key}_compounded_$w');
      }
    }
    final sj = <String, String>{};
    var ok = true;
    for (final r in registered) {
      seenEvents.add(r);
      if (soundsJson.containsKey(r)) {
        sj[r] = jsonEncode(soundsJson[r]);
      } else {
        ok = false;
        unsure('SoundEvent $r: missing from sounds.json');
      }
    }
    if ((subtitle != null) != langHas('create.subtitle.$key')) {
      ok = false;
      unsure('SoundEvent $key: subtitle presence differs from lang (create.subtitle.$key)');
    }
    out.add(T('SoundEventDef', {
      'key': key,
      'javaConstant': s.group(1),
      'kind': wrapped.isEmpty ? 'custom' : 'wrapped',
      'registeredEvents': registered,
      'subtitle': subtitle,
      'category': cat,
      'attenuationDistance': att,
      'wrapped': wrapped,
      'variants': variants,
      'soundsJson': sj,
      'verified': ok,
    }));
  }
  final extra = soundsJson.keys.where((k) => !seenEvents.contains(k)).toList();
  if (extra.isNotEmpty) unsure('sounds.json keys without Java entry: $extra');
  return out;
}

// --------------------------------------------------------------- PARTICLES

List<T> extractParticles() {
  final f = jf('AllParticleTypes.java');
  final cls = topClass('AllParticleTypes.java');
  return [
    for (final ec in cls.enumConstants)
      T('ParticleTypeDef', {
        'key': langId(ec.name),
        'enumName': ec.name,
        'dataClass': fqn(ctorRef(ec.args)!, f, ctx: cls),
      })
  ];
}

// ----------------------------------------- ENTITY DATA SERIALIZER / DECOR

List<T> extractEntityDataSerializers() {
  final f = jf('AllEntityDataSerializers.java');
  final cls = topClass('AllEntityDataSerializers.java');
  final out = <T>[];
  for (final m in RegExp(r'REGISTER\.register\("([^"]+)",\s*\(\)\s*->\s*(\w+)\)').allMatches(cls.body)) {
    final field = cls.field(m.group(2)!);
    out.add(T('EntityDataSerializerDef', {
      'key': m.group(1),
      'javaClass': fqn(field?.type ?? m.group(2)!, f, ctx: cls),
    }));
  }
  return out;
}

List<T> extractMapDecorations() {
  final cls = topClass('AllMapDecorationTypes.java');
  final out = <T>[];
  for (final m in RegExp(r'DECORATION_TYPES\.register\("([^"]+)",\s*\(\)\s*->\s*new MapDecorationType\(([^;]*)\)\);').allMatches(cls.body)) {
    final a = splitArgs(m.group(2)!);
    final asset = RegExp(r'asResource\("([^"]+)"\)').firstMatch(a[0])?.group(1);
    // 26.3 dropped `mapColor` and `explorationMapElement` from `MapDecorationType`: the
    // constructor is now `(assetId, showOnItemFrame, trackCount)`. The fields stay in the
    // manifest type so the generator keeps one shape across versions.
    final threeArg = a.length == 3;
    out.add(T('MapDecorationDef', {
      'key': m.group(1),
      'assetId': 'create:$asset',
      'showOnItemFrame': a[1] == 'true',
      'mapColor': threeArg ? 0 : int.parse(a[2]),
      'trackCount': a[threeArg ? 2 : 3] == 'true',
      'explorationMapElement': threeArg ? false : a[4] == 'true',
    }));
  }
  return out;
}

// ------------------------------------------------------------ ADVANCEMENTS

class AdvOut {
  List<T> advancements = [];
  List<T> triggers = [];
}

AdvOut extractAdvancements() {
  final out = AdvOut();
  final cls = topClass('foundation/advancement/AllAdvancements.java');
  final text = cls.body;
  final starts = RegExp(r'(\w+)\s*=\s*create\("([^"]+)"').allMatches(text).toList();
  final javaIds = <String, String>{}; // id -> const
  final javaType = <String, String>{};
  for (var i = 0; i < starts.length; i++) {
    final s = starts[i];
    final e = i + 1 < starts.length ? starts[i + 1].start : text.length;
    final chunk = text.substring(s.end, e);
    javaIds[s.group(2)!] = s.group(1)!;
    javaType[s.group(2)!] = RegExp(r'\.special\((\w+)\)').firstMatch(chunk)?.group(1) ?? 'NORMAL';
  }
  final dir = '$res/data/create/advancement';
  final createFiles = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((x) => x.path.endsWith('.json'))
      .map((x) => x.path.substring(dir.length + 1, x.path.length - 5))
      .toSet();
  final triggerIds = <String>{};
  final order = javaIds.keys.toList();
  for (final id in order) {
    if (!createFiles.contains(id)) {
      unsure('Advancement $id: Java entry has no generated json');
      continue;
    }
    final raw = File('$dir/$id.json').readAsStringSync();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final trig = <String>[];
    (j['criteria'] as Map).forEach((k, v) {
      final t = (v as Map)['trigger'] as String;
      trig.add(t);
      if (t.startsWith('create:')) triggerIds.add(t);
    });
    final title = lang['advancement.create.$id'] as String?;
    final desc = lang['advancement.create.$id.desc'] as String?;
    var ok = title != null && desc != null;
    if (!ok) unsure('Advancement $id: lang title/description missing');
    out.advancements.add(T('AdvancementDef', {
      'id': id,
      'kind': 'create',
      'parent': j['parent'],
      'trigger': trig,
      'title': title,
      'description': desc,
      'taskType': javaType[id],
      'rawJson': raw,
      'javaConstant': javaIds[id],
      'verified': ok,
    }));
  }
  for (final id in createFiles.toList()..sort()) {
    if (!javaIds.containsKey(id)) unsure('Advancement json $id has no Java entry');
  }
  // recipe unlock advancements
  for (final file in filesUnder('data/create/advancement/recipes')) {
    final id = file.path.substring(dir.length + 1, file.path.length - 5);
    final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final trig = <String>{};
    (j['criteria'] as Map).forEach((k, v) => trig.add((v as Map)['trigger'] as String));
    out.advancements.add(T('AdvancementDef', {
      'id': id,
      'kind': 'recipe',
      'parent': j['parent'],
      'trigger': trig.toList(),
      'rewardRecipes': ((j['rewards'] as Map?)?['recipes'] as List?)?.cast<String>() ?? <String>[],
    }));
  }
  for (final t in triggerIds.toList()..sort()) {
    out.triggers.add(T('TriggerDef', {
      'id': t,
      'javaClass': 'com.simibubi.create.foundation.advancement.SimpleCreateTrigger',
    }));
  }
  // lang cross check
  final langAdv = lang.keys.where((k) => k.startsWith('advancement.create.') && !k.endsWith('.desc')).length;
  if (langAdv != javaIds.length) unsure('advancement lang count $langAdv != java count ${javaIds.length}');
  return out;
}

// -------------------------------------------------------- CUSTOM REGISTRIES

T entry(String key, String cls, [String notes = '', bool ok = true]) =>
    T('CustomRegistryEntryDef', {'key': key, 'javaClass': cls, 'notes': notes, 'verified': ok});

List<T> extractCustomRegistries() {
  final regs = <T>[];
  final cr = topClass('api/registry/CreateRegistries.java');
  final bi = topClass('api/registry/CreateBuiltInRegistries.java');
  final keyOf = <String, String>{}; // CONST -> key
  for (final fld in cr.fields) {
    keyOf[fld.name] = firstString(fld.init)!;
  }
  final valueType = <String, String>{};
  for (final fld in cr.fields) {
    final m = RegExp(r'ResourceKey<Registry<(.*)>>$').firstMatch(fld.type);
    valueType[fld.name] = m == null ? fld.type : norm(m.group(1)!);
  }
  final intrusive = <String, bool>{};
  for (final fld in bi.fields) {
    final m = RegExp(r'CreateRegistries\.(\w+)').firstMatch(fld.init);
    if (m != null) intrusive[m.group(1)!] = fld.init.contains('withIntrusiveHolders');
  }

  // --- entries per registry constant
  final entries = <String, List<T>>{};
  final regIn = <String, String>{};

  // arm interaction point types
  {
    final rel = 'content/kinetics/mechanicalArm/AllArmInteractionPointTypes.java';
    final f = jf(rel);
    final c = topClass(rel);
    final l = <T>[];
    for (final m in RegExp(r'register\("([^"]+)",\s*new\s+(\w[\w.]*)\(').allMatches(c.body)) {
      l.add(entry(m.group(1)!, fqn(m.group(2)!, f, ctx: c)));
    }
    entries['ARM_INTERACTION_POINT_TYPE'] = l;
    regIn['ARM_INTERACTION_POINT_TYPE'] = '$_pkg.content.kinetics.mechanicalArm.AllArmInteractionPointTypes';
  }
  // fan processing types
  {
    final rel = 'content/kinetics/fan/processing/AllFanProcessingTypes.java';
    final f = jf(rel);
    final c = topClass(rel);
    final l = <T>[];
    for (final m in RegExp(r'register\("([^"]+)",\s*new\s+(\w[\w.]*)\(').allMatches(c.body)) {
      l.add(entry(m.group(1)!, fqn(m.group(2)!, f, ctx: c)));
    }
    entries['FAN_PROCESSING_TYPE'] = l;
    regIn['FAN_PROCESSING_TYPE'] = '$_pkg.content.kinetics.fan.processing.AllFanProcessingTypes';
  }
  // item attribute types
  {
    final rel = 'content/logistics/item/filter/attribute/AllItemAttributeTypes.java';
    final f = jf(rel);
    final c = topClass(rel);
    final l = <T>[];
    final re = RegExp(r'singleton\("(\w+)"|register\("(\w+)",\s*new\s+(\w[\w.]*)\(');
    for (final m in re.allMatches(c.body)) {
      if (m.group(1) != null) {
        l.add(entry(m.group(1)!, '$_pkg.content.logistics.item.filter.attribute.SingletonItemAttribute.Type',
            'singleton predicate attribute (translation key = id)'));
      } else {
        l.add(entry(m.group(2)!, fqn(m.group(3)!, f, ctx: c)));
      }
    }
    entries['ITEM_ATTRIBUTE_TYPE'] = l;
    regIn['ITEM_ATTRIBUTE_TYPE'] = '$_pkg.content.logistics.item.filter.attribute.AllItemAttributeTypes';
  }
  // display sources / targets
  for (final spec in [
    ('DISPLAY_SOURCE', 'AllDisplaySources.java', 'displaySource'),
    ('DISPLAY_TARGET', 'AllDisplayTargets.java', 'displayTarget'),
  ]) {
    final f = jf(spec.$2);
    final c = topClass(spec.$2);
    final l = <T>[];
    for (final fld in c.fields) {
      if (!fld.type.startsWith('RegistryEntry')) continue;
      final ch = parseChain(fld.init);
      final c0 = ch.calls.first;
      String key;
      String ctor;
      if (c0.key == 'simple') {
        final a = splitArgs(c0.value);
        key = firstString(a[0])!;
        ctor = ctorRef(a[1])!;
      } else {
        final a = splitArgs(c0.value);
        key = firstString(a[0])!;
        ctor = ctorRef(a[1])!;
      }
      final assoc = [for (final x in ch.calls) if (x.key == 'associate') norm(x.value)];
      final extra = ch.has('onRegisterAfter') ? 'onRegisterAfter(BLOCK_ENTITY_TYPE): ComputerCraft compat only' : '';
      final nt = [if (assoc.isNotEmpty) 'associate: ${assoc.join(', ')}', if (extra.isNotEmpty) extra].join('; ');
      _displayConstKey['${spec.$2.replaceAll('.java', '')}.${fld.name}'] = key;
      l.add(entry(key, fqn(ctor, f, ctx: c), nt));
    }
    entries[spec.$1] = l;
    regIn[spec.$1] = '$_pkg.${spec.$2.replaceAll('.java', '')}';
  }
  // mounted storage types
  {
    final rel = 'AllMountedStorageTypes.java';
    final f = jf(rel);
    final c = topClass(rel);
    final item = <T>[], fluid = <T>[];
    for (final fld in c.fields) {
      if (!fld.type.startsWith('RegistryEntry')) continue;
      final ch = parseChain(fld.init);
      final c0 = ch.calls.first;
      final a = splitArgs(c0.value);
      final key = firstString(a[0])!;
      final ctor = ctorRef(a[1])!;
      final isFluid = fld.type.contains('MountedFluidStorageType');
      final assoc = [
        for (final x in ch.calls)
          if (x.key == 'associate' || x.key == 'associateBlockTag') '${x.key}(${norm(x.value)})'
      ];
      final cl = fqn(ctor, f, ctx: c);
      (isFluid ? fluid : item).add(entry(key, cl, assoc.isEmpty ? (key == 'fallback' ? 'fallback provider, registered last on lookup creation' : 'associated by the block definition') : assoc.join('; ')));
    }
    entries['MOUNTED_ITEM_STORAGE_TYPE'] = item;
    entries['MOUNTED_FLUID_STORAGE_TYPE'] = fluid;
    regIn['MOUNTED_ITEM_STORAGE_TYPE'] = '$_pkg.AllMountedStorageTypes';
    regIn['MOUNTED_FLUID_STORAGE_TYPE'] = '$_pkg.AllMountedStorageTypes';
  }
  // contraption types
  {
    final rel = 'AllContraptionTypes.java';
    final f = jf(rel);
    final c = topClass(rel);
    final l = <T>[];
    for (final fld in c.fields) {
      if (!fld.type.startsWith('Reference')) continue;
      final a = splitArgs(parseChain(fld.init).calls.first.value);
      l.add(entry(firstString(a[0])!, fqn(ctorRef(a[1])!, f, ctx: c), 'ContraptionType factory; also BY_LEGACY_NAME'));
    }
    entries['CONTRAPTION_TYPE'] = l;
    regIn['CONTRAPTION_TYPE'] = '$_pkg.AllContraptionTypes';
  }
  // package port target types
  {
    final rel = 'content/logistics/packagePort/AllPackagePortTargetTypes.java';
    final f = jf(rel);
    final c = topClass(rel);
    final l = <T>[];
    for (final m in RegExp(r'REGISTER\.register\("([^"]+)",\s*([\w.]+)::new\)').allMatches(c.body)) {
      l.add(entry(m.group(1)!, fqn(m.group(2)!, f, ctx: c)));
    }
    entries['PACKAGE_PORT_TARGET_TYPE'] = l;
    regIn['PACKAGE_PORT_TARGET_TYPE'] = '$_pkg.content.logistics.packagePort.AllPackagePortTargetTypes';
  }
  // potato codecs
  for (final spec in [
    ('POTATO_PROJECTILE_RENDER_MODE', 'AllPotatoProjectileRenderModes'),
    ('POTATO_PROJECTILE_ENTITY_HIT_ACTION', 'AllPotatoProjectileEntityHitActions'),
    ('POTATO_PROJECTILE_BLOCK_HIT_ACTION', 'AllPotatoProjectileBlockHitActions'),
  ]) {
    final rel = 'content/equipment/potatoCannon/${spec.$2}.java';
    final f = jf(rel);
    final c = topClass(rel);
    final l = <T>[];
    for (final m in RegExp(r'register\("([^"]+)",\s*([\w.]+)\.CODEC\)').allMatches(c.body)) {
      final cc = resolve(m.group(2)!, f, ctx: c);
      var shape = '';
      var ok = true;
      if (cc != null) {
        final cf = cc.field('CODEC');
        shape = '${recordComponents(cc)}${cf == null ? '' : ' codec: ${norm(cf.init)}'}';
      } else {
        ok = false;
      }
      l.add(entry(m.group(1)!, fqn(m.group(2)!, f, ctx: c), shape, ok));
    }
    entries[spec.$1] = l;
    regIn[spec.$1] = '$_pkg.content.equipment.potatoCannon.${spec.$2}';
  }
  // potato projectile type (datapack registry; entries from bootstrap)
  {
    final rel = 'content/equipment/potatoCannon/AllPotatoProjectileTypes.java';
    final c = topClass(rel);
    final l = <T>[];
    for (final m in RegExp(r'register\(ctx,\s*"([^"]+)"').allMatches(c.body)) {
      l.add(entry(m.group(1)!, '$_pkg.api.equipment.potatoCannon.PotatoCannonProjectileType', 'datapack registry entry bootstrapped in Java; json under data/create/create/potato_projectile/type'));
    }
    entries['POTATO_PROJECTILE_TYPE'] = l;
    regIn['POTATO_PROJECTILE_TYPE'] = '$_pkg.content.equipment.potatoCannon.AllPotatoProjectileTypes';
  }

  for (final k in keyOf.keys) {
    final isPotatoType = k == 'POTATO_PROJECTILE_TYPE';
    regs.add(T('CustomRegistryDef', {
      'key': keyOf[k],
      'valueType': valueType[k],
      'intrusiveHolders': intrusive[k] ?? false,
      'syncedToClient': !isPotatoType,
      'registeredIn': regIn[k] ?? '',
      'entries': entries[k] ?? <T>[],
      'verified': entries.containsKey(k),
    }));
    if (!entries.containsKey(k)) unsure('Custom registry ${keyOf[k]}: no entries extracted');
  }
  return regs;
}

List<T> extractPotatoTypes() {
  final out = <T>[];
  final javaKeys = <String>[
    for (final m in RegExp(r'register\(ctx,\s*"([^"]+)"').allMatches(topClass('content/equipment/potatoCannon/AllPotatoProjectileTypes.java').body)) m.group(1)!
  ];
  final dir = '$res/data/create/create/potato_projectile/type';
  final fileKeys = Directory(dir)
      .listSync()
      .whereType<File>()
      .map((f) => f.path.substring(dir.length + 1, f.path.length - 5))
      .toSet();
  for (final k in javaKeys) {
    if (!fileKeys.contains(k)) {
      unsure('PotatoProjectileType $k: json missing');
      continue;
    }
    out.add(T('PotatoProjectileTypeDef', {'key': k, 'rawJson': File('$dir/$k.json').readAsStringSync()}));
  }
  for (final k in fileKeys) {
    if (!javaKeys.contains(k)) unsure('PotatoProjectileType json $k has no bootstrap entry');
  }
  return out;
}

// ----------------------------------------------------------- CREATIVE TABS

String _blockOrItemKey(String expr) {
  final m = RegExp(r'^All(Blocks|Items|PaletteBlocks)\.(\w+)').firstMatch(expr.trim());
  if (m == null) return expr.trim();
  final c = m.group(2)!;
  if (m.group(1) == 'Blocks') return blockKeyByConst[c] ?? '?$c';
  if (m.group(1) == 'Items') return itemKeyByConst[c] ?? '?$c';
  return blockKeyByConst['palette:$c'] ?? '?$c';
}

List<T> extractCreativeTabs() {
  final cls = topClass('AllCreativeModeTabs.java');
  final text = cls.body;
  final out = <T>[];
  final excluded = <String>[];
  final searchOnly = <String>[];
  // exclusions
  final simpleEx = RegExp(r'simpleExclusions\s*=\s*List\.of\((.*?)\);', dotAll: true).firstMatch(text);
  if (simpleEx != null) {
    for (final a in splitArgs(simpleEx.group(1)!)) {
      excluded.add(_blockOrItemKey(a));
    }
  }
  final tagEx = RegExp(r'tagDependentExclusions\s*=\s*List\.of\((.*?)\);', dotAll: true).firstMatch(text);
  final tagDep = <String>[];
  if (tagEx != null) {
    for (final a in splitArgs(tagEx.group(1)!)) {
      tagDep.add(_blockOrItemKey(a));
    }
  }
  final orderings = <T>[];
  for (final spec in [('simpleBeforeOrderings', true), ('simpleAfterOrderings', false)]) {
    final m = RegExp('${spec.$1}\\s*=\\s*Map\\.of\\((.*?)\\);', dotAll: true).firstMatch(text);
    if (m == null) continue;
    final a = splitArgs(m.group(1)!);
    for (var i = 0; i + 1 < a.length; i += 2) {
      orderings.add(T('CreativeTabItemOrderingDef', {'item': _blockOrItemKey(a[i]), 'anchor': _blockOrItemKey(a[i + 1]), 'before': spec.$2}));
    }
  }
  final vis = RegExp(r'simpleVisibilities\s*=\s*Map\.of\((.*?)\);', dotAll: true).firstMatch(text);
  if (vis != null) {
    final a = splitArgs(vis.group(1)!);
    for (var i = 0; i + 1 < a.length; i += 2) {
      if (a[i + 1].contains('SEARCH_TAB_ONLY')) searchOnly.add(_blockOrItemKey(a[i]));
    }
  }
  for (final l in ['DYED_VALVE_HANDLES']) {
    searchOnly.addAll(dyedLists[l] ?? []);
  }
  // other search-only rules: all non-default dyed seats/table cloths/postboxes/toolboxes
  searchOnly
    ..addAll((dyedLists['SEATS'] ?? []).where((k) => !k.startsWith('red_')))
    ..addAll((dyedLists['TABLE_CLOTHS'] ?? []).where((k) => !k.startsWith('red_')))
    ..addAll((dyedLists['PACKAGE_POSTBOXES'] ?? []).where((k) => !k.startsWith('white_')))
    ..addAll((dyedLists['TOOLBOXES'] ?? []).where((k) => !k.startsWith('brown_')));

  final re = RegExp(r'REGISTER\.register\("(\w+)",\s*\(\)\s*->\s*CreativeModeTab\.builder\(\)(.*?)\.build\(\)\)', dotAll: true);
  for (final m in re.allMatches(text)) {
    final key = m.group(1)!;
    final b = m.group(2)!;
    final title = RegExp(r'translatable\("([^"]+)"\)').firstMatch(b)!.group(1)!;
    final before = <String>[];
    final tb = RegExp(r'withTabsBefore\(([^)]*(?:\([^)]*\))?[^)]*)\)').firstMatch(b);
    if (tb != null) {
      for (final a in splitArgs(tb.group(1)!)) {
        final cm = RegExp(r'CreativeModeTabs\.(\w+)').firstMatch(a);
        if (cm != null) {
          before.add('minecraft:${cm.group(1)!.toLowerCase()}');
        } else {
          final bm = RegExp(r'(\w+)_CREATIVE_TAB').firstMatch(a);
          before.add('create:${bm?.group(1)?.toLowerCase() ?? a}');
        }
      }
    }
    final icon = RegExp(r'\.icon\(\(\)\s*->\s*(.*?)\.asStack\(\)\)').firstMatch(b)!.group(1)!;
    final addItems = RegExp(r'RegistrateDisplayItemsGenerator\((true|false)').firstMatch(b)!.group(1) == 'true';
    final iconKey = _blockOrItemKey(icon);
    var ok = !iconKey.startsWith('?');
    if (!langHas(title)) {
      ok = false;
      unsure('CreativeTab $key: no lang $title');
    }
    out.add(T('CreativeTabDef', {
      'key': key,
      'titleKey': title,
      'iconBlockOrItem': 'create:$iconKey',
      'tabsBefore': before,
      'includesItems': addItems,
      'excluded': [...excluded, ...tagDep],
      'searchOnly': searchOnly,
      'orderings': orderings,
      'stackComponents': {
        'copper_backtank': 'create:banktank_air=BacktankUtil.maxAirWithoutEnchants()',
        'netherite_backtank': 'create:banktank_air=BacktankUtil.maxAirWithoutEnchants()',
      },
      'contentSources': key == 'base'
          ? 'First all blocks with a BlockItem registered while Registrate current tab == base (AllBlocks fields before the `setCreativeTab(PALETTES)` static block at ~line 2302, in registration order), then all non-BlockItem items registered under base (AllItems, in registration order), minus exclusions; orderings applied afterwards (BEFORE/AFTER moves); the 3D-item predicate pass is a no-op because collectItems skips BlockItems. Excluded additionally: PackageStyles.RARE_BOXES, tag dependent crushed ores when hidden. Items listed in searchOnly use TabVisibility.SEARCH_TAB_ONLY, everything else PARENT_AND_SEARCH_TABS.'
          : 'Blocks only (no items): all BlockItems registered while Registrate current tab == palettes, i.e. AllBlocks fields after the `setCreativeTab(PALETTES)` switch plus everything registered by AllPaletteBlocks (and its stone-type / wood-type generators), in registration order, minus exclusions.',
      'verified': ok,
    }));
  }
  return out;
}

/// Fills creative tab contentOrder (best effort).
void fillCreativeContent(List<T> tabs) {
  final ab = topClass('AllBlocks.java');
  final switchIdx = ab.body.indexOf('setCreativeTab(AllCreativeModeTabs.PALETTES_CREATIVE_TAB)');
  final baseBlocks = <String>[];
  final palBlocks = <String>[];
  for (final fld in ab.fields) {
    if (!fld.type.startsWith('BlockEntry') && !fld.type.startsWith('DyedBlockList')) continue;
    final pos = ab.body.indexOf(RegExp('\\b${fld.name}\\s*='));
    final keys = fld.type.startsWith('DyedBlockList') ? (dyedLists[fld.name] ?? []) : [if (blockKeyByConst[fld.name] != null) blockKeyByConst[fld.name]!];
    for (final k in keys) {
      // block has a BlockItem when a generated item model (or item lang) exists
      if (!File('$res/assets/create/models/item/$k.json').existsSync()) continue;
      (pos < switchIdx ? baseBlocks : palBlocks).add(k);
    }
  }
  final items = <String>[];
  final ai = topClass('AllItems.java');
  for (final fld in ai.fields) {
    if (!fld.type.startsWith('ItemEntry')) continue;
    final k = itemKeyByConst[fld.name];
    if (k != null) items.add(k);
  }
  for (final t in tabs) {
    final key = t.fields['key'];
    final ex = Set<String>.of((t.fields['excluded'] as List).cast<String>());
    if (key == 'base') {
      final l = <String>[...baseBlocks.where((k) => !ex.contains(k)), ...items.where((k) => !ex.contains(k))];
      // apply orderings
      for (final o in (t.fields['orderings'] as List).cast<T>()) {
        final item = o.fields['item'] as String, anchor = o.fields['anchor'] as String;
        final ai2 = l.indexOf(anchor);
        if (ai2 < 0) continue;
        var ii = l.indexOf(item);
        var a2 = ai2;
        if (ii >= 0) {
          l.removeAt(ii);
          if (ii < a2) a2--;
        }
        l.insert((o.fields['before'] as bool) ? a2 : a2 + 1, item);
      }
      t.fields['contentOrder'] = l;
    } else {
      t.fields['contentOrder'] = palBlocks.where((k) => !ex.contains(k)).toList();
    }
    t.fields['contentOrderComplete'] = false;
    t.fields['verified'] = false;
  }
  unsure('CreativeTab contentOrder is approximate: block/item keys come from AllBlocks/AllItems field order '
      '(block items detected via generated item models); blocks registered by AllPaletteBlocks / palette generators, '
      'cardboard/package styles registered in loops and fluid buckets are not included. Prefer blocks.g.dart/items.g.dart '
      'registration order from the block/item extractors for the authoritative order.');
}

// -------------------------------------------------------------------- main

void main(List<String> args) {
  root = args.isNotEmpty ? args[0] : _defaultRoot;
  javaRoot = '$root/src/main/java';
  res = '$root/src/generated/resources';
  idx = SourceIndex([Directory(javaRoot)])..build();
  lang = jsonDecode(readRes('assets/create/lang/en_us.json')) as Map<String, dynamic>;

  buildBlockMaps();
  // custom registries first so display keys are known to block entity types
  final custom = extractCustomRegistries();
  final bet = extractBlockEntityTypes();
  final ent = extractEntityTypes();
  final menus = extractMenuTypes();
  final dcs = extractDataComponents();
  final fluids = extractFluids();
  final recipes = extractRecipeTypes();
  final dmg = extractDamageTypes();
  final ench = extractEnchantments();
  final snd = extractSounds();
  final part = extractParticles();
  final eds = extractEntityDataSerializers();
  final mdec = extractMapDecorations();
  final adv = extractAdvancements();
  final potato = extractPotatoTypes();
  final tabs = extractCreativeTabs();
  fillCreativeContent(tabs);

  // cross checks
  final entLang = lang.keys.where((k) => k.startsWith('entity.create.')).length;
  if (entLang != ent.length) unsure('entity lang count $entLang != ${ent.length}');
  for (final e in ent) {
    if (!langHas('entity.create.${e.fields['key']}')) unsure('EntityType ${e.fields['key']}: no entity lang');
  }
  final fluidLang = lang.keys.where((k) => k.startsWith('fluid.create.')).length;
  if (fluidLang != fluids.length) unsure('fluid lang count $fluidLang != ${fluids.length}');
  final subLang = lang.keys.where((k) => k.startsWith('create.subtitle.')).length;
  final subJava = snd.where((s) => s.fields['subtitle'] != null).length;
  if (subLang != subJava) unsure('sound subtitle lang count $subLang != java subtitles $subJava');
  final dmgLang = lang.keys.where((k) => RegExp(r'^death\.attack\.create\.\w+$').hasMatch(k)).length;
  notes.add('Lang cross-check: death.attack.create.<id> keys: $dmgLang (damage types extracted: ${dmg.length}; potato_cannon also has .item variant).');
  final enchLang = lang.keys.where((k) => RegExp(r'^enchantment\.create\.\w+$').hasMatch(k)).length;
  if (enchLang != ench.length) unsure('enchantment lang count $enchLang != ${ench.length}');

  counts['block entity types'] = bet.length;
  counts['entity types'] = ent.length;
  counts['menu types'] = menus.length;
  counts['data components'] = dcs.length;
  counts['fluids'] = fluids.length;
  counts['recipe types'] = recipes.length;
  counts['damage types'] = dmg.length;
  counts['enchantments'] = ench.length;
  counts['sound entries'] = snd.length;
  counts['sound events registered'] = snd.fold(0, (a, s) => a + (s.fields['registeredEvents'] as List).length);
  counts['particle types'] = part.length;
  counts['entity data serializers'] = eds.length;
  counts['map decorations'] = mdec.length;
  counts['advancements (create tree)'] = adv.advancements.where((a) => a.fields['kind'] == 'create').length;
  counts['advancements (recipe unlocks)'] = adv.advancements.where((a) => a.fields['kind'] == 'recipe').length;
  counts['custom triggers'] = adv.triggers.length;
  counts['custom registries'] = custom.length;
  for (final c in custom) {
    counts['  registry ${c.fields['key']}'] = (c.fields['entries'] as List).length;
  }
  counts['potato projectile types (json)'] = potato.length;
  counts['creative tabs'] = tabs.length;

  // ---- write registries.g.dart
  final b = StringBuffer();
  b.writeln('// GENERATED by tool/extract_registries.dart - never hand-edit.');
  b.writeln('// Source: ${root.split('/').last} (src/main/java + src/generated/resources).');
  b.writeln('// ignore_for_file: type=lint, prefer_single_quotes, unnecessary_const, lines_longer_than_80_chars');
  b.writeln();
  b.writeln("import 'types_registries.dart';");
  b.writeln();
  void list(String type, String name, List<T> l, String doc) {
    b.writeln('/// $doc (${l.length}), registration order.');
    b.writeln('const List<$type> $name = [');
    for (final e in l) {
      b.writeln('  ${lit(e, 1)},');
    }
    b.writeln('];');
    b.writeln();
  }

  list('BlockEntityTypeDef', 'kBlockEntityTypes', bet, 'Block entity types');
  list('EntityTypeDef', 'kEntityTypes', ent, 'Entity types');
  list('MenuTypeDef', 'kMenuTypes', menus, 'Menu types');
  list('DataComponentDef', 'kDataComponents', dcs, 'Data component types');
  list('FluidDef', 'kFluids', fluids, 'Fluids');
  list('RecipeTypeDef', 'kRecipeTypes', recipes, 'Recipe types / serializers');
  list('DamageTypeDef', 'kDamageTypes', dmg, 'Damage types');
  list('EnchantmentDef', 'kEnchantments', ench, 'Enchantments');
  list('SoundEventDef', 'kSoundEvents', snd, 'Sound entries');
  list('ParticleTypeDef', 'kParticleTypes', part, 'Particle types');
  list('EntityDataSerializerDef', 'kEntityDataSerializers', eds, 'Entity data serializers');
  list('MapDecorationDef', 'kMapDecorations', mdec, 'Map decoration types');
  list('AdvancementDef', 'kAdvancements', adv.advancements, 'Advancements (create tree first, then recipe unlocks)');
  list('TriggerDef', 'kTriggers', adv.triggers, 'Custom advancement triggers');
  list('CustomRegistryDef', 'kCustomRegistries', custom, 'Custom registries');
  list('PotatoProjectileTypeDef', 'kPotatoProjectileTypes', potato, 'Potato projectile types (json)');
  list('CreativeTabDef', 'kCreativeTabs', tabs, 'Creative tabs');
  b.writeln('const RegistriesManifest kRegistriesManifest = RegistriesManifest(');
  for (final p in [
    ['blockEntityTypes', 'kBlockEntityTypes'],
    ['entityTypes', 'kEntityTypes'],
    ['menuTypes', 'kMenuTypes'],
    ['dataComponents', 'kDataComponents'],
    ['fluids', 'kFluids'],
    ['recipeTypes', 'kRecipeTypes'],
    ['damageTypes', 'kDamageTypes'],
    ['enchantments', 'kEnchantments'],
    ['soundEvents', 'kSoundEvents'],
    ['particleTypes', 'kParticleTypes'],
    ['entityDataSerializers', 'kEntityDataSerializers'],
    ['mapDecorations', 'kMapDecorations'],
    ['advancements', 'kAdvancements'],
    ['triggers', 'kTriggers'],
    ['customRegistries', 'kCustomRegistries'],
    ['potatoProjectileTypes', 'kPotatoProjectileTypes'],
    ['creativeTabs', 'kCreativeTabs'],
  ]) {
    b.writeln('  ${p[0]}: ${p[1]},');
  }
  b.writeln(');');
  File('lib/src/manifest/registries.g.dart').writeAsStringSync(b.toString());

  // ---- report
  bool unv(T t) => t.fields['verified'] == false;
  final unverified = <String, List<String>>{};
  void collect(String name, List<T> l, String Function(T) id) {
    final u = l.where(unv).map(id).toList();
    if (u.isNotEmpty) unverified[name] = u;
  }

  collect('block entity types', bet, (t) => t.fields['key'] as String);
  collect('entity types', ent, (t) => t.fields['key'] as String);
  collect('data components', dcs, (t) => t.fields['key'] as String);
  collect('fluids', fluids, (t) => t.fields['key'] as String);
  collect('recipe types', recipes, (t) => t.fields['key'] as String);
  collect('damage types', dmg, (t) => t.fields['key'] as String);
  collect('enchantments', ench, (t) => t.fields['key'] as String);
  collect('sound entries', snd, (t) => t.fields['key'] as String);
  collect('advancements', adv.advancements, (t) => t.fields['id'] as String);
  collect('custom registries', custom, (t) => t.fields['key'] as String);
  collect('creative tabs', tabs, (t) => t.fields['key'] as String);
  final r = StringBuffer();
  r.writeln('# Registries extraction report');
  r.writeln();
  r.writeln('Generated by `tool/extract_registries.dart` (do not edit). Source: `$root`.');
  r.writeln();
  r.writeln('## Counts');
  r.writeln();
  counts.forEach((k, v) => r.writeln('- $k: $v'));
  r.writeln();
  r.writeln('## Entries marked `verified: false`');
  r.writeln();
  if (unverified.isEmpty) r.writeln('(none)');
  unverified.forEach((k, v) => r.writeln('- $k (${v.length}): ${v.join(', ')}'));
  r.writeln();
  r.writeln('## Uncertain items / diagnostics');
  r.writeln();
  if (uncertain.isEmpty) r.writeln('(none)');
  for (final u in uncertain) {
    r.writeln('- $u');
  }
  r.writeln();
  r.writeln('## Notes');
  r.writeln();
  for (final n in notes) {
    r.writeln('- $n');
  }
  r.writeln('- Not part of this extraction: blocks, items, payloads, config, stress values, tags (other agents); '
      'worldgen/biome modifiers, loot tables, recipe json bodies and the `data_maps` json are untouched.');
  File('lib/src/manifest/REPORT_registries.md').writeAsStringSync(r.toString());
  stdout.writeln('wrote registries.g.dart and REPORT_registries.md');
  counts.forEach((k, v) => stdout.writeln('$k: $v'));
  stdout.writeln('uncertain: ${uncertain.length}');
}

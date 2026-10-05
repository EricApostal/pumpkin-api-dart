/// Reads the Lonsdaleite mod's Java sources (the `common/` classes and the
/// NeoForge entry point) into the data the manifest needs. Only the Java the
/// mod actually uses is understood; everything else is a [JavaParseError], so a
/// mod update that adds something new fails loudly instead of being skipped.
library;

import 'dart:io';

import 'java_text.dart';
import 'vanilla.dart';

/// `ToolMaterial` and `ArmorMaterial` constants plus the tags they reference.
final class ModMaterials {
  /// `LonsdaleiteToolMaterials.NAME` to its tier.
  final Map<String, ToolMaterialSpec> tools;

  /// `LonsdaleiteArmorMaterials.NAME` to its tier.
  final Map<String, ArmorMaterialSpec> armor;

  /// Java constant of a `TagKey` to its id (`lonsdaleite:repairs_lonsdaleite_tools`).
  final Map<String, String> tags;

  const ModMaterials(this.tools, this.armor, this.tags);
}

/// What `Item.Properties` the mod's registration ends up with and where it came from.
final class ItemRegistration {
  /// The Java field, e.g. `LONSDALEITE_PICKAXE`.
  final String field;

  /// Registry id, e.g. `lonsdaleite:lonsdaleite_pickaxe`.
  final String id;

  /// The Java class instantiated (`Item` for the vanilla one).
  final String javaClass;

  /// The class' superclass (`Item`, `MaceItem`, `BlockItem`).
  final String javaSuper;

  /// Methods the class overrides.
  final List<String> overrides;

  /// The builder calls on `Item.Properties`, in order, as Java source.
  final List<String> builderCalls;

  /// The components those builders produce.
  final Json components;

  /// The registration's lambda, verbatim.
  final String source;

  /// The tool/armor material constant used, if any.
  final String? toolMaterial;
  final String? armorMaterial;

  /// Armor slot constant (`HELMET`), if armor.
  final String? armorType;

  const ItemRegistration({
    required this.field,
    required this.id,
    required this.javaClass,
    required this.javaSuper,
    required this.overrides,
    required this.builderCalls,
    required this.components,
    required this.source,
    this.toolMaterial,
    this.armorMaterial,
    this.armorType,
  });
}

/// The block and its class.
final class BlockRegistration {
  final String field;
  final String id;
  final String javaClass;
  final String javaSuper;
  final List<String> overrides;

  /// `BlockBehaviour.Properties` builder calls in Java source.
  final List<String> builderCalls;
  final double destroyTime;
  final double explosionResistance;
  final String soundType;
  final bool canOcclude;
  final bool requiresCorrectToolForDrops;
  final int lightLevel;
  final bool isSuffocating;
  final bool isViewBlocking;

  /// The boolean properties of the block state in definition order.
  final List<String> properties;

  /// The default value of each property.
  final Map<String, bool> defaults;

  const BlockRegistration({
    required this.field,
    required this.id,
    required this.javaClass,
    required this.javaSuper,
    required this.overrides,
    required this.builderCalls,
    required this.destroyTime,
    required this.explosionResistance,
    required this.soundType,
    required this.canOcclude,
    required this.requiresCorrectToolForDrops,
    required this.lightLevel,
    required this.isSuffocating,
    required this.isViewBlocking,
    required this.properties,
    required this.defaults,
  });
}

/// An `insertAfter` of the mod's items in a vanilla creative tab.
final class TabInsertion {
  final String tab;
  final String after;
  final String item;
  final String visibility;

  const TabInsertion(this.tab, this.after, this.item, this.visibility);
}

/// The mod's own creative tab.
final class CreativeTabSpec {
  final String id;
  final String titleKey;
  final String icon;
  final List<String> items;

  const CreativeTabSpec(this.id, this.titleKey, this.icon, this.items);
}

/// The `common/` and `neoforge/` sources of a checkout.
final class ModSource {
  final Directory root;

  ModSource(this.root);

  String _read(String relative) {
    final file = File('${root.path}/$relative');
    if (!file.existsSync()) {
      throw JavaParseError('Missing ${file.path}');
    }
    return stripJavaComments(file.readAsStringSync());
  }

  static const _pkg = 'common/src/main/java/com/kestalkayden/lonsdaleite';
  static const _entry =
      'neoforge/src/main/java/com/kestalkayden/lonsdaleite/Lonsdaleite.java';

  late final String modId = _modId();

  String _modId() {
    final m = RegExp(r'MOD_ID\s*=\s*"([^"]+)"').firstMatch(_read('$_pkg/LonsdaleiteCommon.java'));
    if (m == null) throw JavaParseError('MOD_ID not found');
    return m.group(1)!;
  }

  /// All Java classes of `common/` by simple name.
  late final Map<String, String> _classSources = {
    for (final f in Directory('${root.path}/$_pkg')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.java')))
      f.uri.pathSegments.last.replaceAll('.java', ''):
          stripJavaComments(f.readAsStringSync()),
  };

  late final ModMaterials materials = _parseMaterials();

  ModMaterials _parseMaterials() {
    final toolSrc = _classSources['LonsdaleiteToolMaterials']!;
    final armorSrc = _classSources['LonsdaleiteArmorMaterials']!;

    final tags = <String, String>{};
    final tagPattern = RegExp(
      r'TagKey<Item>\s+(\w+)\s*=\s*TagKey\.create\(\s*Registries\.ITEM,\s*'
      r'Identifier\.fromNamespaceAndPath\(LonsdaleiteCommon\.MOD_ID,\s*"([^"]+)"\)\)',
    );
    for (final m in tagPattern.allMatches(toolSrc)) {
      tags[m.group(1)!] = '$modId:${m.group(2)}';
    }

    final tools = <String, ToolMaterialSpec>{};
    for (final m in RegExp(r'ToolMaterial\s+(\w+)\s*=\s*new ToolMaterial\(')
        .allMatches(toolSrc)) {
      final open = m.end - 1;
      final args = splitTopLevel(
        toolSrc.substring(open + 1, indexOfClosing(toolSrc, open)),
      );
      if (args.length != 6) {
        throw JavaParseError('ToolMaterial ${m.group(1)} has ${args.length} args');
      }
      tools[m.group(1)!] = ToolMaterialSpec(
        incorrectBlocksForDrops: _incorrectTag(args[0]),
        durability: parseJavaNumber(args[1]).asInt,
        speed: parseJavaNumber(args[2]).value,
        attackDamageBonus: parseJavaNumber(args[3]).value,
        enchantmentValue: parseJavaNumber(args[4]).asInt,
        repairItems: _tagConstant(args[5], tags),
      );
    }
    _checkMaterialHelpers(toolSrc, tools);

    final assetPattern = RegExp(
      r'ResourceKey<EquipmentAsset>\s+(\w+)\s*=\s*ResourceKey\.create\(\s*EquipmentAssets\.ROOT_ID,\s*'
      r'Identifier\.fromNamespaceAndPath\(LonsdaleiteCommon\.MOD_ID,\s*"([^"]+)"\)\)',
    );
    final assets = {
      for (final m in assetPattern.allMatches(armorSrc))
        m.group(1)!: '$modId:${m.group(2)}',
    };

    final armor = <String, ArmorMaterialSpec>{};
    for (final m in RegExp(r'ArmorMaterial\s+(\w+)\s*=\s*new ArmorMaterial\(')
        .allMatches(armorSrc)) {
      final open = m.end - 1;
      final args = splitTopLevel(
        armorSrc.substring(open + 1, indexOfClosing(armorSrc, open)),
      );
      if (args.length != 8) {
        throw JavaParseError('ArmorMaterial ${m.group(1)} has ${args.length} args');
      }
      final asset = assets[args[7]];
      if (asset == null) throw JavaParseError('Unknown equipment asset ${args[7]}');
      armor[m.group(1)!] = ArmorMaterialSpec(
        durability: parseJavaNumber(args[0]).asInt,
        defense: _defenseMap(args[1]),
        enchantmentValue: parseJavaNumber(args[2]).asInt,
        equipSound: _equipSound(args[3]),
        toughness: parseJavaNumber(args[4]).value,
        knockbackResistance: parseJavaNumber(args[5]).value,
        repairItems: _tagConstant(args[6], tags),
        assetId: asset,
      );
    }
    return ModMaterials(tools, armor, tags);
  }

  static String _incorrectTag(String expression) {
    final m = RegExp(r'^ToolMaterial\.(\w+)\.incorrectBlocksForDrops\(\)$')
        .firstMatch(expression.trim());
    final tag = m == null ? null : vanillaIncorrectTags[m.group(1)];
    if (tag == null) {
      throw JavaParseError('Unsupported incorrectBlocksForDrops `$expression`');
    }
    return tag;
  }

  static String _tagConstant(String expression, Map<String, String> tags) {
    final name = expression.trim().split('.').last;
    final tag = tags[name];
    if (tag == null) throw JavaParseError('Unknown tag constant `$expression`');
    return tag;
  }

  static Map<ArmorType, int> _defenseMap(String expression) {
    final m = RegExp(r'^Map\.of\((.*)\)$', dotAll: true).firstMatch(expression.trim());
    if (m == null) throw JavaParseError('Expected Map.of(...) in `$expression`');
    final parts = splitTopLevel(m.group(1)!);
    if (parts.length.isOdd) throw JavaParseError('Odd Map.of arguments');
    return {
      for (var i = 0; i < parts.length; i += 2)
        ArmorType.fromJava(parts[i].split('.').last): parseJavaNumber(parts[i + 1]).asInt,
    };
  }

  static String _equipSound(String expression) {
    final name = expression.trim().split('.').last;
    const prefix = 'ARMOR_EQUIP_';
    if (!name.startsWith(prefix)) {
      throw JavaParseError('Unsupported equip sound `$expression`');
    }
    return 'minecraft:item.armor.equip_${name.substring(prefix.length).toLowerCase()}';
  }

  /// `getAttackDamage`, `getMiningSpeed` and `getEnchantability` hard-code the
  /// numbers of the two tiers; they must agree with the constructor calls.
  void _checkMaterialHelpers(String source, Map<String, ToolMaterialSpec> tools) {
    final helpers = <String, double Function(ToolMaterialSpec)>{
      'getAttackDamage': (m) => m.attackDamageBonus,
      'getMiningSpeed': (m) => m.speed,
      'getEnchantability': (m) => m.enchantmentValue.toDouble(),
    };
    helpers.forEach((name, read) {
      final start = source.indexOf(' $name(');
      if (start < 0) return;
      final open = source.indexOf('{', start);
      final body = source.substring(open, indexOfClosing(source, open));
      for (final m in RegExp(r'material == (\w+)\)\s*\{\s*return ([\d.]+)F?;').allMatches(body)) {
        final spec = tools[m.group(1)!];
        if (spec == null || toFloat32(double.parse(m.group(2)!)) != toFloat32(read(spec))) {
          throw JavaParseError('$name disagrees with the ${m.group(1)} constructor');
        }
      }
    });
  }

  // -- Classes ----------------------------------------------------------------

  /// `public class X extends Y`.
  String superOf(String className) {
    final src = _classSources[className];
    if (src == null) return className;
    final m = RegExp('class $className extends (\\w+)').firstMatch(src);
    if (m == null) throw JavaParseError('No superclass for $className');
    return m.group(1)!;
  }

  /// Methods of [className] annotated `@Override`.
  List<String> overridesOf(String className) {
    final src = _classSources[className];
    if (src == null) return const [];
    return [
      for (final m in RegExp(r'@Override\s+(?:public|protected)\s+[\w<>\[\].,? ]+?\s+(\w+)\(')
          .allMatches(src))
        m.group(1)!,
    ];
  }

  /// The source of a method body in [className].
  String methodBody(String className, String method) {
    final src = _classSources[className]!;
    final m = RegExp('\\s$method\\(').firstMatch(src);
    if (m == null) throw JavaParseError('$className.$method not found');
    final open = src.indexOf('{', m.end);
    return src.substring(open + 1, indexOfClosing(src, open));
  }

  bool isModClass(String name) => _classSources.containsKey(name);

  /// `Lonsdaleite_Mace.createAttributes()`: a static builder chain.
  List<Json> staticAttributes(String className, String method) {
    final body = methodBody(className, method);
    final m = RegExp(r'return\s+(.*?);\s*$', dotAll: true).firstMatch(body.trim());
    if (m == null) throw JavaParseError('$className.$method has no return');
    final chain = parseCallChain(m.group(1)!);
    if (chain.root != 'ItemAttributeModifiers') {
      throw JavaParseError('Unsupported attribute source ${chain.root}');
    }
    final out = <Json>[];
    for (final call in chain.calls) {
      if (call.name == 'builder' || call.name == 'build') continue;
      if (call.name != 'add' || call.args.length != 3) {
        throw JavaParseError('Unsupported attribute builder call $call');
      }
      final modifier = RegExp(r'^new AttributeModifier\((.*)\)$', dotAll: true)
          .firstMatch(call.args[1].trim());
      if (modifier == null) throw JavaParseError('Expected new AttributeModifier(...)');
      final parts = splitTopLevel(modifier.group(1)!);
      out.add(attributeModifier(
        attribute: 'minecraft:${call.args[0].split('.').last.toLowerCase()}',
        id: _attributeId(parts[0]),
        amount: parseJavaNumber(parts[1]).value,
        operation: parts[2].split('.').last.toLowerCase(),
        slot: call.args[2].split('.').last.toLowerCase(),
      ));
    }
    return out;
  }

  static String _attributeId(String constant) => switch (constant.trim()) {
    'BASE_ATTACK_DAMAGE_ID' => 'minecraft:base_attack_damage',
    'BASE_ATTACK_SPEED_ID' => 'minecraft:base_attack_speed',
    final other => throw JavaParseError('Unknown attribute id constant $other'),
  };

  // -- Registrations ----------------------------------------------------------

  late final String _entrySource = _read(_entry);

  /// The items in registration order.
  late final List<ItemRegistration> items = _parseItems();

  List<ItemRegistration> _parseItems() {
    final src = _entrySource;
    final out = <ItemRegistration>[];
    final pattern = RegExp(
      r'DeferredItem<[^>]+>\s+(\w+)\s*=\s*ITEMS\.(registerItem|registerSimpleItem)\(',
    );
    for (final m in pattern.allMatches(src)) {
      final open = m.end - 1;
      final args = splitTopLevel(src.substring(open + 1, indexOfClosing(src, open)));
      final name = parseJavaString(args.first);
      final id = '$modId:$name';
      if (m.group(2) == 'registerSimpleItem') {
        out.add(_item(m.group(1)!, id, 'Item', const [], ItemProperties(id), '', null));
        continue;
      }
      out.add(_registeredItem(m.group(1)!, id, args[1]));
    }
    return out;
  }

  ItemRegistration _registeredItem(String field, String id, String lambda) {
    final arrow = lambda.indexOf('->');
    if (arrow < 0 || lambda.substring(0, arrow).trim() != 'p') {
      throw JavaParseError('Expected `p -> ...` for $id, got `$lambda`');
    }
    final body = lambda.substring(arrow + 2).trim();
    final ctor = RegExp(r'^new (\w+)\(').firstMatch(body);
    if (ctor == null) throw JavaParseError('Expected `new X(...)` for $id');
    final open = ctor.end - 1;
    final callArgs = splitTopLevel(body.substring(open + 1, indexOfClosing(body, open)));
    final className = ctor.group(1)!;

    final JavaChain chain = _propertiesChain(className, callArgs);
    final properties = ItemProperties(id);
    final context = _ItemContext(this);
    for (final call in chain.calls) {
      context.apply(properties, call);
    }
    return _item(
      field,
      id,
      className,
      [for (final c in chain.calls) c.toString()],
      properties,
      lambda,
      context,
    );
  }

  ItemRegistration _item(
    String field,
    String id,
    String className,
    List<String> calls,
    ItemProperties properties,
    String source,
    _ItemContext? context,
  ) => ItemRegistration(
    field: field,
    id: id,
    javaClass: className,
    javaSuper: superOf(className) == className ? 'Item' : superOf(className),
    overrides: overridesOf(className),
    builderCalls: calls,
    components: properties.components,
    source: source,
    toolMaterial: context?.toolMaterial,
    armorMaterial: context?.armorMaterial,
    armorType: context?.armorType,
  );

  /// The `Item.Properties` chain an instantiation ends up with: the call
  /// site's `p...` chain, continued by what the class' constructor does with
  /// it before `super(...)`.
  JavaChain _propertiesChain(String className, List<String> callArgs) {
    JavaChain fromPRoot(String text) {
      final chain = parseCallChain(text);
      if (chain.root != 'p') throw JavaParseError('Expected a `p` chain, got `$text`');
      return chain;
    }

    final src = _classSources[className];
    if (src == null) {
      // A vanilla class: its only argument is the properties.
      final propsArg = callArgs.where((a) => RegExp(r'^p(\.|$)').hasMatch(a)).toList();
      if (propsArg.length != 1) throw JavaParseError('No properties for new $className');
      return fromPRoot(propsArg.single);
    }

    final ctor = RegExp('public $className\\(([^)]*)\\)\\s*\\{').firstMatch(src);
    if (ctor == null) throw JavaParseError('No constructor in $className');
    final params = splitTopLevel(ctor.group(1)!);
    if (params.length != callArgs.length) {
      throw JavaParseError('$className takes ${params.length} arguments, got ${callArgs.length}');
    }
    final names = [for (final p in params) p.split(RegExp(r'\s+')).last];
    final propsIndex = params.indexWhere((p) => p.contains('Item.Properties'));
    if (propsIndex < 0) throw JavaParseError('$className has no Item.Properties parameter');
    final propsName = names[propsIndex];
    final base = fromPRoot(callArgs[propsIndex]);

    final body = src.substring(ctor.end - 1);
    final superCall = RegExp(r'super\(').firstMatch(body);
    if (superCall == null) throw JavaParseError('No super call in $className');
    final superOpen = superCall.end - 1;
    final superArgs = splitTopLevel(body.substring(superOpen + 1, indexOfClosing(body, superOpen)));
    final using = superArgs.where((a) => RegExp('^$propsName(\\.|\$)').hasMatch(a)).toList();
    if (using.length != 1) throw JavaParseError('$className passes properties ambiguously');
    final extra = parseCallChain(using.single);

    String substitute(String arg) {
      final index = names.indexOf(arg.trim());
      return index < 0 ? arg : callArgs[index];
    }

    return JavaChain('p', [
      ...base.calls,
      for (final call in extra.calls) JavaCall(call.name, [for (final a in call.args) substitute(a)]),
    ]);
  }

  /// The block registration.
  late final BlockRegistration block = _parseBlock();

  BlockRegistration _parseBlock() {
    final src = _entrySource;
    final m = RegExp(r'DeferredBlock<[^>]+>\s+(\w+)\s*=\s*BLOCKS\.registerBlock\(').firstMatch(src);
    if (m == null) throw JavaParseError('No block registration');
    final open = m.end - 1;
    final args = splitTopLevel(src.substring(open + 1, indexOfClosing(src, open)));
    if (args.length != 3) throw JavaParseError('registerBlock takes 3 arguments');
    final className = args[1].replaceAll('::new', '');
    final lambda = args[2];
    final arrow = lambda.indexOf('->');
    final chain = parseCallChain(lambda.substring(arrow + 2));
    if (chain.root != 'p') throw JavaParseError('Expected a `p` chain for the block');

    var destroy = 0.0, resistance = 0.0, canOcclude = true, needsTool = false;
    var sound = 'stone', light = 0, suffocating = true, viewBlocking = true;
    for (final call in chain.calls) {
      switch (call.name) {
        case 'strength':
          destroy = parseJavaNumber(call.args[0]).value;
          resistance = parseJavaNumber(call.args[1]).value;
        case 'sound':
          sound = call.args.single.split('.').last.toLowerCase();
        case 'noOcclusion':
          canOcclude = false;
        case 'requiresCorrectToolForDrops':
          needsTool = true;
        case 'lightLevel':
          light = _constantLambda(call.args.single, int.parse);
        case 'isSuffocating':
          suffocating = _constantLambda(call.args.single, _parseBool);
        case 'isViewBlocking':
          viewBlocking = _constantLambda(call.args.single, _parseBool);
        default:
          throw JavaParseError('Unsupported block builder call $call');
      }
    }

    final classSrc = _classSources[className]!;
    final fieldNames = {
      for (final f in RegExp(r'BooleanProperty (\w+)\s*=\s*BlockStateProperties\.(\w+);')
          .allMatches(classSrc))
        f.group(1)!: f.group(2)!.toLowerCase(),
    };
    final addMatch = RegExp(r'builder\.add\(([^)]*)\)').firstMatch(classSrc);
    if (addMatch == null) throw JavaParseError('No state definition in $className');
    final properties = [
      for (final p in splitTopLevel(addMatch.group(1)!)) fieldNames[p] ?? (throw JavaParseError('Unknown property $p')),
    ];
    final defaults = {
      for (final d in RegExp(r'\.setValue\((\w+),\s*(true|false)\)').allMatches(
        classSrc.substring(0, classSrc.indexOf('createBlockStateDefinition')),
      ))
        fieldNames[d.group(1)!]!: d.group(2) == 'true',
    };
    if (defaults.length != properties.length) {
      throw JavaParseError('Not every block state property has a default');
    }

    return BlockRegistration(
      field: m.group(1)!,
      id: '$modId:${parseJavaString(args[0])}',
      javaClass: className,
      javaSuper: superOf(className),
      overrides: overridesOf(className),
      builderCalls: [for (final c in chain.calls) c.toString()],
      destroyTime: destroy,
      explosionResistance: resistance,
      soundType: sound,
      canOcclude: canOcclude,
      requiresCorrectToolForDrops: needsTool,
      lightLevel: light,
      isSuffocating: suffocating,
      isViewBlocking: viewBlocking,
      properties: properties,
      defaults: defaults,
    );
  }

  static bool _parseBool(String s) => s == 'true' ? true : s == 'false' ? false : throw JavaParseError('Not a bool: $s');

  /// `state -> 7` or `(state, level, pos) -> false`.
  static T _constantLambda<T>(String lambda, T Function(String) parse) {
    final m = RegExp(r'^(?:\w+|\([\w, ]*\))\s*->\s*(\w+)$').firstMatch(lambda.trim());
    if (m == null) throw JavaParseError('Not a constant lambda: `$lambda`');
    return parse(m.group(1)!);
  }

  // -- Creative tabs ----------------------------------------------------------

  /// Java field to registry id, items then the block item.
  late final Map<String, String> fieldIds = {
    for (final i in items) i.field: i.id,
  };

  late final CreativeTabSpec ownTab = _parseOwnTab();

  CreativeTabSpec _parseOwnTab() {
    final src = _entrySource;
    final m = RegExp(r'TABS\.register\("([^"]+)"').firstMatch(src);
    if (m == null) throw JavaParseError('No creative tab registration');
    final open = src.indexOf('(', m.start);
    final body = src.substring(open, indexOfClosing(src, open));
    final title = RegExp(r'Component\.translatable\("([^"]+)"\)').firstMatch(body)?.group(1);
    final icon = RegExp(r'\.icon\(\(\) -> new ItemStack\((\w+)\.get\(\)\)\)').firstMatch(body)?.group(1);
    if (title == null || icon == null) throw JavaParseError('Unsupported creative tab builder');
    return CreativeTabSpec(
      '$modId:${m.group(1)}',
      title,
      _itemId(icon),
      [
        for (final a in RegExp(r'entries\.accept\((\w+)\.get\(\)\)').allMatches(body))
          _itemId(a.group(1)!),
      ],
    );
  }

  String _itemId(String field) =>
      fieldIds[field] ?? (throw JavaParseError('Unknown item field $field'));

  late final List<TabInsertion> tabInsertions = _parseInsertions();

  List<TabInsertion> _parseInsertions() {
    final src = _entrySource;
    final start = src.indexOf('onBuildCreativeTabs(');
    final methodOpen = src.indexOf('{', src.indexOf(')', start));
    final method = src.substring(methodOpen + 1, indexOfClosing(src, methodOpen));
    final out = <TabInsertion>[];
    for (final tab in RegExp(r'getTabKey\(\) == CreativeModeTabs\.(\w+)\)\s*\{').allMatches(method)) {
      final open = tab.end - 1;
      final body = method.substring(open + 1, indexOfClosing(method, open));
      final tabId = 'minecraft:${tab.group(1)!.toLowerCase()}';

      // Single `event.insertAfter(new ItemStack(A), new ItemStack(B), V)` lines.
      final singles = RegExp(
        r'event\.insertAfter\(new ItemStack\(([\w.]+?)(?:\.get\(\))?\),\s*new ItemStack\((\w+)\.get\(\)\),\s*CreativeModeTab\.TabVisibility\.(\w+)\)',
      );
      // Anchored loops over an array of DeferredItem.
      final loops = RegExp(
        r'ItemStack (\w+) = new ItemStack\(Items\.(\w+)\);\s*for \(DeferredItem<[^>]*> \w+ : new DeferredItem\[\] \{([^}]*)\}\) \{\s*'
        r'ItemStack (\w+) = new ItemStack\(entry\.get\(\)\);\s*event\.insertAfter\((\w+), \4, CreativeModeTab\.TabVisibility\.(\w+)\);\s*\1 = \4;\s*\}',
      );
      final loopMatches = loops.allMatches(body).toList();
      final loopSpans = [for (final l in loopMatches) (l.start, l.end)];
      for (final s in singles.allMatches(body)) {
        if (loopSpans.any((span) => s.start >= span.$1 && s.start < span.$2)) continue;
        final after = s.group(1)!;
        out.add(TabInsertion(
          tabId,
          after.startsWith('Items.') ? _vanillaItem(after) : _itemId(after),
          _itemId(s.group(2)!),
          s.group(3)!.toLowerCase(),
        ));
      }
      for (final l in loopMatches) {
        if (l.group(1) != l.group(5)) throw JavaParseError('Unsupported insertion loop in $tabId');
        var after = 'minecraft:${l.group(2)!.toLowerCase()}';
        for (final field in splitTopLevel(l.group(3)!)) {
          final id = _itemId(field);
          out.add(TabInsertion(tabId, after, id, l.group(6)!.toLowerCase()));
          after = id;
        }
      }
    }
    if (out.isEmpty) throw JavaParseError('No vanilla creative tab insertions found');
    return out;
  }

  static String _vanillaItem(String reference) =>
      'minecraft:${reference.substring('Items.'.length).toLowerCase()}';
}

/// Evaluates the `Item.Properties` builder calls the mod makes.
final class _ItemContext {
  final ModSource source;
  String? toolMaterial;
  String? armorMaterial;
  String? armorType;

  _ItemContext(this.source);

  ModMaterials get _m => source.materials;

  ToolMaterialSpec _tool(String expression, {bool remember = true}) {
    final name = expression.trim().split('.').last;
    final spec = _m.tools[name];
    if (spec == null) throw JavaParseError('Unknown tool material `$expression`');
    if (remember) toolMaterial = name;
    return spec;
  }

  String _tag(String expression) {
    final name = expression.trim().split('.').last;
    return _m.tags[name] ?? (throw JavaParseError('Unknown tag `$expression`'));
  }

  double _n(String text) => parseJavaNumber(text).value;

  void apply(ItemProperties p, JavaCall call) {
    final a = call.args;
    switch (call.name) {
      case 'rarity':
        p.rarity(a.single.split('.').last.toLowerCase());
      case 'durability':
        p.durability(parseJavaNumber(a.single).asInt);
      case 'repairable':
        p.repairable(_tag(a.single));
      case 'enchantable':
        p.enchantable(parseJavaNumber(a.single).asInt);
      case 'attributes':
        p.attributes(_attributes(a.single));
      case 'component':
        p.component(_componentKey(a[0]), _componentValue(a[1]));
      case 'useBlockDescriptionPrefix':
        p.useBlockDescriptionPrefix();
      case 'pickaxe':
        p.pickaxe(_tool(a[0]), _n(a[1]), _n(a[2]));
      case 'axe':
        p.axe(_tool(a[0]), _n(a[1]), _n(a[2]));
      case 'shovel':
        p.shovel(_tool(a[0]), _n(a[1]), _n(a[2]));
      case 'hoe':
        p.hoe(_tool(a[0]), _n(a[1]), _n(a[2]));
      case 'sword':
        p.sword(_tool(a[0]), _n(a[1]), _n(a[2]));
      case 'spear':
        if (a.length != 10) throw JavaParseError('spear takes 10 arguments, got ${a.length}');
        p.spear(
          _tool(a[0]),
          swingSeconds: _n(a[1]),
          damageMultiplier: _n(a[2]),
          delaySeconds: _n(a[3]),
          dismountSeconds: _n(a[4]),
          dismountSpeed: _n(a[5]),
          knockbackSeconds: _n(a[6]),
          knockbackSpeed: _n(a[7]),
          damageSeconds: _n(a[8]),
          damageRelativeSpeed: _n(a[9]),
        );
      case 'humanoidArmor':
        final name = a[0].trim().split('.').last;
        final material = _m.armor[name] ?? (throw JavaParseError('Unknown armor material ${a[0]}'));
        armorMaterial = name;
        armorType = a[1].trim().split('.').last;
        p.humanoidArmor(material, ArmorType.fromJava(armorType!));
      default:
        throw JavaParseError('Unsupported Item.Properties call `$call`');
    }
  }

  static String _componentKey(String expression) {
    final m = RegExp(r'^DataComponents\.(\w+)$').firstMatch(expression.trim());
    if (m == null) throw JavaParseError('Unsupported component key `$expression`');
    return 'minecraft:${m.group(1)!.toLowerCase()}';
  }

  Object? _componentValue(String expression) {
    final e = expression.trim();
    if (e == 'MaceItem.createToolProperties()') return maceToolProperties();
    final weaponMatch = RegExp(r'^new Weapon\((\d+)\)$').firstMatch(e);
    if (weaponMatch != null) return weapon(int.parse(weaponMatch.group(1)!));
    throw JavaParseError('Unsupported component value `$expression`');
  }

  List<Json> _attributes(String expression) {
    final m = RegExp(r'^(\w+)\.(\w+)\(\)$').firstMatch(expression.trim());
    if (m == null || !source.isModClass(m.group(1)!)) {
      throw JavaParseError('Unsupported attribute source `$expression`');
    }
    return source.staticAttributes(m.group(1)!, m.group(2)!);
  }
}

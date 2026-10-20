// The persistence tag of an item stack: Java's `ItemStack.CODEC` shape (`id`, `count`,
// `components?`) with the plugin's own component bytes next to it, and the codec components of a
// Java save preserved verbatim. Pure, so it runs on the Dart VM; the host codecs
// (`ItemCodec`, `StackCodec`, `HostSlotStacks`) are thin adapters over it.
import 'package:create/src/common/stack_tag.dart';
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/core/nbt.dart';
import 'package:test/test.dart';

/// The `components` compound of a Java save, in the codec form Java writes them.
NbtMap javaComponents() => NbtMap()
  ..putString('create:package_address', 'depot 1')
  ..putInt('minecraft:damage', 7)
  ..putList('create:filter_items', [
    (NbtMap()
          ..putString('id', 'minecraft:iron_ingot')
          ..putInt('count', 2))
        .toValue(),
  ]);

/// A package as a Java save holds it.
NbtMap javaTag() => NbtMap()
  ..putString('id', 'create:cardboard_package_12x12')
  ..putInt('count', 3)
  ..putCompound(JavaStackTag.componentsKey, javaComponents());

/// Structural equality of two NBT values (`NbtValue` has no `==`).
bool sameNbt(NbtValue a, NbtValue b) {
  if (a.kind != b.kind) return false;
  if (a.kind == NbtKind.compound) {
    final x = a.asCompound, y = b.asCompound;
    if (x.length != y.length) return false;
    for (final e in x.entries) {
      final other = y[e.key];
      if (other == null || !sameNbt(e.value, other)) return false;
    }
    return true;
  }
  if (a.kind == NbtKind.list) {
    final x = a.value as List<NbtValue>, y = b.value as List<NbtValue>;
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (!sameNbt(x[i], y[i])) return false;
    }
    return true;
  }
  return a.value == b.value;
}

/// The components of a tag, structurally comparable with [javaComponents].
NbtValue componentsOf(NbtValue tag) => NbtMap.of(tag).getCompoundOrNull(JavaStackTag.componentsKey)!.toValue();

/// The plugin's component bytes of a tag as `name:bytes` (records do not compare list fields).
List<String> compsOf(StackTag tag) => [for (final (name, bytes) in tag.comps) '$name:$bytes'];

void main() {
  group('a Java save read and written back', () {
    test('keeps the components of {id, count, components}', () {
      final java = javaTag().toValue();
      final tag = JavaStackTag.read(java);
      expect(tag, isNotNull);
      expect(tag!.id, 'create:cardboard_package_12x12');
      expect(tag.count, 3);
      expect(tag.maxStack, isNull, reason: 'Java does not write Max');
      expect(tag.components, isNotNull);
      expect(sameNbt(tag.components!, javaComponents().toValue()), isTrue);

      final written = JavaStackTag.write(id: tag.id, count: tag.count, comps: tag.comps, components: tag.components);
      final back = NbtMap.of(written);
      expect(back.getString('id'), 'create:cardboard_package_12x12');
      expect(back.getInt('count'), 3);
      expect(sameNbt(componentsOf(written), javaComponents().toValue()), isTrue);

      // Stable through a second trip.
      final again = JavaStackTag.read(written)!;
      final twice = JavaStackTag.write(id: again.id, count: again.count, comps: again.comps, components: again.components);
      expect(sameNbt(componentsOf(twice), javaComponents().toValue()), isTrue);
    });

    test('the client tag keeps them too', () {
      final tag = JavaStackTag.read(javaTag().toValue())!;
      final client = NbtMap.of(JavaStackTag.writeClient(id: tag.id, count: tag.count, components: tag.components));
      expect(client.getString('id'), 'create:cardboard_package_12x12');
      expect(client.getInt('count'), 3);
      expect(sameNbt(componentsOf(client.toValue()), javaComponents().toValue()), isTrue);
    });

    test('an empty or air tag holds no stack', () {
      expect(JavaStackTag.read(null), isNull);
      expect(JavaStackTag.read(NbtMap().toValue()), isNull);
      expect(JavaStackTag.read((NbtMap()..putString('id', 'minecraft:stone')..putInt('count', 0)).toValue()), isNull);
    });
  });

  group('a tag the plugin writes', () {
    test('is what ItemStack.CODEC reads: id and count', () {
      final written = JavaStackTag.write(
        id: 'create:brass_funnel',
        count: 2,
        comps: [('minecraft:damage', [5])],
        maxStack: 64,
        damageable: false,
      );
      final tag = NbtMap.of(written);
      expect(tag.getString('id'), 'create:brass_funnel');
      expect(tag.getInt('count'), 2);
      expect(tag.getInt('Max'), 64);
      expect(tag.getBool('Dmg'), isFalse);
      // The plugin's bytes are not a codec value: no `components`, so Java reads the plain item
      // instead of failing on a component it cannot decode.
      expect(tag.getCompoundOrNull(JavaStackTag.componentsKey), isNull);
      expect(tag.getList(JavaStackTag.compsKey), hasLength(1));
    });

    test('round-trips its own component bytes, Max and Dmg', () {
      final comps = [('minecraft:damage', [9]), ('${customComponentPrefix}create:filter_items', [1, 2, 3])];
      final written = JavaStackTag.write(id: 'minecraft:diamond_sword', count: 1, comps: comps, maxStack: 1, damageable: true);
      final back = JavaStackTag.read(written)!;
      expect(back.id, 'minecraft:diamond_sword');
      expect(back.count, 1);
      expect(back.maxStack, 1);
      expect(back.damageable, isTrue);
      expect(compsOf(back), ['${customComponentPrefix}create:filter_items:[1, 2, 3]', 'minecraft:damage:[9]']);
      expect(back.components, isNull);
    });

    test('still reads the older plugin form (Key/Count)', () {
      final old = NbtMap()
        ..putString('Key', 'minecraft:iron_ingot')
        ..putInt('Count', 4)
        ..putInt('Max', 64)
        ..putBool('Dmg', false)
        ..putList(JavaStackTag.compsKey, [
          (NbtMap()
                ..putString('N', 'minecraft:damage')
                ..map['V'] = NbtValue.byteArray([3]))
              .toValue(),
        ]);
      final tag = JavaStackTag.read(old.toValue())!;
      expect(tag.id, 'minecraft:iron_ingot');
      expect(tag.count, 4);
      expect(tag.maxStack, 64);
      expect(tag.damageable, isFalse);
      expect(compsOf(tag), ['minecraft:damage:[3]']);
    });
  });

  group('an ItemValue from a Java save', () {
    test('keeps the codec form and reads the package address from it', () {
      final tag = JavaStackTag.read(javaTag().toValue())!;
      final box = ItemValue(tag.id, tag.count, rawComponents: tag.components);
      expect(box.rawComponents, isNotNull);
      expect(packageAddressOf(box), 'depot 1');
      expect(box.withCount(2).rawComponents, isNotNull, reason: 'splitting keeps the codec form');
    });

    test('drops the codec value of a component the plugin changes, and only that one', () {
      final tag = JavaStackTag.read(javaTag().toValue())!;
      final box = ItemValue(tag.id, tag.count, rawComponents: tag.components);
      final changed = box.withComponent(packageAddressComponent, encodePackageAddress('depot 2'));
      expect(packageAddressOf(changed), 'depot 2');
      final raw = changed.rawComponents!.asCompound;
      expect(raw.containsKey('create:package_address'), isFalse);
      expect(raw.containsKey('minecraft:damage'), isTrue);
      expect(raw.containsKey('create:filter_items'), isTrue);
    });
  });
}
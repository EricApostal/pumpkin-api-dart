// Entity type keys: the host reports a vanilla entity's type as a kebab-case wire name
// (`chest-minecart`), while every contraption check compares `namespace:path` keys
// (`minecraft:chest_minecart`). A missed mapping makes `ContraptionLevel.minecartsAt` return
// nothing, so the cart assembler never sees the cart it should assemble.
import 'package:create/src/contraptions/core/entity_type_keys.dart';
import 'package:test/test.dart';

void main() {
  group('entityTypeKey', () {
    test('maps a vanilla wire name to its namespaced snake_case key', () {
      expect(entityTypeKey(wireName: 'minecart'), 'minecraft:minecart');
      expect(entityTypeKey(wireName: 'chest-minecart'), 'minecraft:chest_minecart');
      expect(entityTypeKey(wireName: 'furnace-minecart'), 'minecraft:furnace_minecart');
      expect(entityTypeKey(wireName: 'player'), 'minecraft:player');
    });

    test('keeps the registered key of a plugin type', () {
      expect(
        entityTypeKey(pluginKey: 'create:stationary_contraption', wireName: 'stationary-contraption'),
        'create:stationary_contraption',
      );
    });
  });

  group('hostTypeKey', () {
    test('a plugin entity needs no wire name: get-type is null for it', () {
      // The host reports a plugin type only through `get-plugin-type-key`; `Entity.getType()`
      // returns `null` for it (the type is registered at runtime, the WIT enum has no variant).
      expect(hostTypeKey(pluginKey: 'create:contraption', wireName: null), 'create:contraption');
      expect(hostTypeKey(pluginKey: 'create:seat', wireName: null), 'create:seat');
    });

    test('a vanilla entity maps its wire name, a host that reports neither yields null', () {
      expect(hostTypeKey(wireName: 'chest-minecart'), 'minecraft:chest_minecart');
      expect(hostTypeKey(pluginKey: null, wireName: null), isNull);
    });
  });

  group('reportedEntityTypeKey', () {
    test('a plugin key the host prefixed with minecraft: is unwrapped', () {
      // `crates/pumpkin-core/src/world/mod.rs:1728`: `format!("minecraft:{}", resource_name)`.
      expect(
        reportedEntityTypeKey('minecraft:create:stationary_contraption'),
        'create:stationary_contraption',
      );
      expect(reportedEntityTypeKey('minecraft:create:contraption'), 'create:contraption');
      expect(reportedEntityTypeKey('minecraft:create:gantry_contraption'), 'create:gantry_contraption');
    });

    test('a vanilla type keeps its minecraft: namespace, an unprefixed key is unchanged', () {
      expect(reportedEntityTypeKey('minecraft:minecart'), 'minecraft:minecart');
      expect(reportedEntityTypeKey('minecraft:player'), 'minecraft:player');
      expect(reportedEntityTypeKey('create:contraption'), 'create:contraption');
    });
  });

  group('isMinecartEntityType', () {
    test('every minecart variant is one, with its namespaced key', () {
      for (final key in [
        'minecraft:minecart',
        'minecraft:chest_minecart',
        'minecraft:furnace_minecart',
        'minecraft:hopper_minecart',
        'minecraft:command_block_minecart',
      ]) {
        expect(isMinecartEntityType(key), isTrue, reason: key);
      }
    });

    test('the raw wire name of a minecart is not a key', () {
      // What `Entity.getType().wireName` gives: the bug this mapping prevents.
      expect(isMinecartEntityType('minecart'), isFalse);
      expect(isMinecartEntityType('chest-minecart'), isFalse);
    });

    test('a boat, a player and an unknown key are not minecarts', () {
      expect(isMinecartEntityType('minecraft:oak_boat'), isFalse);
      expect(isMinecartEntityType('minecraft:player'), isFalse);
      expect(isMinecartEntityType('create:contraption'), isFalse);
    });
  });
}

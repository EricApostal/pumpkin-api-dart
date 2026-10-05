// The binding-free parts of the play-phase helpers.
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('glidingFlightAttributeId', () {
    final vanillaCount = VanillaRegistries.require('minecraft:attribute').length;

    test('without a synced attribute registry it follows the vanilla ids', () {
      final spec = NeoForgeServerSpec.vanillaPlus(
        additions: {'minecraft:item': ['x:y']},
      );
      // NeoForge's attributes come after the vanilla ones: swim_speed,
      // creative_flight, gliding_flight.
      expect(glidingFlightAttributeId(spec), vanillaCount + 2);
    });

    test('with a synced attribute registry it is the position in it', () {
      final spec = NeoForgeServerSpec.vanillaPlus(
        additions: {
          'minecraft:attribute': [...neoForgeOwnAttributes, 'x:extra'],
        },
      );
      expect(glidingFlightAttributeId(spec), vanillaCount + 2);
      final shifted = NeoForgeServerSpec.vanillaPlus(
        additions: {
          'minecraft:attribute': ['x:first', ...neoForgeOwnAttributes],
        },
      );
      expect(glidingFlightAttributeId(shifted), vanillaCount + 3);
    });

    test('a synced registry without the attribute gives null', () {
      final spec = NeoForgeServerSpec.vanillaPlus(
        additions: {'minecraft:attribute': ['x:extra']},
      );
      expect(glidingFlightAttributeId(spec), isNull);
    });

    test('an explicit id wins', () {
      final spec = NeoForgeServerSpec.vanillaPlus(additions: {});
      expect(
        glidingFlightAttributeId(
          spec,
          const GlidingFlightOptions(attributeId: 7),
        ),
        7,
      );
    });
  });

  test('an empty recipe content is two zero VarInts', () {
    expect(emptyRecipeContent, [0, 0]);
    expect(recipeContentChannel, 'neoforge:recipe_content');
  });

  test('the configuration ping packet', () {
    expect(configurationPingPacketId, 5);
    expect(configurationPingBody.length, 4);
  });
}

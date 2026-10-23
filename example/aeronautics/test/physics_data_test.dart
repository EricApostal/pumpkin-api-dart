// Aeronautics' physics data, and the material it gives levitite.
//
// The end-to-end behaviour (a levitite assembly lifts instead of falling) needs a
// live server: the sub-level is ticked by the solver component. What this file
// pins is the half that was missing and that can be checked on the VM -- that the
// four files of `data/aeronautics/**` reach the tables the model reads, with the
// Java values, so `aeronautics:levitite` is not `null` when a block names it.
//
// The tables themselves are Sable's (`package:sable`), and its types are pure, so
// the decoding runs here exactly as the owning component runs it.
import 'package:aeronautics/src/data/aeronautics_physics_data.dart';
import 'package:sable/src/sublevel/physics/floating_block_material.dart';
import 'package:sable/src/sublevel/physics/physics_block_properties.dart';
import 'package:test/test.dart';

void main() {
  final data = AeronauticsPhysicsData.fromEmbeddedPack();

  group('the embedded pack', () {
    test('carries both floating materials', () {
      expect(data.materials.keys, containsAll(['aeronautics:levitite', 'aeronautics:simple_drag']));
    });

    test('carries both physics block property definitions', () {
      final selectors = [
        for (final json in data.properties) '${json['selector']}',
      ];
      expect(selectors, containsAll(['#aeronautics:levitite', '#aeronautics:airtight']));
    });

    test('a registry id is derived from the file path, as FileToIdConverter does', () {
      expect(
        AeronauticsPhysicsData.registryIdOf(
          'data/aeronautics/floating_materials/levitite.json',
          'floating_materials',
        ),
        'aeronautics:levitite',
      );
      expect(AeronauticsPhysicsData.registryIdOf('data/x/y/z.json', 'floating_materials'), isNull);
    });
  });

  group('aeronautics:levitite', () {
    late FloatingBlockMaterial material;

    setUp(() {
      material = FloatingBlockMaterial.fromJson(data.materials['aeronautics:levitite']!);
    });

    test('has the Java lift and the Java frictions', () {
      // `data/aeronautics/floating_materials/levitite.json`, verbatim.
      expect(material.liftStrength, 10.0);
      expect(material.preventSelfLift, isTrue);
      expect(material.scaleWithGravity, isTrue);
      expect(material.scaleWithPressure, isFalse);
      expect(material.transitionSpeed, 3.0);
      expect(material.slowVerticalFriction, 2.0);
      expect(material.fastVerticalFriction, 0.1);
      expect(material.slowHorizontalFriction, 1.5);
      expect(material.fastHorizontalFriction, 0.05);
    });

    test('lifts ten times as hard as the strongest Sable material', () {
      // `data/sable/floating_materials/end_stone.json` is lift 2.
      expect(material.liftStrength, greaterThan(2.0));
    });
  });

  group('aeronautics:simple_drag', () {
    test('scales with pressure and has no lift of its own', () {
      final material = FloatingBlockMaterial.fromJson(data.materials['aeronautics:simple_drag']!);
      expect(material.scaleWithPressure, isTrue);
      expect(material.liftStrength, 0.0);
      expect(material.fastVerticalFriction, 1.0);
      expect(material.fastHorizontalFriction, 1.0);
    });
  });

  group('the definitions, applied to a block of the tag', () {
    late PhysicsBlockPropertiesTable table;

    setUp(() {
      table = PhysicsBlockPropertiesTable()
        ..blockInTag = (blockId, tagId) =>
            (tagId == 'aeronautics:levitite' &&
                (blockId == 'aeronautics:levitite' ||
                    blockId == 'aeronautics:pearlescent_levitite')) ||
            (tagId == 'aeronautics:airtight' && blockId == 'aeronautics:white_envelope');
      for (final json in data.properties) {
        final definition = PhysicsBlockPropertiesDefinition.tryFromJson(json);
        if (definition != null) table.addDefinition(definition);
      }
    });

    test('a levitite block names the levitite material', () {
      expect(table.floatingMaterialOf('aeronautics:levitite'), 'aeronautics:levitite');
      expect(
        table.floatingMaterialOf('aeronautics:pearlescent_levitite'),
        'aeronautics:levitite',
      );
    });

    test('the material it names is in the table, so it resolves instead of null', () {
      final id = table.floatingMaterialOf('aeronautics:levitite');
      expect(id, isNotNull);
      final material = FloatingBlockMaterial.fromJson(data.materials[id]!);
      expect(material.liftStrength, 10.0);
    });

    test('an airtight block names the drag material with the 0.33 scale', () {
      expect(table.floatingMaterialOf('aeronautics:white_envelope'), 'aeronautics:simple_drag');
      expect(table.floatingScaleOf('aeronautics:white_envelope'), 0.33);
    });

    test('a block outside both tags is unaffected', () {
      expect(table.floatingMaterialOf('minecraft:stone'), isNull);
      expect(table.floatingScaleOf('minecraft:stone'), 1.0);
    });
  });
}

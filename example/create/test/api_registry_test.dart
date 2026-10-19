import 'package:create/src/api/block_state.dart';
import 'package:create/src/api/registry.dart';
import 'package:create/src/api/schematic/requirements.dart';
import 'package:create/src/schematics/item_requirement.dart';
import 'package:test/test.dart';

void main() {
  group('SimpleRegistry', () {
    test('direct registrations win and duplicates throw', () {
      final registry = SimpleRegistry<String>();
      registry.register('create:a', 'A');
      expect(registry.lookup('create:a'), 'A');
      expect(registry.lookup('create:b'), isNull);
      expect(() => registry.register('create:a', 'B'), throwsArgumentError);
      expect(registry.lookupState(const BState('create:a')), 'A');
      expect(registry.contains('create:a'), isTrue);
      expect(registry.keys, ['create:a']);
      expect(registry.direct('create:a'), 'A');
    });

    test('providers are queried newest first and cached until invalidated', () {
      final registry = SimpleRegistry<String>();
      var calls = 0;
      registry.registerProvider(
        SimpleRegistryProvider<String>((key) {
          calls++;
          return key == 'create:x' ? 'first' : null;
        }),
      );
      registry.registerProvider(
        SimpleRegistryProvider<String>((key) {
          calls++;
          return key == 'create:x' ? 'second' : null;
        }),
      );
      expect(registry.lookup('create:x'), 'second');
      final afterFirst = calls;
      expect(registry.lookup('create:x'), 'second');
      expect(calls, afterFirst, reason: 'the provider value is cached');
      registry.invalidate();
      expect(registry.lookup('create:x'), 'second');
      expect(calls, greaterThan(afterFirst));
      expect(
        () => registry.registerProvider(SimpleRegistryProvider((_) => null)),
        returnsNormally,
      );
    });

    test('a provider is only registered once', () {
      final registry = SimpleRegistry<String>();
      final provider = SimpleRegistryProvider<String>((_) => null);
      registry.registerProvider(provider);
      expect(() => registry.registerProvider(provider), throwsArgumentError);
    });

    test('direct values win over providers, tags are providers', () {
      final registry = SimpleRegistry<String>();
      registry.register('create:x', 'direct');
      registry.registerProvider(
        SimpleRegistryProvider<String>.forTag(
          'create:tag',
          'tagged',
          isInTag: (key, tag) => key == 'create:x' && tag == 'create:tag',
        ),
      );
      expect(registry.lookup('create:x'), 'direct');
      expect(registry.lookup('create:y'), isNull);
    });

    test('MultiSimpleRegistry collects every value', () {
      final registry = MultiSimpleRegistry<String>();
      registry.add('create:x', 'a');
      registry.add('create:x', 'b');
      registry.addProvider(
        SimpleRegistryProvider((key) => key == 'create:x' ? 'p' : null),
      );
      expect(registry.lookup('create:x'), ['a', 'b', 'p']);
      expect(registry.lookup('create:y'), isEmpty);
      registry.register('create:z', ['z']);
      expect(registry.lookup('create:z'), ['z']);
      expect(() => registry.register('create:z', []), throwsArgumentError);
    });

    test('SimpleRegistryAccess adds direct values and tags', () {
      final registry = SimpleRegistry<String>();
      final access = SimpleRegistryAccess.of(
        registry,
        isInTag: (key, tag) => key == 'create:b' && tag == 'create:tag',
      );
      access.add('create:a', 'A');
      access.addTag('create:tag', 'T');
      expect(registry.lookup('create:a'), 'A');
      expect(registry.lookup('create:b'), 'T');
    });
  });

  group('CreateRegistries', () {
    test('the registry ids', () {
      expect(
        CreateRegistries.armInteractionPointType,
        'create:arm_interaction_point_type',
      );
      expect(
        CreateRegistries.potatoProjectileType,
        'create:potato_projectile/type',
      );
      expect(CreateRegistries.all, hasLength(13));
      expect(CreateRegistries.all, contains(CreateRegistries.displayTarget));
    });

    test('the manifest entries', () {
      expect(
        CreateBuiltInRegistries.entriesOf(
          CreateRegistries.armInteractionPointType,
        ),
        contains('create:basin'),
      );
      expect(
        CreateBuiltInRegistries.isSynced(CreateRegistries.displaySource),
        isTrue,
      );
      // `potato_projectile/type` is a datapack registry, so it is not synced.
      expect(
        CreateBuiltInRegistries.isSynced(CreateRegistries.potatoProjectileType),
        isFalse,
      );
      expect(
        CreateBuiltInRegistries.contains(
          CreateRegistries.mountedItemStorageType,
          'create:chest',
        ),
        isTrue,
      );
      expect(CreateBuiltInRegistries.definitionOf('create:nope'), isNull);
    });
  });

  group('SchematicRequirementRegistries', () {
    test('registers into the module registries', () {
      final requirements = SchematicRequirements();
      final registries = SchematicRequirementRegistries.of(requirements);
      registries.registerBlock(
        'create:x',
        (state, nbt) => ItemRequirement.none,
      );
      registries.registerBlockEntity(
        'create:be',
        (state, nbt) => ItemRequirement.none,
      );
      registries.registerEntity('minecraft:pig', (nbt) => ItemRequirement.none);
      expect(requirements.blocks, contains('create:x'));
      expect(requirements.blockEntities, contains('create:be'));
      expect(requirements.entities, contains('minecraft:pig'));
    });
  });
}

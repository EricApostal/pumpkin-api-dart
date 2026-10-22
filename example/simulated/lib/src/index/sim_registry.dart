// Everything Simulated registers, in one place.
//
// The entries go into Create's registry (`CreateRegistry`), so the ids line up
// with Create's own content and the same `applyRegistry` writes them to the
// host. Order matters: it is the order of the ids, and it is the Java order --
// `SimJavaOrder` holds it and `register` pins it with `useOrder`.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.index.*
// ignore_for_file: implementation_imports
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/blocks.dart';
import 'package:create/src/core/ordered_registry.dart';
import 'package:create/src/core/registry.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/sim_sounds.dart';
import '../content/blocks/physics_assembler/physics_assembler_block_entity.dart';
import '../content/blocks/portable_engine/portable_engine_block.dart';
import '../content/blocks/portable_engine/portable_engine_block_entity.dart';
import '../content/blocks/spring/spring_block_entity.dart';
import '../content/blocks/steering_wheel/steering_wheel_block_entity.dart';
import '../content/blocks/swivel_bearing/swivel_bearing_block_entity.dart';
import '../content/blocks/throttle_lever/throttle_lever_block_entity.dart';
import '../content/blocks/torsion_spring/torsion_spring_block_entity.dart';
import '../content/entities/honey_glue/honey_glue_entity.dart';
import 'sim_blocks.dart';
import 'sim_items.dart';
import 'sim_java_order.dart';

/// The registration of the mod.
abstract final class SimRegistry {
  /// Adds the items, blocks, block entity types, entity types and sounds to
  /// [registry].
  ///
  /// [lookup] resolves a block entity by world and position (the plugin passes
  /// the store's `typed`).
  static void register(
    CreateRegistry registry, {
    required T? Function<T>(String worldId, (int, int, int) pos) lookup,
  }) {
    // Items first: a block item needs its item, and the block links to it.
    for (final item in simItems()) {
      registry.item(item);
    }

    // The content this port builds has to be the table the ids are pinned
    // against. `pumpkin_api` is wasm-only, so no VM test can build these; the
    // check runs on the real path instead, and a mismatch would otherwise shift
    // every id after it.
    final blocks = simBlocks(lookup: lookup);
    _checkKeys('blocks', [for (final block in blocks) block.key], SimPorted.blocks);
    for (final block in blocks) {
      _checkProperties(block);
      registry.block(block);
    }

    // The block entity types, in the Java field order (`SimJavaOrder`).
    _blockEntityType(registry, TorsionSpringBlockEntity.type, const [SimBlockKeys.torsionSpring],
        (worldId, pos) => TorsionSpringBlockEntity(worldId, pos));
    _blockEntityType(registry, PhysicsAssemblerBlockEntity.type, const [SimBlockKeys.physicsAssembler],
        (worldId, pos) => PhysicsAssemblerBlockEntity(worldId, pos));
    // `SimBlockEntityTypes.PORTABLE_ENGINE` (`SimBlockEntityTypes.java:114`):
    // one type for all sixteen engines (`PortableEngineBlock.getBlockEntityType`).
    _blockEntityType(
        registry,
        PortableEngineBlockEntity.type,
        [for (final colour in SimBlockKeys.engineColours) portableEngineKey(colour)],
        (worldId, pos) => PortableEngineBlockEntity(worldId, pos));
    _blockEntityType(registry, SwivelBearingBlockEntity.type, const [SimBlockKeys.swivelBearing],
        (worldId, pos) => SwivelBearingBlockEntity(worldId, pos));
    _blockEntityType(registry, SteeringWheelBlockEntity.type, const [SimBlockKeys.steeringWheel],
        (worldId, pos) => SteeringWheelBlockEntity(worldId, pos));
    _blockEntityType(registry, SpringBlockEntity.type, const [SimBlockKeys.spring],
        (worldId, pos) => SpringBlockEntity(worldId, pos));
    _blockEntityType(registry, SwivelBearingPlateBlockEntity.type, const [SimBlockKeys.swivelBearingPlate],
        (worldId, pos) => SwivelBearingPlateBlockEntity(worldId, pos));
    _blockEntityType(registry, ThrottleLeverBlockEntity.type, const [SimBlockKeys.throttleLever],
        (worldId, pos) => ThrottleLeverBlockEntity(worldId, pos));
    _checkKeys('block entity types', registry.blockEntityTypes.keys, SimPorted.blockEntityTypes);
    _checkKeys('items', registry.items.keys, SimPorted.items);

    registry.entityType(honeyGlueEntityType);

    for (final sound in SimSoundEvents.all) {
      registry.sound(SoundSpec(sound.key));
    }

    registry.tag(TagKind.block, 'simulated:non_movable', const [
      SimBlockKeys.swivelBearing,
      SimBlockKeys.swivelBearingPlate,
    ]);
    registry.tag(TagKind.block, 'simulated:symmetric_sails', [
      for (final colour in SimBlockKeys.sailColours) SimBlockKeys.sail(colour),
    ]);
    registry.tag(TagKind.block, 'simulated:super_light', const [
      SimBlockKeys.swivelBearingPlate,
    ]);

    // -- Id order ----------------------------------------------------------------
    // NeoForge numbers registry entries by position, so the ids have to be the
    // Java registration order, not the order the content happens to be declared
    // in here. `SimJavaOrder` is that order, entry by entry.
    registry.useOrder(RegistryKind.items, SimJavaOrder.items);
    registry.useOrder(RegistryKind.blocks, SimJavaOrder.blocks);
    registry.useOrder(RegistryKind.blockEntityTypes, SimJavaOrder.blockEntityTypes);
  }

  /// What the Java order asked for and the port did not register, per registry.
  ///
  /// Empty for a fully ported registry; the plugin logs it, and
  /// `registry_order_test.dart` pins the exact set, so a block that lands in the
  /// wrong place (or goes missing) fails loudly instead of shifting ids.
  static Map<RegistryKind, OrderReport> reports(CreateRegistry registry) => {
    RegistryKind.items: registry.reportOf(RegistryKind.items),
    RegistryKind.blocks: registry.reportOf(RegistryKind.blocks),
    RegistryKind.blockEntityTypes: registry.reportOf(RegistryKind.blockEntityTypes),
  };

  static void _blockEntityType(
    CreateRegistry registry,
    String key,
    List<String> validBlocks,
    CreateBlockEntity Function(String worldId, BlockPos pos) create,
  ) => registry.blockEntityType(
    BlockEntityTypeSpec(key: key, validBlocks: validBlocks, create: create),
  );

  /// Throws unless [built] is [table], entry for entry.
  static void _checkKeys(String what, List<String> built, List<String> table) {
    if (built.length == table.length) {
      var index = 0;
      while (index < built.length && built[index] == table[index]) {
        index++;
      }
      if (index == built.length) return;
      throw StateError(
        'The $what this port builds are not the Java order table at index $index: '
        '`${built[index]}` was built, `${table[index]}` is the Java entry '
        '(`sim_java_order.dart`). Fix the table and the builder together: the ids '
        'follow the table, so the entries after this one would take ids the Java '
        'mod gives to other content.',
      );
    }
    throw StateError(
      'This port builds ${built.length} $what, but the Java order table lists ${table.length} '
      '(`sim_java_order.dart`):\n  built: ${built.join(', ')}\n  table: ${table.join(', ')}',
    );
  }

  /// Throws unless the state properties of [block] are the Java's.
  ///
  /// The *names* are compared: a property the Java does not have (or one this
  /// port forgot) means a different number of states, and every state id after
  /// the block moves with it. The values are the Java's too, but `facing` is
  /// Create's property (`CreateProps.facing`), whose value order is stale.
  static void _checkProperties(CreateBlock block) {
    final expected = SimPorted.propertiesOf(block.key);
    final actual = [for (final property in block.definition.properties) property.name];
    if (actual.length == expected.length && actual.every(expected.containsKey)) return;
    throw StateError(
      'The state properties of `${block.key}` are $actual, but the Java has '
      '${expected.keys.toList()} (`sim_java_order.dart`): the states of this block '
      'and the base state id of every block after it would differ from the Java.',
    );
  }
}

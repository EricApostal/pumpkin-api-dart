// Everything Simulated registers, in one place.
//
// The entries go into Create's registry (`CreateRegistry`), so the ids line up
// with Create's own content and the same `applyRegistry` writes them to the
// host. Order matters: it is the order of the ids.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.index.*
// ignore_for_file: implementation_imports
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/registry.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/sim_sounds.dart';
import '../content/blocks/physics_assembler/physics_assembler_block_entity.dart';
import '../content/blocks/spring/spring_block_entity.dart';
import '../content/blocks/steering_wheel/steering_wheel_block_entity.dart';
import '../content/blocks/swivel_bearing/swivel_bearing_block_entity.dart';
import '../content/blocks/throttle_lever/throttle_lever_block_entity.dart';
import '../content/blocks/torsion_spring/torsion_spring_block_entity.dart';
import '../content/entities/honey_glue/honey_glue_entity.dart';
import 'sim_blocks.dart';
import 'sim_items.dart';

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

    for (final block in simBlocks(lookup: lookup)) {
      registry.block(block);
    }

    _blockEntityType(registry, PhysicsAssemblerBlockEntity.type, const [SimBlockKeys.physicsAssembler],
        (worldId, pos) => PhysicsAssemblerBlockEntity(worldId, pos));
    _blockEntityType(registry, SteeringWheelBlockEntity.type, const [SimBlockKeys.steeringWheel],
        (worldId, pos) => SteeringWheelBlockEntity(worldId, pos));
    _blockEntityType(registry, ThrottleLeverBlockEntity.type, const [SimBlockKeys.throttleLever],
        (worldId, pos) => ThrottleLeverBlockEntity(worldId, pos));
    _blockEntityType(registry, SpringBlockEntity.type, const [SimBlockKeys.spring],
        (worldId, pos) => SpringBlockEntity(worldId, pos));
    _blockEntityType(registry, TorsionSpringBlockEntity.type, const [SimBlockKeys.torsionSpring],
        (worldId, pos) => TorsionSpringBlockEntity(worldId, pos));
    _blockEntityType(registry, SwivelBearingBlockEntity.type, const [SimBlockKeys.swivelBearing],
        (worldId, pos) => SwivelBearingBlockEntity(worldId, pos));
    _blockEntityType(registry, SwivelBearingPlateBlockEntity.type, const [SimBlockKeys.swivelBearingPlate],
        (worldId, pos) => SwivelBearingPlateBlockEntity(worldId, pos));

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
  }

  static void _blockEntityType(
    CreateRegistry registry,
    String key,
    List<String> validBlocks,
    CreateBlockEntity Function(String worldId, BlockPos pos) create,
  ) => registry.blockEntityType(
    BlockEntityTypeSpec(key: key, validBlocks: validBlocks, create: create),
  );
}

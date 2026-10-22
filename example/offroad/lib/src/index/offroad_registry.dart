// Everything Offroad registers, in one place, in the order the Java mod
// registers it.
//
// NeoForge numbers registry entries by position, so the *order* is part of the
// contract: a client with the Java mod numbers `offroad:borehead_bearing` the
// same only if the blocks before it are the same. The order lists are the pure
// ones of `index/offroad_ids.dart` (the field order of `OffroadBlocks`,
// `OffroadItems`, `OffroadBlockEntityTypes`, `OffroadEntityTypes` and
// `OffroadDataComponents`), so the same lists the VM tests check are the ones
// pinned here.
//
// Java: `Offroad.init` (`Offroad.java:33-48`).
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../content/blocks/borehead_bearing/borehead_bearing_block.dart';
import '../content/blocks/rock_cutting_wheel/rock_cutting_wheel_block.dart';
import '../content/blocks/wheel_mount/wheel_mount_block.dart';
import '../content/components/tire_like.dart';
import '../content/items/offroad_items.dart';
import '../index/offroad_ids.dart';

/// Registers the mod's content into [registry] and pins every id order.
void registerOffroad(CreateRegistry registry) {
  // -- Blocks -------------------------------------------------------------------
  // `OffroadBlocks.init()` — the block items are registered inside each builder.
  registry.block(buildBoreheadBearingBlock());
  registry.block(buildRockCuttingWheelBlock());
  registry.block(buildWheelMountBlock());

  // -- Items --------------------------------------------------------------------
  for (final item in offroadItems()) {
    registry.item(item);
  }

  // -- Block entity types --------------------------------------------------------
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: OffroadIds.wheelMountBlockEntity,
      validBlocks: const [OffroadIds.wheelMount],
      create: WheelMountBlockEntity.new,
    ),
  );
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: OffroadIds.boreheadBearingBlockEntity,
      validBlocks: const [OffroadIds.boreheadBearing],
      create: BoreheadBearingBlockEntity.new,
    ),
  );
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: OffroadIds.rockCuttingWheelBlockEntity,
      validBlocks: const [OffroadIds.rockCuttingWheel],
      create: RockCuttingWheelBlockEntity.new,
      // `RockCuttingWheelBlockEntity.tick` only animates on the client.
      tickInterval: 0,
    ),
  );

  // -- Entity types ---------------------------------------------------------------
  // `OffroadEntityTypes.BOREHEAD_CONTRAPTION_ENTITY`: `sized(1, 1)`,
  // `clientTrackingRange(20)`, `updateInterval(40)`, `eyeHeight(0)`,
  // `fireImmune()`, `noLootTable()`.
  //
  // The spawn-data channel is what makes the client rebuild the contraption: the Java
  // entity is an `IEntityWithComplexSpawn`, so without it the host sends a bare
  // add-entity packet and the client keeps an entity it cannot render.
  registry.entityType(
    const EntityTypeSpec(
      key: OffroadIds.boreheadContraptionEntity,
      width: 1,
      height: 1,
      eyeHeight: 0,
      fireImmune: true,
      trackingRange: 20,
      updateInterval: 40,
      spawnDataChannel: 'neoforge:advanced_add_entity',
    ),
  );

  // -- Data components ------------------------------------------------------------
  registry.dataComponent(OffroadIds.tireComponent, codec: tireComponentCodec, persistent: true);

  // -- Tags -----------------------------------------------------------------------
  // `OffroadTags.Blocks` (the one that adds generators): `borehead_effective` is
  // `#c:ores`, `borehead_super_effective` is ancient debris.
  registry.tag(TagKind.block, 'offroad:borehead_effective', const ['#c:ores']);
  registry.tag(TagKind.block, 'offroad:borehead_super_effective', const ['minecraft:ancient_debris']);

  // The blocks that set `requiresCorrectTool: true` also need their vanilla
  // mineable tag (`data/minecraft/tags/block/mineable/{pickaxe,axe}.json`).
  registry.tag(TagKind.block, 'minecraft:mineable/pickaxe', const [
    OffroadIds.boreheadBearing,
    OffroadIds.rockCuttingWheel,
    OffroadIds.wheelMount,
  ]);
  registry.tag(TagKind.block, 'minecraft:mineable/axe', const [OffroadIds.wheelMount]);

  // -- Id order -------------------------------------------------------------------
  registry.useOrder(RegistryKind.blocks, OffroadIds.blocks);
  registry.useOrder(RegistryKind.items, OffroadIds.items);
  registry.useOrder(RegistryKind.blockEntityTypes, OffroadIds.blockEntityTypes);
  registry.useOrder(RegistryKind.entityTypes, OffroadIds.entityTypes);
  registry.useOrder(RegistryKind.dataComponents, OffroadIds.dataComponents);
}
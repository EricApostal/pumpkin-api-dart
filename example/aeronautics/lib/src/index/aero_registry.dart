// Everything Aeronautics registers, in one place, in the order the Java mod
// registers it.
//
// NeoForge numbers registry entries by position, so the *order* is part of the
// contract: a client with the Java mods numbers `aeronautics:white_envelope` the
// same only if the blocks before it are the same. [registerAeronautics] therefore
// pins each registry's order with `useOrder` and the lists below are the Java
// field-initialiser order of `index/AeroBlocks`, `index/AeroItems`,
// `index/AeroBlockEntityTypes` and `index/AeroEntityTypes`.
//
// Java: `Aeronautics.init` (`Aeronautics.java:37-57`), which calls
// `AeroBlocks.init()`, `AeroBlockEntityTypes.init()`, `AeroItems.init()`,
// `AeroEntityTypes.init()`, `AeroSoundEvents.init()`, `AeroLiftingGasTypes.init()`,
// `AeroRegistries.init()`, `AeroPacketManager.init()`,
// `AeroLevititeBlendPropagationContexts.init()` and `AeroDataComponents.init()`.
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../content/blocks/hot_air/envelope_blocks.dart';
import '../content/blocks/hot_air/hot_air_burner_block.dart';
import '../content/blocks/hot_air/steam_vent.dart';
import '../content/blocks/levitite/levitite_blocks.dart';
import '../content/blocks/mounted_potato_cannon/mounted_potato_cannon.dart';
import '../content/blocks/propeller/gyroscopic_propeller_bearing_block.dart';
import '../content/blocks/propeller/propeller_bearing_block.dart';
import '../content/blocks/propeller/small_propeller_blocks.dart';
import '../content/components/converter.dart';
import '../content/components/levitating.dart';
import '../content/items/aero_items.dart';
import 'aero_java_order.dart';

/// The dye order every dyed family expands in (`DyeColor.values()`).
const List<String> aeroDyeColors = aeroDyeColorOrder;

/// The block keys in registration order (43) — `AeroJavaOrder.blocks`.
final List<String> aeroBlockOrder = AeroJavaOrder.blocks;

/// The item keys in registration order (46) — `AeroJavaOrder.items`.
final List<String> aeroItemOrder = AeroJavaOrder.items;

/// The block entity type keys in registration order (9) —
/// `AeroJavaOrder.blockEntityTypes`.
const List<String> aeroBlockEntityOrder = AeroJavaOrder.blockEntityTypes;

/// The entity type keys in registration order (2) — `AeroJavaOrder.entityTypes`.
const List<String> aeroEntityTypeOrder = AeroJavaOrder.entityTypes;

/// The data component keys in registration order (2) —
/// `AeroJavaOrder.dataComponents`.
const List<String> aeroDataComponentOrder = AeroJavaOrder.dataComponents;

/// `aeronautics:lifting_gas_type` — `AeroJavaOrder.liftingGasTypeRegistry`.
const String aeroLiftingGasTypeRegistry = AeroJavaOrder.liftingGasTypeRegistry;
const List<String> aeroLiftingGasTypes = AeroJavaOrder.liftingGasTypes;

/// `aeronautics:levitite_crystal_propagation_context` —
/// `AeroJavaOrder.crystallizationContextRegistry`.
const String aeroCrystallizationContextRegistry = AeroJavaOrder.crystallizationContextRegistry;
const List<String> aeroCrystallizationContexts = AeroJavaOrder.crystallizationContexts;

/// Registers the mod's content into [registry] and pins every id order.
///
/// [lookup] resolves a block entity by world and position; the module passes the
/// store's `typed`, for the block entities whose behaviour needs a neighbour.
void registerAeronautics(
  CreateRegistry registry, {
  required T? Function<T>(String worldId, (int, int, int) pos) lookup,
}) {
  // -- Blocks -------------------------------------------------------------------
  for (final block in _blocks()) {
    registry.block(block);
  }

  // -- Items --------------------------------------------------------------------
  // The block items are registered by `registry.block`; the standalone ones here.
  for (final item in aeroItems()) {
    registry.item(item);
  }

  // -- Datapack registries --------------------------------------------------------
  // `AeroGeneratedEntries.gatherRegistryEntries` adds `AeroJukeboxSongs` to
  // `Registries.JUKEBOX_SONG` (`data/AeroGeneratedEntries.java:28`). The disc's
  // `jukebox_playable` names that entry, and the client resolves it while it
  // binds item components when configuration finishes
  // (`RegistryDataCollector.updateComponents`), so the entry has to be part of
  // the registry data the host sends; without it the client disconnects with
  // "Missing element ResourceKey[minecraft:jukebox_song / aeronautics:cloud_skipper]".
  registry.datapackRegistry(jukeboxSongRegistry);
  registry.datapackEntry(jukeboxSongRegistry, cloudSkipperSongKey, cloudSkipperSongNbt());

  // -- Block entity types --------------------------------------------------------
  void type(String key, List<String> validBlocks, CreateBlockEntity Function(String worldId, BlockPos pos) create) {
    registry.blockEntityType(BlockEntityTypeSpec(key: key, validBlocks: validBlocks, create: create));
  }

  type('aeronautics:steam_vent', const [steamVentKey], SteamVentBlockEntity.new);
  type(hotAirBurnerKey, const [hotAirBurnerKey], HotAirBurnerBlockEntity.new);
  type(propellerBearingKey, const [propellerBearingKey], PropellerBearingBlockEntity.new);
  type(
    gyroscopicPropellerBearingKey,
    const [gyroscopicPropellerBearingKey],
    GyroscopicPropellerBearingBlockEntity.new,
  );
  type(
    'aeronautics:envelope_encased_shaft',
    [for (final color in aeroDyeColors) encasedEnvelopeKey(color)],
    // The encased shaft is a plain kinetic block entity in Java
    // (`KineticBlockEntity::new`, `AeroBlockEntityTypes.java:60-64`).
    EncasedShaftBlockEntity.new,
  );
  type('aeronautics:andesite_propeller', const [SmallPropellerKeys.andesite], AndesitePropellerBlockEntity.new);
  type('aeronautics:wooden_propeller', const [SmallPropellerKeys.wooden], WoodenPropellerBlockEntity.new);
  type('aeronautics:smart_propeller', const [SmallPropellerKeys.smart], SmartPropellerBlockEntity.new);
  type(
    mountedPotatoCannonKey,
    const [mountedPotatoCannonKey],
    MountedPotatoCannonBlockEntity.new,
  );

  // -- Entity types ---------------------------------------------------------------
  registry.entityType(
    const EntityTypeSpec(
      key: 'aeronautics:propeller_bearing_contraption',
      width: 1,
      height: 1,
      eyeHeight: 0,
      fireImmune: true,
      trackingRange: 20,
      updateInterval: 40,
    ),
  );
  registry.entityType(
    const EntityTypeSpec(
      key: 'aeronautics:gust',
      width: 1,
      height: 1,
      eyeHeight: 0,
      fireImmune: true,
      trackingRange: 20,
      updateInterval: 40,
    ),
  );

  // -- Data components ------------------------------------------------------------
  registry.dataComponent('aeronautics:levitating', codec: levitatingComponentCodec, persistent: true);
  registry.dataComponent('aeronautics:converter', codec: converterComponentCodec, persistent: true);

  // -- Custom registries ----------------------------------------------------------
  registry.syncedRegistry(aeroLiftingGasTypeRegistry, aeroLiftingGasTypes);
  registry.syncedRegistry(aeroCrystallizationContextRegistry, aeroCrystallizationContexts);

  // -- Fluid ----------------------------------------------------------------------
  // `AeroFluidsNeoForge`'s `standardFluid("levitite_blend", ...)`
  // (`AeroFluidsNeoForge.java:23-52`) registers the source, its flowing variant
  // and the bucket in one call: the source enters the fluid registry first and
  // the flowing entry last (`FluidBuilder.java:597-614`), the bucket item is
  // `<name>_bucket` (`:293,494`). The host numbers fluids in registration order
  // and rejects a still fluid whose flowing variant never registers, so both
  // entries come from the one table, source first.
  for (final pair in AeroJavaOrder.fluidPairs) {
    registry.item(ItemRegistration(key: pair.bucket));
    registry.fluid(
      FluidSpec(
        key: pair.still,
        flowingVariant: pair.flowing,
        placement: FluidPlacement(block: pair.block, flowing: false),
        bucketItem: pair.bucket,
        tickRate: 25,
        levelDecreasePerBlock: 2,
        slopeFindDistance: 3,
        density: 1400,
        viscosity: 1500,
      ),
    );
    registry.fluid(
      FluidSpec(
        key: pair.flowing,
        tickRate: 25,
        levelDecreasePerBlock: 2,
        density: 1400,
        viscosity: 1500,
      ),
    );
  }

  // -- Channels -------------------------------------------------------------------
  // The channel table lives in `aeronautics_channels.dart` (`AeroPacketManager`)
  // and goes into the declaration through `AeronauticsAddon`, Create's generic
  // hook, not through this registry: a channel declared twice is rejected.

  // -- Tags -----------------------------------------------------------------------
  registry.tag(TagKind.block, 'aeronautics:airtight', [
    for (final color in aeroDyeColors) ...[
      envelopeKey(color),
      encasedEnvelopeKey(color),
    ],
  ]);
  registry.tag(TagKind.block, 'aeronautics:levitite', const [
    'aeronautics:levitite',
    'aeronautics:pearlescent_levitite',
  ]);
  registry.tag(TagKind.item, 'aeronautics:levitite', const [
    'aeronautics:levitite',
    'aeronautics:pearlescent_levitite',
  ]);
  registry.tag(TagKind.block, 'aeronautics:levitite_catalyzer', const ['minecraft:fire']);
  registry.tag(TagKind.block, 'aeronautics:levitite_soul_catalyzer', const ['minecraft:soul_fire']);

  // -- Id order -------------------------------------------------------------------
  registry.useOrder(RegistryKind.blocks, aeroBlockOrder);
  registry.useOrder(RegistryKind.items, aeroItemOrder);
  registry.useOrder(RegistryKind.blockEntityTypes, aeroBlockEntityOrder);
  registry.useOrder(RegistryKind.entityTypes, aeroEntityTypeOrder);
  registry.useOrder(RegistryKind.dataComponents, aeroDataComponentOrder);
  registry.useOrder(RegistryKind.fluids, AeroJavaOrder.fluidOrder);
}

/// The block definitions, in [aeroBlockOrder].
List<CreateBlock> _blocks() => [
  ...buildEnvelopeBlocks(),
  buildHotAirBurnerBlock(),
  buildSteamVentBlock(),
  buildPropellerBearingBlock(),
  buildGyroscopicPropellerBearingBlock(),
  ...buildSmallPropellerBlocks(),
  buildMountedPotatoCannonBlock(),
  buildLevititeBlock(),
  buildPearlescentLevititeBlock(),
  buildLevititeBlendBlock(),
];

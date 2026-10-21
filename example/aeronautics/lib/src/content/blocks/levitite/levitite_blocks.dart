// The levitite blocks: the crystal the blend becomes, and the blend fluid block.
//
// Java: `index/AeroBlocks.java:388-424` (the two crystal blocks) and
// `aeronautics/neoforge/.../index/AeroFluidsNeoForge.java:24-52` (the fluid).
//
// Levitite carries `aeronautics:levitating` as a *default item component*
// (`AeroBlocks.java:405,420`): an item of it falls slowly. Both crystals drop
// nothing (`noLootTable`), are mined with a pickaxe and emit light 10.
//
// Pure: no host imports beyond the block/component descriptions.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:pumpkin_api/pumpkin_api.dart';


/// `aeronautics:levitite`.
const String levititeKey = 'aeronautics:levitite';

/// `aeronautics:pearlescent_levitite`.
const String pearlescentLevititeKey = 'aeronautics:pearlescent_levitite';

/// `aeronautics:levitite_blend`: the fluid block, registered by the loader half
/// of the Java mod (`AeroFluidsNeoForge`).
const String levititeBlendBlockKey = 'aeronautics:levitite_blend';

/// `AeroBlocks.LEVITITE`.
CreateBlock buildLevititeBlock() => _levititeBlock(levititeKey);

/// `AeroBlocks.PEARLESCENT_LEVITITE`.
CreateBlock buildPearlescentLevititeBlock() => _levititeBlock(pearlescentLevititeKey);

// TODO(parity): `AeroBlocks.java:405,420` gives the item the
// `aeronautics:levitating` default component (`Levitating.LEVITITE` /
// `PEARLESCENT_LEVITITE`). The host's `item-registry.register-item` only accepts
// the vanilla component set, so the value is kept per item key by
// `Levitating.byItemKey` and applied by the item-entity tick instead.
CreateBlock _levititeBlock(String key) => CreateBlock(
  key: key,
  hardness: 7,
  blastResistance: 20,
  requiresCorrectTool: true,
  luminance: 10,
  soundType: 'amethyst',
  // `.properties(BlockBehaviour.Properties::noLootTable)`.
  drops: BlockDrops.nothing,
  tags: const ['minecraft:mineable/pickaxe', 'aeronautics:levitite'],
);

/// `AeroFluidsNeoForge.LEVITITE_BLEND`: the fluid block.
///
/// `standardFluid("levitite_blend", ...)` registers the still fluid, its flowing
/// variant, this block and the bucket; the block is a liquid block the host
/// places through the fluid registry (`FluidSpec.placement`), so it is declared
/// here only for its id position.
///
/// It is a vanilla `LiquidBlock` (`FluidBuilder.java:405-426,601`), whose one
/// property is `LEVEL` (`LiquidBlock.java:39,225`), an int from 0 to 15
/// (`BlockStateProperties.java:116`) with default 0 (`LiquidBlock.java:58`):
/// sixteen states. The host reads `level` off the block when it places fluid
/// (`fluid_registry.rs:fluid_state_of`), so a block without it would take a state
/// a Java client numbers differently.
CreateBlock buildLevititeBlendBlock() => CreateBlock(
  key: levititeBlendBlockKey,
  properties: [CreateProps.level('level', 15)],
  defaultState: {'level': '0'},
  hardness: 100,
  blastResistance: 100,
  replaceable: true,
  canOcclude: false,
  collisionShape: BlockShape.empty,
  selectionShape: BlockShape.empty,
  soundType: 'empty',
  drops: BlockDrops.nothing,
  hasItem: false,
);

// The sixteen dyed portable engines: one block definition each, the placement
// rule of `HorizontalKineticBlock.getPreferredHorizontalFacing`, the shapes of
// `SimBlockShapes.PORTABLE_ENGINE` and the use behaviour of
// `PortableEngineBlock.useItemOn`.
//
// Java registers the family with Registrate (`SimBlocks.PORTABLE_ENGINES`,
// `SimBlocks.java:327-375`), one item per colour, and the block entity type
// `simulated:portable_engine` accepts all sixteen.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.portable_engine.PortableEngineBlock
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter, stateIdOf;
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/contraptions/bearing/bearing_placement.dart'
    show bearingShaftNeighbours;
import 'package:create/src/processing/host/stack_host.dart' show HostStacks;
import 'package:create/src/core/blocks.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../service/sim_services.dart';
import 'portable_engine_block_entity.dart';

/// The block key of the engine of [colour] (`simulated:<colour>_portable_engine`).
String portableEngineKey(String colour) => 'simulated:${colour}_portable_engine';

/// The colour of an engine block key, `null` for anything else.
String? portableEngineColourOf(String blockKey) {
  const prefix = 'simulated:';
  const suffix = '_portable_engine';
  if (!blockKey.startsWith(prefix) || !blockKey.endsWith(suffix)) return null;
  return blockKey.substring(prefix.length, blockKey.length - suffix.length);
}

/// `SimBlockShapes.PORTABLE_ENGINE`: a 16 x 4 base plate and a 10 x 12 body one
/// pixel in from the sides, `forDirectional(NORTH)` — so `north`/`south` put the
/// body on the `z` sides and `east`/`west` on the `x` sides (the shape is
/// symmetric under a half turn).
List<BlockBox> portableEngineBoxes(Direction facing) {
  final alongX = facing.axis == Axis.x;
  return [
    const BlockBox(0, 0, 0, 1, 4 / 16, 1),
    alongX
        ? const BlockBox(1 / 16, 2 / 16, 3 / 16, 15 / 16, 14 / 16, 13 / 16)
        : const BlockBox(3 / 16, 2 / 16, 1 / 16, 13 / 16, 14 / 16, 15 / 16),
  ];
}

/// `PortableEngineBlock.getStateForPlacement`:
///
/// ```java
/// Direction preferred = getPreferredHorizontalFacing(context);   // a horizontal
///                                                               // neighbour with a shaft
/// if (preferred == null || player.isShiftKeyDown()) {
///     Direction horizontal = context.getHorizontalDirection();
///     return defaultBlockState().setValue(HORIZONTAL_FACING,
///         sneaking ? horizontal.getOpposite() : horizontal);
/// }
/// return defaultBlockState().setValue(HORIZONTAL_FACING, preferred);
/// ```
///
/// The shaft rule is the same one the bearing family uses
/// ([bearingShaftNeighbours]); unlike a bearing the engine does not turn it
/// around (`opposite: false`), because its shaft is on the facing side
/// (`hasShaftTowards(face) = face == HORIZONTAL_FACING`).
const List<PlacementRule> portableEnginePlacement = [
  PlacementRule.neighbourShaft('facing', bearingShaftNeighbours, whenSneaking: false),
  PlacementRule.horizontalFacing('facing', whenSneaking: false),
  PlacementRule.horizontalFacing('facing', opposite: true, whenSneaking: true),
];

/// One engine of the family.
///
/// [lookup] resolves the block entity of the position (the store's `typed`).
CreateBlock portableEngineBlock(
  String colour, {
  required T? Function<T>(String worldId, (int, int, int) pos) lookup,
}) {
  final key = portableEngineKey(colour);
  return CreateBlock(
    key: key,
    // `PortableEngineBlock.createBlockStateDefinition`: `LIT` plus
    // `HorizontalKineticBlock`'s `HORIZONTAL_FACING` (`:58-62`), so eight states.
    properties: [CreateProps.horizontalFacing, CreateProps.lit],
    defaultState: {'facing': 'north', 'lit': 'false'},
    // `SharedProperties::stone` (1.5 / 6.0), `SoundType.NETHERITE_BLOCK`,
    // `noOcclusion`, `MINEABLE_WITH_PICKAXE` (`SimBlocks.java:357-374`).
    //
    // The light level is `lit ? 6 : 0` in Java; a plugin block's `luminance` is
    // one number for every state, so the port keeps the unlit value (a lit
    // engine does not glow here).
    hardness: 1.5,
    blastResistance: 6,
    requiresCorrectTool: true,
    soundType: 'netherite_block',
    canOcclude: false,
    collisionShape: BlockShape.boxes(portableEngineBoxes(Direction.north)),
    selectionShape: BlockShape.boxes(portableEngineBoxes(Direction.north)),
    shapeRules: [
      for (final facing in [Direction.south, Direction.east, Direction.west])
        ShapeRule(
          when: {'facing': facing.serializedName},
          collisionShape: BlockShape.boxes(portableEngineBoxes(facing)),
          selectionShape: BlockShape.boxes(portableEngineBoxes(facing)),
        ),
    ],
    tags: const ['minecraft:mineable/pickaxe'],
    hasItem: true,
    drops: BlockDrops.selfItem,
    blockEntityType: PortableEngineBlockEntity.type,
    placement: portableEnginePlacement,
    behavior: BlockBehavior(
      onUseWithItem: (server, event) => _useItem(server, event, lookup),
      // `getAnalogOutputSignal`: what is left to burn.
      onComparatorOutput: (server, event) =>
          lookup<PortableEngineBlockEntity>(event.targetWorld.getId(), event.pos.toPos())?.analogOutput ?? 0,
    ),
  );
}

/// `PortableEngineBlock.useItemOn`.
Future<BlockUseResult> _useItem(
  Server server,
  CustomBlockUseEventData event,
  T? Function<T>(String worldId, (int, int, int) pos) lookup,
) async {
  final world = event.targetWorld;
  final worldId = world.getId();
  final pos = event.pos;
  final base = pos.toPos();
  final itemKey = HostStacks.namespaced(await event.item.getRegistryKey());
  final state = HostBlockGetter.stateOfId(world.getBlockStateId(pos: pos));
  final be = lookup<PortableEngineBlockEntity>(worldId, base);

  // An empty engine and an empty hand: nothing to do (Java `TRY_WITH_EMPTY_HAND`).
  if ((be?.slot.isEmpty ?? true) && itemKey.isEmpty) return BlockUseResult.tryEmptyHand;

  // -- Dye: the engine of this colour becomes the engine of that colour --------
  final colour = SimServices.dyeColorOf(itemKey);
  if (colour != null) {
    final target = portableEngineKey(colour);
    if (state.key != target) {
      final id = stateIdOf(BState(target, state.props));
      if (id != null) {
        // `shouldChangedStateKeepBlockEntity`: the engine keeps its block entity
        // -- and the fuel in it -- across the swap. The host removes a plugin
        // block entity whenever its block is replaced, so the swap is written
        // with the flag that skips that callback.
        await world.setBlockState(
          pos: pos,
          state: id,
          updateFlags: {
            BlockFlagsFlag.notifyNeighbors,
            BlockFlagsFlag.skipBlockEntityReplacedCallback,
          },
        );
        world.sound(
          Sound.itemDyeUse,
          (pos.x + .5, pos.y + .5, pos.z + .5),
          category: SoundCategory.blocks,
          volume: 1,
          pitch: 1.1,
        );
      }
    }
    return BlockUseResult.success;
  }

  // -- Creative blaze cake: superheat the fuel, or burn forever ----------------
  if (itemKey == 'create:creative_blaze_cake') {
    be?.burn.applyCreativeBlazeCake();
    be?.sendData();
    return BlockUseResult.success;
  }

  if (be == null) return BlockUseResult.pass;

  // -- Fuel -------------------------------------------------------------------
  final held = await HostStacks.read(event.item);
  if (held.isNotEmpty && !be.canInsertStack(held)) return BlockUseResult.fail;

  final slot = be.slot;
  if (slot.isEmpty) {
    // The slot takes the held stack and the hand is emptied.
    be.setSlot(held);
    await event.player.setItemInHand(hand: event.hand, stack: null);
  } else if (slot.sameItemSameComponents(held)) {
    // The same fuel: merge up to the stack limit.
    final target = (slot.count + held.count).clamp(0, slot.maxCount);
    if (target <= slot.count) return BlockUseResult.success;
    final taken = target - slot.count;
    be.setSlot(slot.withCount(target));
    await event.player.setItemInHand(
      hand: event.hand,
      stack: await PortableEngineBlockEntity.hostStack(held.shrink(taken)),
    );
  } else {
    // Another fuel: the old one goes back to the player.
    final old = be.extract(slot.maxCount);
    if (old.isNotEmpty) {
      final stack = await PortableEngineBlockEntity.hostStack(old);
      if (stack != null) {
        await event.player.getInventory().storage.give(stack);
      }
      world.sound(
        Sound.entityItemPickup,
        (pos.x + .5, pos.y + .5, pos.z + .5),
        category: SoundCategory.players,
        volume: .2,
        pitch: 1,
      );
    }
  }
  be.sendData();
  return BlockUseResult.success;
}

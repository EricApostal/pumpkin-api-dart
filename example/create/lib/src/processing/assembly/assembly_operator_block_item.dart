// `AssemblyOperatorBlockItem`: the block items of the machines that must be placed two blocks
// above a belt, basin, depot or weighted ejector (the mechanical press, mixer, spout and
// deployer). Ported from `content/processing/AssemblyOperatorBlockItem.java`.
//
// The host places a block item at the clicked position; the item therefore intercepts
// `playerUseBlock` and writes the block at `clicked.above(2)` itself, cancelling the vanilla
// placement. The block state comes from the machine's own placement function (the deployer's
// shaft-aware state), with the horizontal facing as the fallback for the press.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../basin/basin_block.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../core/module.dart';
import '../deployer/deployer_block.dart' show deployerPlacement;
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';

/// Builds the state of an assembly operator block at [target].
typedef AssemblyOperatorPlacement = KState Function(
  PlacementContext? context,
  World world,
  Pos target,
  Player player,
);

/// The `AssemblyOperatorBlockItem`s of the processing module.
abstract final class AssemblyOperatorBlockItem {
  static final Map<String, String> _blockByItem = {};
  static final Map<String, AssemblyOperatorPlacement> _placements = {};

  /// Registers [itemKey] as an assembly operator item for [blockKey].
  static void register(
    String itemKey,
    String blockKey, {
    required AssemblyOperatorPlacement placement,
  }) {
    _blockByItem[itemKey] = blockKey;
    _placements[itemKey] = placement;
  }

  /// `onLoad`: registers the items and intercepts the placement.
  static void install(CreateContext ctx) {
    register(
      'create:mechanical_press',
      'create:mechanical_press',
      // `MechanicalPressBlock.getStateForPlacement`: a neighbouring horizontal shaft
      // decides the facing as it is, else `HorizontalKineticBlock`'s
      // `getHorizontalDirection().getOpposite()`.
      placement: (context, world, target, player) {
        final facing = context == null
            ? _horizontal(context, player).opposite
            : mechanicalPressFacing(context);
        return KState('create:mechanical_press', {'facing': facing.name});
      },
    );
    register(
      'create:mechanical_mixer',
      'create:mechanical_mixer',
      placement: (context, world, target, player) =>
          const KState('create:mechanical_mixer', {}),
    );
    register(
      'create:spout',
      'create:spout',
      placement: (context, world, target, player) =>
          const KState('create:spout', {}),
    );
    register(
      'create:deployer',
      'create:deployer',
      placement: (context, world, target, player) {
        if (context != null) {
          return deployerPlacement(context, KState.air, null, world);
        }
        return KState('create:deployer', {
          'facing': nearestLookingDirection(
            player.getYaw(),
            player.getPitch(),
          ).opposite.name,
          'axis_along_first': 'true',
        });
      },
    );

    ctx.host.intercept(Events.playerUseBlock, _onUse);
  }

  static Future<PlayerUseBlockEventData> _onUse(
    Server server,
    PlayerUseBlockEventData e,
  ) async {
    if (e.cancelled) return e;

    final String itemKey;
    try {
      itemKey = await e.item.getRegistryKey();
    } on Object {
      return e;
    }
    final blockKey = _blockByItem[itemKey];
    if (blockKey == null) return e;
    // `AssemblyOperatorBlockItem.place` only redirects a top-face click.
    if (e.face != BlockDirection.up) return e;

    final world = e.player.getWorld();
    final clicked = e.blockPos.toPos();
    final rt = ProcessingRuntime.instance;
    final worldId = rt.worlds.touch(world);
    if (!_operatesOn(world, worldId, clicked)) return e;

    final target = clicked.aboveBy(2);
    if (!HostBlockGetter(world).canBeReplaced(target)) {
      // Java returns `InteractionResult.FAIL`: the item is not placed at all.
      return e.cancel();
    }

    final context = _placementContext(world, worldId, target, e.player);
    final state = _placements[itemKey]!(context, world, target, e.player);
    final bstate = BState(state.block, state.props);
    if (!stateExists(bstate)) return e;

    await setBlockState(world, target, bstate);
    world.playCustomSound(
      soundName: 'minecraft:block.${_soundTypeOf(blockKey)}.place',
      category: SoundCategory.blocks,
      pos: (target.$1 + .5, target.$2 + .5, target.$3 + .5),
      volume: 1,
      pitch: 1,
    );
    if (e.player.getGamemode() != GameMode.creative) {
      await _shrinkHeld(e.player, e.hand, e.item);
    }
    return e.cancel();
  }

  /// `operatesOn`: a horizontal belt, a basin, a depot or a weighted ejector.
  static bool _operatesOn(World world, String worldId, Pos clicked) {
    final state = HostBlockGetter(world).stateAt(clicked);
    if (state.key == 'create:belt') return state['slope'] == 'horizontal';
    if (BasinBlock.isBasin(
      ProcessingRuntime.instance.store,
      worldId,
      clicked,
    )) {
      return true;
    }
    return state.key == 'create:depot' ||
        state.key == 'create:weighted_ejector';
  }

  static PlacementContext? _placementContext(
    World world,
    String worldId,
    Pos target,
    Player player,
  ) {
    if (!KineticsRuntime.isLoaded) return null;
    final level = KineticsRuntime.instance.level(worldId);
    return PlacementContext(
      pos: toKPos(target.toBlockPos()),
      // `AssemblyOperatorBlockItem.adjustContext` builds the context with
      // `Direction.UP` as the clicked face; only top-face clicks get here.
      clickedFace: Dir.up,
      nearestLooking: nearestLookingDirection(
        player.getYaw(),
        player.getPitch(),
      ),
      horizontal: horizontalDirection(player.getYaw()),
      sneaking: player.asEntity().isSneaking(),
      stateAt: level.stateAt,
      blocks: KineticsRuntime.instance.blocks,
    );
  }

  static Dir _horizontal(PlacementContext? context, Player player) =>
      context?.horizontal ?? horizontalDirection(player.getYaw());

  static String _soundTypeOf(String blockKey) {
    final path = blockKey.contains(':')
        ? blockKey.substring(blockKey.indexOf(':') + 1)
        : blockKey;
    return manifestBlocksByKey[path]?.soundType.toLowerCase() ?? 'stone';
  }

  /// `ItemStack.shrink(1)` in [hand].
  static Future<void> _shrinkHeld(
    Player player,
    Hand hand,
    ItemStack stack,
  ) async {
    final count = await stack.getCount();
    final inventory = player.getInventory();
    if (count <= 1) {
      await inventory.setItemInHand(hand: hand, item: null);
    } else {
      await stack.setCount(count: count - 1);
      await inventory.setItemInHand(hand: hand, item: stack);
    }
  }
}

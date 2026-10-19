// `RadialWrenchHandler` and the `create:radial_wrench_menu_submit` handler: a wrench rotation that
// picks the target state from the radial menu instead of cycling it.
//
// Java: `content/contraptions/wrench/{RadialWrenchHandler,RadialWrenchMenu,RadialWrenchMenuSubmitPacket}`.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/wrenchable.dart';
import '../../common/common.dart';
import '../../kinetics/api.dart' show KineticNetworkService, KState;
import '../blocks/actuator_runtime.dart';

/// The pitch of the rotate sound (`Create.RANDOM.nextFloat() + .5`).
final math.Random _random = math.Random();

/// `RadialWrenchMenuSubmitPacket.handle`: apply the state the player picked, if it is still the
/// same block.
Future<void> handleRadialWrenchSubmit(
  Player player,
  KineticNetworkService? kinetics,
  WrenchRegistry? wrench,
  Pos blockPos,
  BState newState,
) async {
  final world = player.getWorld();
  final current = HostBlockGetter(world).stateAt(blockPos);

  // `if (!level.getBlockState(blockPos).is(newState.getBlock())) return;`
  if (current.key != newState.key) return;

  final worldId = world.getId();
  final pos = BlockPos(x: blockPos.$1, y: blockPos.$2, z: blockPos.$3);

  // `KineticBlockEntity.switchToBlockState(level, blockPos, updatedState)`: the kinetic switch
  // keeps the network and the block entity data. `Block.updateFromNeighbourShapes` is applied by
  // the host when the state is written with neighbour updates (the menu sends a complete state).
  final switcher = wrench?.stateSwitcher;
  if (switcher != null) {
    final id = BlockRegistry.resolveState(newState.key, newState.props);
    if (id == null) return;
    await switcher(world, pos, id);
  } else if (kinetics != null && kinetics.isKineticBlock(newState.key)) {
    await kinetics.switchToBlockState(
      worldId,
      pos,
      KState(newState.key, newState.props),
    );
  } else {
    final id = BlockRegistry.resolveState(newState.key, newState.props);
    if (id == null) return;
    await world.setBlockState(
      pos: pos,
      state: id,
      updateFlags: BlockUpdateFlags.normal,
    );
  }

  // `IWrenchable.playRotateSound(level, pos)`.
  world.playCustomSound(
    soundName: 'create:wrench_rotate',
    category: SoundCategory.blocks,
    pos: blockPos.center,
    volume: 1,
    pitch: 0.5 + _random.nextDouble(),
  );
}

/// `RadialWrenchHandler`: which blocks offer the radial menu.
///
/// The Java class is client-side (it draws the menu); the server validates and applies the
/// submitted state in [handleRadialWrenchSubmit]. `RadialWrenchMenu.tryCreateFor` accepts any block
/// with one of the registered rotation properties, except the blacklisted water wheels.
final class RadialWrenchHandler {
  const RadialWrenchHandler();

  /// `RadialWrenchMenu.VALID_PROPERTIES`: the properties the menu can cycle.
  static const Set<String> rotationProperties = {
    'axis',
    'facing',
    'horizontal_axis',
    'horizontal_facing',
    'target',
    'vertical',
  };

  /// `RadialWrenchMenu.BLOCK_BLACKLIST`.
  static const Set<String> blockBlacklist = {
    'create:large_water_wheel',
    'create:water_wheel_structural',
  };

  /// Whether [state] has a radial wrench menu (`tryCreateFor`).
  static bool hasMenu(BState state) =>
      !blockBlacklist.contains(state.key) &&
      rotationProperties.any(state.props.containsKey);
}

/// Whether the block at [blockPos] has a radial wrench menu (the server-side part of
/// `RadialWrenchMenu.tryCreateFor`).
bool hasRadialWrenchMenu(World world, Pos blockPos) =>
    RadialWrenchHandler.hasMenu(HostBlockGetter(world).stateAt(blockPos));

/// The block entity store accessor kept for symmetry with the other actuator handlers.
Object? radialWrenchTarget(String worldId, Pos blockPos) => ActuatorRuntime
    .maybe
    ?.store
    .at(worldId, BlockPos(x: blockPos.$1, y: blockPos.$2, z: blockPos.$3));

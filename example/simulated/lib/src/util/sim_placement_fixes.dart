// Host glue for the placement states in `content/blocks/sim_placement.dart`: what a
// player clicked (the `placed` event does not carry the clicked face), the world
// reads the vanilla rule needs, and the write of the fixed state.
//
// The state is fixed in the block's `player-placed` hook, like Create's
// `decoration` module does it (`behaviour_support.dart:fixPlacedState`). The host
// writes the registration's default state first, the fix lands in the same tick,
// and its `world.setBlockState` reaches the clients with the next block-change
// flush — the same two-step the port's ladders, doors, girders and placards use.
//
// Host: this file uses `pumpkin_api` and Create's pure helpers.
//
// Java: `BlockPlaceContext` (the click and the look), `BlockItem.place`.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/api/blocks.dart'
    show HostBlockGetter, setBlockState, toDirection;
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' as d;
import 'package:create/src/common/host_bridge.dart' show BlockPosToPos;
import 'package:create/src/common/pos.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../content/blocks/sim_placement.dart';

/// The block click that may place a block, as `BlockPlaceContext` reads it.
final class SimClick {
  /// `BlockHitResult.getBlockPos()`: the block that was clicked.
  final Pos clickedPos;

  /// `BlockHitResult.getDirection()`: the face of the clicked block.
  final d.Direction face;

  /// The server tick of the click.
  final int tick;

  const SimClick(this.clickedPos, this.face, this.tick);

  /// `BlockPlaceContext.replacingClickedOnBlock()`: the clicked block was
  /// replaceable, so the new block went into the clicked position.
  bool replacingClickedOnBlock(Pos placedPos) => clickedPos == placedPos;
}

/// The last click of every player, and the tick counter that ages it.
///
/// Installed by the plugin; the block behaviours read it. Java keeps the click in
/// the `BlockPlaceContext` that reaches `getStateForPlacement`, which the host does
/// not hand to a `placed` hook, so the click has to be recorded when it happens
/// (`PlayerUseBlockEvent` fires before the place).
final class SimPlacementFixes {
  SimPlacementFixes();

  /// The installed instance, `null` before the plugin's `onLoad`.
  static SimPlacementFixes? instance;

  /// `AllConfigs.server()...`: a click older than this many ticks is not the click
  /// that placed a block (the host fires the place event in the same tick).
  static const int clickAge = 2;

  final Map<String, SimClick> _clicks = {};

  /// The last server tick seen, for [clickAge].
  int _tick = 0;

  /// Records every block click and follows the tick counter (for [clickAge]).
  void install(Context context) {
    context.listen(Events.serverTickStart, (server, event) => _tick = event.tick);
    context.intercept(Events.playerUseBlock, (server, event) async {
      _clicks[event.player.uuidString] = SimClick(
        event.blockPos.toPos(),
        toDirection(event.face),
        _tick,
      );
      return event;
    });
  }

  /// The click of [playerId] when it may have placed the block at [pos], consumed
  /// so one click belongs to one placement.
  SimClick? takeClick(Uuid? playerId, Pos pos) {
    if (playerId == null) return null;
    final click = _clicks.remove(playerId.asString);
    if (click == null || _tick - click.tick > clickAge) return null;
    if (click.replacingClickedOnBlock(pos) || click.clickedPos.relative(click.face) == pos) {
      return click;
    }
    return null;
  }
}

/// The state the host wrote for `block` at [stateIndex].
BState _placedState(String block, int stateIndex) =>
    HostBlockGetter.stateOfIndex(block, stateIndex);

/// The player that placed a block, or `null` when there is no such player (the
/// placement cannot be reproduced without one).
Player? _placingPlayer(Server server, Uuid? playerId) =>
    playerId == null ? null : server.getPlayerByUuid(id: playerId);

/// `Direction.orderedByNearest(player)` for the player's view vector.
List<d.Direction> _orderedByNearest(Player player) {
  final look = player.lookDirection;
  return d.Direction.orderedByNearest(look.$1, look.$2, look.$3);
}

/// `BlockPlaceContext.getHorizontalDirection()`: `player.getDirection()`.
d.Direction _horizontalDirection(Player player) => d.Direction.fromYRot(player.getYaw());

/// Runs [choose] for a player placement and writes the state it answers, if it
/// differs from the one the host wrote.
///
/// [choose] is `null` when the host has to keep its state: no placing player (a
/// mechanism placed the block), no recorded click (the click is not the one that
/// placed it), or a candidate Java would have refused.
Future<void> _fixPlacedState({
  required Server server,
  required World world,
  required BlockPos pos,
  required String block,
  required int stateIndex,
  required Uuid? playerId,
  required BState? Function(Player player, SimClick click, BState placed, HostBlockGetter getter)
  choose,
}) async {
  final player = _placingPlayer(server, playerId);
  if (player == null) return;
  final click = SimPlacementFixes.instance?.takeClick(playerId, pos.toPos());
  if (click == null) return;
  final placed = _placedState(block, stateIndex);
  final fixed = choose(player, click, placed, HostBlockGetter(world));
  if (fixed == null || fixed == placed) return;
  await setBlockState(world, pos.toPos(), fixed);
}

/// Fixes a face-attached block (the assembler, the throttle lever) to the state
/// Java's `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement` chooses.
///
/// Java answers `null` when no looking direction gives a surviving block, and the
/// item then places nothing. The block is already in the world here, so the state
/// stays the host's in that case; the placement itself is what the `can-place`
/// hook would have to refuse, and it is not wired for these blocks.
Future<void> fixFaceAttachedPlacement({
  required Server server,
  required World world,
  required BlockPos pos,
  required String block,
  required int stateIndex,
  required Uuid? playerId,
}) => _fixPlacedState(
  server: server,
  world: world,
  pos: pos,
  block: block,
  stateIndex: stateIndex,
  playerId: playerId,
  choose: (player, click, placed, getter) {
    final p = pos.toPos();
    return faceAttachedStateForPlacement(
      defaultState: placed,
      nearestLooking: nearestLookingDirections(
        orderedByNearest: _orderedByNearest(player),
        clickedFace: click.face,
        replacingClickedOnBlock: click.replacingClickedOnBlock(p),
      ),
      horizontalDirection: _horizontalDirection(player),
      canSurvive: (connected) {
        // `FaceAttachedHorizontalDirectionalBlock.canAttach`: the block behind the
        // attachment must be sturdy on the face it shows to the placed block.
        final support = p.relative(connected.opposite);
        return getter.isFaceSturdy(support, connected);
      },
    );
  },
);

/// Fixes the steering wheel to the state `SteeringWheelBlock.getStateForPlacement`
/// chooses (`facing` from the look, `on_floor` from the clicked face).
Future<void> fixSteeringWheelPlacement({
  required Server server,
  required World world,
  required BlockPos pos,
  required String block,
  required int stateIndex,
  required Uuid? playerId,
}) => _fixPlacedState(
  server: server,
  world: world,
  pos: pos,
  block: block,
  stateIndex: stateIndex,
  playerId: playerId,
  choose: (player, click, placed, getter) => steeringWheelStateForPlacement(
    defaultState: placed,
    view: player.lookDirection,
    clickedFace: click.face,
  ),
);
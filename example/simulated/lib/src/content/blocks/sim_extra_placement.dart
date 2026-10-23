// // Placing the Simulated blocks whose Java `getStateForPlacement` the host's
// // placement rules cannot express.
// //
// // The host's sources give a direction, an axis, a half, a stealth or a
// // neighbour-shaft direction; they cannot give `AttachFace` (the `face` / `target`
// // enums), and a four-valued `facing` may not take a `clicked-face` source at all
// // (the host rejects a rule whose source can give a value the property does not
// // list, and that rejection is what kept the whole plugin from loading once:
// // `property 'facing' has no value 'down'`). Those states are therefore written by
// // the block's `player-placed` hook, the way the assembler, the throttle lever, the
// // steering wheel and the portable engines already do it
// // (`util/sim_placement_fixes.dart`).
// //
// // Java sources: `NameplateBlock.getStateForPlacement` (`:107-121`),
// // `AltitudeSensorBlock.getStateForPlacement` (`:48-64`),
// // `LaserSensorBlock.getStateForPlacement` (`:34-50`),
// // `OpticalSensorBlock.getStateForPlacement` (`:57-70`),
// // `DockingConnectorBlock.getStateForPlacement` (`:66-74`),
// // `GimbalSensorBlock.getStateForPlacement` (`:38-41`).
// //
// // Host: this file uses `pumpkin_api` (the state is written through the world).
// // ignore_for_file: implementation_imports
// import 'dart:async';

// import 'package:create/src/api/block_state.dart' show BState;
// import 'package:create/src/api/blocks.dart' show HostBlockGetter, setBlockState;
// import 'package:create/src/common/direction.dart' show Axis, Direction;
// import 'package:create/src/common/host_bridge.dart';
// import 'package:create/src/common/pos.dart' show Pos;
// import 'package:pumpkin_api/pumpkin_api.dart';

// import '../../../util/sim_placement_fixes.dart' show SimClick, SimPlacementFixes;

// /// Runs [choose] for a player placement and writes the state it answers, when it
// /// differs from the one the host wrote.
// ///
// /// The host has already written its state, so a `null` answer keeps it (no placing
// /// player, no recorded click, or a state Java would not have produced).
// Future<void> fixExtraPlaced({
//   required Server server,
//   required World world,
//   required BlockPos pos,
//   required String block,
//   required int stateIndex,
//   required Uuid? playerId,
//   required BState? Function(Player player, SimClick click, BState placed, HostBlockGetter getter) choose,
// }) async {
//   if (playerId == null) return;
//   final player = server.getPlayerByUuid(id: playerId);
//   if (player == null) return;
//   final click = SimPlacementFixes.instance?.takeClick(playerId, pos.toPos());
//   if (click == null) return;
//   final placed = HostBlockGetter.stateOfIndex(block, stateIndex);
//   final fixed = choose(player, click, placed, HostBlockGetter(world));
//   if (fixed == null || fixed == placed) return;
//   await setBlockState(world, pos.toPos(), fixed);
// }

// /// `Direction.fromYRot(player.getYaw())` — `BlockPlaceContext.getHorizontalDirection()`
// /// is `player.getDirection()`, the 2D data value of the yaw.
// Direction horizontalDirectionOf(Player player) => Direction.fromYRot(player.getYaw());

// /// `NameplateBlock.getStateForPlacement` (`:107-121`).
// ///
// /// ```java
// /// Direction direction = context.getClickedFace();
// /// if (clickedFace.getAxis() == Axis.Y) direction = context.getHorizontalDirection().getOpposite();
// /// return state.setValue(POSITION, getPositionState(level, pos, direction)).setValue(FACING, direction);
// /// ```
// ///
// /// `facing` is the clicked face for a side click — Java's `HorizontalDirectionalBlock`
// /// default would have been the *horizontal* direction, and the nameplate hangs on the
// /// face that was clicked. A four-valued `facing` cannot take a `clicked-face` rule, so
// /// this is a hook.
// ///
// /// `POSITION` is `getPositionState` (`:129-145`): it reads the nameplates of the same
// /// colour to the left and to the right of [facing] and answers `single`, `left`,
// /// `right` or `middle`.
// BState? nameplateStateForPlacement({
//   required BState placed,
//   required Direction clickedFace,
//   required Direction horizontalDirection,
//   required Pos pos,
//   required BState Function(Pos pos) stateAt,
// }) {
//   final facing = clickedFace.isVertical ? horizontalDirection.opposite : clickedFace;
//   final position = _nameplatePosition(
//     stateAt: stateAt,
//     colour: _colourOf(placed.key),
//     pos: pos,
//     facing: facing,
//   );
//   return placed.setDir('facing', facing).setValue('position', position);
// }

// /// The colour of a nameplate block key (`simulated:<colour>_nameplate`).
// String _colourOf(String blockKey) {
//   const prefix = 'simulated:';
//   const suffix = '_nameplate';
//   if (!blockKey.startsWith(prefix) || !blockKey.endsWith(suffix)) return blockKey;
//   return blockKey.substring(prefix.length, blockKey.length - suffix.length);
// }

// /// `NameplateBlock.getPositionState`: `LEFT` when the counter-clockwise neighbour is
// /// the same colour and faces the same way, `RIGHT` for the clockwise one, `MIDDLE`
// /// when both are, `SINGLE` when neither is.
// String _nameplatePosition({
//   required BState Function(Pos pos) stateAt,
//   required String colour,
//   required Pos pos,
//   required Direction facing,
// }) {
//   bool same(Pos neighbour) {
//     final state = stateAt(neighbour);
//     return _colourOf(state.key) == colour &&
//         state.key.endsWith('_nameplate') &&
//         state.props['facing'] == facing.serializedName;
//   }

//   final left = same(pos.relative(facing.counterClockWise));
//   final right = same(pos.relative(facing.clockWise));
//   if (left && right) return 'middle';
//   if (left) return 'right';
//   if (right) return 'left';
//   return 'single';
// }

// /// `AltitudeSensorBlock.getStateForPlacement` (`:48-64`).
// ///
// /// ```java
// /// Direction facing = context.getHorizontalDirection().getOpposite();
// /// AttachFace face = AttachFace.FLOOR;
// /// if (clickedFace == DOWN) face = CEILING;
// /// else if (clickedFace.getAxis().isHorizontal()) { face = WALL; facing = clickedFace; }
// /// return defaultBlockState().setValue(HORIZONTAL_FACING, facing).setValue(FACE, face)
// ///     .setValue(DIAL, FaceType.LINEAR);
// /// ```
// BState altitudeSensorStateForPlacement({
//   required BState placed,
//   required Direction clickedFace,
//   required Direction horizontalDirection,
// }) {
//   var facing = horizontalDirection.opposite;
//   var face = 'floor';
//   if (clickedFace == Direction.down) {
//     face = 'ceiling';
//   } else if (clickedFace.isHorizontal) {
//     face = 'wall';
//     facing = clickedFace;
//   }
//   return placed.setDir('facing', facing).setValue('face', face).setValue('dial', 'linear');
// }

// /// `LaserSensorBlock.getStateForPlacement` and `OpticalSensorBlock`'s
// /// (`:34-50`, `:57-70`), which differ only in the vertical case.
// ///
// /// ```java
// /// Direction facing = context.getNearestLookingDirection();
// /// Direction preferred = player.isSteppingCarefully() ? facing : facing.getOpposite();
// /// if (preferred.getAxis() == Axis.Y) {
// ///     state = state.setValue(TARGET, preferred == UP ? AttachFace.CEILING : AttachFace.FLOOR);
// ///     preferred = context.getHorizontalDirection() [.getOpposite() for the optical sensor];
// /// }
// /// return state.setValue(FACING, preferred).setValue(POWERED, false);
// /// ```
// ///
// /// `getNearestLookingDirection()` is the promoted front of the ordered look list,
// /// i.e. the clicked face's opposite while the clicked block is not replaceable, so
// /// `preferred` is the clicked face (or its opposite when the player sneaks).
// BState laserSensorStateForPlacement({
//   required BState placed,
//   required Direction clickedFace,
//   required Direction horizontalDirection,
//   required bool sneaking,
//   required bool horizontalOppositeWhenVertical,
// }) {
//   var preferred = sneaking ? clickedFace.opposite : clickedFace;
//   var target = 'wall';
//   if (preferred.isVertical) {
//     target = preferred == Direction.up ? 'ceiling' : 'floor';
//     preferred = horizontalOppositeWhenVertical ? horizontalDirection.opposite : horizontalDirection;
//   }
//   return placed
//       .setValue('target', target)
//       .setDir('facing', preferred)
//       .setValue('powered', 'false');
// }

// /// `DockingConnectorBlock.getStateForPlacement` (`:66-74`) over
// /// `WrenchableDirectionalBlock`'s `FACING = getNearestLookingDirection()`.
// ///
// /// ```java
// /// Direction nearest = context.getNearestLookingDirection();
// /// if (player != null && player.isShiftKeyDown()) nearest = nearest.getOpposite();
// /// return super.getStateForPlacement(context)
// ///     .setValue(POWERED, context.getLevel().hasNeighborSignal(context.getClickedPos()))
// ///     .setValue(FACING, nearest.getOpposite());
// /// ```
// ///
// /// `nearest` is the clicked face's opposite for a normal click and the clicked face
// /// for a sneaking one, so `FACING` points at the player's look either way. `POWERED`
// /// is `hasNeighborSignal` at placement, which the host cannot read in a placement
// /// rule: it follows the redstone update that comes with the placement (the torsion
// /// spring has the same gap).
// BState dockingConnectorStateForPlacement({
//   required BState placed,
//   required Direction clickedFace,
//   required bool sneaking,
// }) {
//   final nearest = sneaking ? clickedFace : clickedFace.opposite;
//   return placed.setDir('facing', nearest.opposite).setValue('powered', 'false');
// }

// /// `GimbalSensorBlock.getStateForPlacement` (`:38-41`):
// /// `HORIZONTAL_AXIS = context.getHorizontalDirection().getClockWise().getAxis()`.
// BState gimbalSensorStateForPlacement({
//   required BState placed,
//   required Direction horizontalDirection,
// }) =>
//     placed.setValue('horizontal_axis', horizontalDirection.clockWise.axis == Axis.x ? 'x' : 'z');
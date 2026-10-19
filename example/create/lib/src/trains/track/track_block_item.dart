// `TrackBlockItem` (server part): the item of a track block.
//
// Java -> Dart: [select] stores the curve start of the clicked track in the stack's
// `create:track_connecting_from` component; [useOn] is `TrackBlockItem.useOn` - the click that
// starts a connection on a track block and the click that lays the whole run (straights and the
// curve) from it. `TrackPlacement.tryConnect` does the placement itself; this file only decides
// which of the two a click is and what feedback it shows. [use] is `TrackBlockItem.use` (the
// sneak-click in the air that clears a stuck selection).
//
// The client half of Java (`sendExtenderPacket`, the overlay and `isFoil` rendering) is not
// ported: the extended-curve flag arrives through `PlaceExtendedCurvePacket`, which the payload
// bus handles (`curved_track_packets.dart`).
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../api/block_state.dart';
import 'i_track_block.dart';
import 'track_block.dart' show TrackBlock, metalGirderKey;
import 'track_level.dart';
import 'track_placement.dart' show ConnectingFrom, PlacementInfo, TrackPlacement;

/// What `TrackBlockItem.useOn` did with the click (`InteractionResult` plus the feedback).
enum TrackUseOutcome {
  /// Not handled: `super.useOn`, the item places its block like any other block item.
  pass,

  /// A connection was started (`select`). Server side there is no message: the client shows the
  /// `track.second_point` hint itself.
  selected,

  /// The selection was cleared by a sneak-click.
  selectionCleared,

  /// The clicked block is a junction: `track.junction_start`.
  junctionStart,

  /// The clicked track is a tilted turn: `track.turn_start`.
  turnStart,

  /// The run was placed.
  placed,

  /// The connection is invalid; [TrackUseResult.message] says why.
  denied,

  /// The placement state of the item's block could not be built.
  failed,
}

/// The result of [TrackBlockItem.useOn].
final class TrackUseResult {
  const TrackUseResult(this.outcome, {this.message, this.info});

  final TrackUseOutcome outcome;

  /// A `create.track.*` lang key for the overlay message, `null` for none.
  final String? message;

  /// The placement, when one was attempted.
  final PlacementInfo? info;

  /// Whether the click is the item's: `false` means `super.useOn` (the block is placed).
  bool get handled => outcome != TrackUseOutcome.pass;

  /// `InteractionResult.SUCCESS`: the click worked (the hand swings). A denied or failed
  /// placement is `InteractionResult.FAIL`, which does not swing.
  bool get success =>
      outcome != TrackUseOutcome.denied && outcome != TrackUseOutcome.failed;

  @override
  String toString() => 'TrackUseResult(${outcome.name}${message == null ? '' : ', $message'})';
}

abstract final class TrackBlockItem {
  /// `select(world, pos, lookVec, heldItem)`: stores the curve start of the nearest track axis in
  /// [stack]'s `connectingFrom`. Returns false for a block that is no track.
  static bool select(
    TrackLevel level,
    Pos pos,
    Vec3 lookVec,
    TrackItemStack stack,
  ) {
    final blockState = level.stateAt(pos);
    final track = TrackBlockRegistry.ofState(blockState);
    if (track == null) return false;

    final nearestTrackAxis = track.getNearestTrackAxis(
      level,
      pos,
      blockState,
      lookVec,
    );
    final axis =
        nearestTrackAxis.getFirst() *
        (nearestTrackAxis.getSecond() == AxisDirection.positive ? -1 : 1);
    final end = track.getCurveStart(level, pos, blockState, axis);
    final normal = track.getUpNormal(level, pos, blockState).normalized;

    stack.connectingFrom = ConnectingFrom(pos, axis, normal, end);
    return true;
  }

  /// `clearSelection(stack)`.
  static void clearSelection(TrackItemStack stack) =>
      stack.connectingFrom = null;

  /// `isFoil(stack)`.
  static bool isFoil(TrackItemStack stack) => stack.connectingFrom != null;

  /// `TrackBlockItem.use(level, player, hand)`: a sneak-click in the air with a stack that is
  /// connecting clears the selection. Returns whether the use was the item's.
  static bool use(TrackItemStack stack, {required bool sneaking}) {
    if (!sneaking || !isFoil(stack)) return false;
    clearSelection(stack);
    return true;
  }

  /// `TrackBlockItem.useOn(ctx)`: the server logic of a click with a track item.
  ///
  /// Without a selection the click picks the track end to connect from ([select]); with one it
  /// lays the run to the clicked position through [TrackPlacement.tryConnect] - the straights
  /// up to both ends and the curve or S-bend between them. [stack] is the held stack and is
  /// changed in place (the `connecting_from` / `extended_curve` components are consumed);
  /// [player]'s inventory is the snapshot the placement takes the items from.
  ///
  /// [clickedState] is the state of the clicked block, [lookVec] the player's look direction and
  /// [yRot] the player's yaw (`getStateForPlacement` uses them when the run is placed onto a
  /// position that is not a track yet).
  static Future<TrackUseResult> useOn({
    required TrackLevel level,
    required TrackPlacementPlayer player,
    required TrackItemStack stack,
    required Pos clickedPos,
    required Direction clickedFace,
    required BState clickedState,
    required Vec3 lookVec,
    required double yRot,
    required bool sneaking,
  }) async {
    if (!isFoil(stack)) {
      final clickedTrack = TrackBlockRegistry.ofState(clickedState);
      if (clickedTrack != null &&
          clickedTrack.getTrackAxes(level, clickedPos, clickedState).length > 1) {
        return const TrackUseResult(
          TrackUseOutcome.junctionStart,
          message: 'create.track.junction_start',
        );
      }

      final trackEntity = level.getTrackBlockEntity(clickedPos);
      if (trackEntity != null && trackEntity.isTilted()) {
        return const TrackUseResult(
          TrackUseOutcome.turnStart,
          message: 'create.track.turn_start',
        );
      }

      if (select(level, clickedPos, lookVec, stack)) {
        return const TrackUseResult(TrackUseOutcome.selected);
      }
      return const TrackUseResult(TrackUseOutcome.pass);
    }

    if (sneaking) {
      clearSelection(stack);
      return const TrackUseResult(
        TrackUseOutcome.selectionCleared,
        message: 'create.track.selection_cleared',
      );
    }

    // `placing = !(state.getBlock() instanceof ITrackBlock)`: a click on a track continues the
    // line from it, a click on any other block puts the track next to the clicked face.
    final placing = TrackBlockRegistry.ofState(clickedState) == null;
    final maximiseTurn = stack.extendedCurve ?? false;
    stack.extendedCurve = null;

    var pos = clickedPos;
    var state = clickedState;
    if (placing) {
      if (!level.canBeReplaced(pos)) pos = pos.relative(clickedFace);
      final placed = placementState(level, pos, stack.itemKey, lookVec, yRot);
      if (placed == null) {
        return const TrackUseResult(TrackUseOutcome.failed);
      }
      state = placed;
    }

    final offhand = player.inventory.offhand;
    final info = await TrackPlacement.tryConnect(
      level,
      player,
      pos,
      state,
      stack,
      offhand != null && !offhand.isEmpty && offhand.itemKey == metalGirderKey,
      maximiseTurn,
    );

    if (!info.valid) {
      final message = info.message;
      return TrackUseResult(
        TrackUseOutcome.denied,
        message: message == null
            ? null
            : message.startsWith('create.')
            ? message
            : 'create.$message',
        info: info,
      );
    }

    // `stack.remove(TRACK_CONNECTING_FROM)` and `stack.remove(TRACK_EXTENDED_CURVE)` on the
    // main hand stack, so the next click starts a new connection.
    stack.connectingFrom = null;
    stack.extendedCurve = null;
    return TrackUseResult(TrackUseOutcome.placed, info: info);
  }

  /// `getPlacementState(ctx)`: the item's block with the shape that matches the look direction,
  /// waterlogged for [at]. `null` when [itemKey] is no track item.
  ///
  /// [at] is the position the block ends up on: vanilla's `BlockPlaceContext.getClickedPos()`
  /// is the clicked position when that is replaceable and the position next to the clicked face
  /// otherwise.
  static BState? placementState(
    TrackLevel level,
    Pos at,
    String itemKey,
    Vec3 lookVec,
    double yRot,
  ) {
    final track = TrackBlockRegistry.of(itemKey);
    if (track == null) return null;
    if (track is TrackBlock) {
      return track.getStateForPlacement(
        level,
        at,
        track.defaultState,
        lookAngle: lookVec,
        yRot: yRot,
      );
    }
    // An add-on track that is not a [TrackBlock]: the default state of its block.
    return BState(itemKey, {
      trackShapeProperty: 'zo',
      trackHasBeProperty: 'false',
      waterloggedProperty: 'false',
    });
  }
}

/// The English texts of the `create.track.*` keys `useOn` shows (`CreateLang.translateDirect`).
const Map<String, String> kTrackEnglish = {
  'create.track.selection_cleared': 'Selection Cleared',
  'create.track.valid_connection': 'Can Connect \u2714',
  'create.track.second_point': 'Place track or select a second point',
  'create.track.too_far': 'Too far away',
  'create.track.original_missing': 'Original block removed, Sneak-click to reset',
  'create.track.perpendicular': 'Cannot connect perpendicularly',
  'create.track.ascending_s_curve': 'Cannot create sloped S-Bends',
  'create.track.too_sharp': 'Turn too sharp',
  'create.track.too_steep': 'Slope too steep',
  'create.track.slope_turn': 'Cannot enter or leave slope on a turn',
  'create.track.opposing_slopes': 'Cannot connect opposing slopes',
  'create.track.leave_slope_ascending': 'Cannot leave this slope while ascending',
  'create.track.leave_slope_descending': 'Cannot leave this slope while descending',
  'create.track.turn_90': 'Can only turn up to 90 Degrees',
  'create.track.junction_start': 'Cannot start connection from a Junction',
  'create.track.turn_start': 'Cannot start connection from a Turn',
  'create.track.not_enough_tracks': 'Not holding enough tracks',
  'create.track.not_enough_pavement': 'Not holding enough pavement blocks',
  'create.track.hold_for_smooth_curve': 'Hold %1\$s for maximized turn',
};

/// The English text of a `create.track.*` key; the key itself when it has none.
String trackMessage(String key) => kTrackEnglish[key] ?? key;

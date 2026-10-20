// `TrackTargetingBlockItem` (server part): the block item of the station, signal and observer.
// The item selects a position on a track in its data components and, when the block is placed,
// stores the target (`TargetTrack`, `TargetDirection`, `Bezier`) as the block entity data the
// `TrackTargetingBehaviour` reads.
//
// Java -> Dart: the host has no item behaviour hook, so `useOn` runs from `itemUseFirst`
// ([installTrackTargeting]): the first click on a track stores the selected position in the held
// stack, and a click anywhere else consumes that selection and lets the host place the block. The
// block entity data of the placement (`BLOCK_ENTITY_DATA` in Java) cannot be put on the stack -
// the host only lets a plugin set components it registered - so the target is remembered until the
// block is placed and written into its `TrackTargetingBehaviour` then. What is ported is the
// server logic the client and the placement use: the overlap validation (`withGraphLocation`) and
// the item components (`selectedPos`, `selectedDirection`, `selectedBezier`). The client half (the
// overlay outlines and `useOnCurve`) is not.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../core/module.dart';
import '../entity/train_level.dart' show TrainSettings;
import '../graph/edge_point_type.dart';
import '../graph/track_graph_helper.dart';
import '../graph/track_graph_location.dart';
import '../signal/track_edge_point.dart';
import '../station/host_ops.dart' show playCreateSound, sendOverlay, trainsLang;
import '../support/runtime.dart';
import '../track/bezier_track_point_location.dart';
import '../track/i_track_block.dart';
import '../track/track_host.dart' show HostTrackLevel;
import '../track/track_level.dart';
import '../track/track_targeting_behaviour.dart';
import '../track/track_targeting_data.dart';

/// The item of the station block.
const String trackStationItem = 'create:track_station';

/// The item of the signal block.
const String trackSignalItem = 'create:track_signal';

/// The item of the observer block.
const String trackObserverItem = 'create:track_observer';

/// `TrackTargetingBlockItem.OverlapResult`.
enum OverlapResult {
  valid(null),
  occupied('track_target.occupied'),
  junction('track_target.no_junctions'),
  noTrack('track_target.invalid');

  const OverlapResult(this.feedback);

  /// The lang key below `create.` shown to the player, `null` when the target is valid.
  final String? feedback;
}

/// `getType(stack)`: the edge point type of a targeting item, `null` for other items.
EdgePointType<TrackEdgePoint>? targetingTypeOf(String itemKey) =>
    switch (itemKey) {
      trackStationItem => EdgePointType.STATION,
      trackSignalItem => EdgePointType.SIGNAL,
      trackObserverItem => EdgePointType.OBSERVER,
      _ => null,
    };

/// `withGraphLocation(level, pos, front, targetBezier, type, callback)`: validates that the track
/// position is free for an edge point of [type].
void withGraphLocation(
  TrackLevel level,
  Pos pos,
  bool front,
  BezierTrackPointLocation? targetBezier,
  EdgePointType<TrackEdgePoint> type,
  void Function(OverlapResult result, TrackGraphLocation? location) callback,
) {
  final state = level.stateAt(pos);
  final track = TrackBlockRegistry.ofState(state);
  if (track == null) {
    callback(OverlapResult.noTrack, null);
    return;
  }

  final trackAxes = track.getTrackAxes(level, pos, state);
  if (targetBezier == null && trackAxes.length > 1) {
    callback(OverlapResult.junction, null);
    return;
  }

  final targetDirection = front
      ? AxisDirection.positive
      : AxisDirection.negative;
  final location = targetBezier != null
      ? TrackGraphHelper.getBezierGraphLocationAt(
          level,
          pos,
          targetDirection,
          targetBezier,
        )
      : TrackGraphHelper.getGraphLocationAt(
          level,
          pos,
          targetDirection,
          trackAxes[0],
        );
  if (location == null) {
    callback(OverlapResult.noTrack, null);
    return;
  }

  final edge = location.graph.getConnection(
    location.edge.map(location.graph.locateNode),
  );
  if (edge == null) return;

  final edgeData = edge.getEdgeData();
  final edgePosition = location.position;
  for (final edgePoint in edgeData.getPoints()) {
    final otherEdgePosition = edgePoint.getLocationOn(edge);
    final distance = (edgePosition - otherEdgePosition).abs();
    if (distance > 0.75) continue;
    if (edgePoint.canCoexistWith(type, front) && distance < 0.25) continue;
    callback(OverlapResult.occupied, location);
    return;
  }

  callback(OverlapResult.valid, location);
}

/// The item components of a targeting item (`AllDataComponents`).
abstract final class TrackTargetingComponents {
  static const String selectedPos = 'create:track_targeting_item_selected_pos';
  static const String selectedDirection =
      'create:track_targeting_item_selected_direction';
  static const String bezier = 'create:track_targeting_item_bezier';

  /// `stack.get(TRACK_TARGETING_ITEM_SELECTED_POS)`.
  static Pos? readSelectedPos(ItemStack stack) {
    final bytes = stack.customComponent(selectedPos);
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, (r) => r.readBlockPos());
    } on Object {
      return null;
    }
  }

  static void writeSelectedPos(ItemStack stack, Pos pos) =>
      stack.setCustomComponent(
        selectedPos,
        PacketBuffer.encode((w) => w.writeBlockPos(pos)),
      );

  static void clearSelectedPos(ItemStack stack) =>
      stack.removeCustomComponent(selectedPos);

  /// `stack.get(TRACK_TARGETING_ITEM_SELECTED_DIRECTION)`.
  static bool? readSelectedDirection(ItemStack stack) {
    final bytes = stack.customComponent(selectedDirection);
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, (r) => r.readBool());
    } on Object {
      return null;
    }
  }

  static void writeSelectedDirection(ItemStack stack, bool front) =>
      stack.setCustomComponent(
        selectedDirection,
        PacketBuffer.encode((w) => w.writeBool(front)),
      );

  static void clearSelectedDirection(ItemStack stack) =>
      stack.removeCustomComponent(selectedDirection);

  /// `stack.get(TRACK_TARGETING_ITEM_BEZIER)`.
  static BezierTrackPointLocation? readBezier(ItemStack stack) {
    final bytes = stack.customComponent(bezier);
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, BezierTrackPointLocation.read);
    } on Object {
      return null;
    }
  }

  static void writeBezier(ItemStack stack, BezierTrackPointLocation location) =>
      stack.setCustomComponent(bezier, PacketBuffer.encode(location.write));

  static void clearBezier(ItemStack stack) =>
      stack.removeCustomComponent(bezier);

  /// `stack.remove(...)` of the three targeting components.
  static void clearAll(ItemStack stack) {
    clearSelectedPos(stack);
    clearSelectedDirection(stack);
    clearBezier(stack);
  }
}

/// `TrackTargetingBlockItem.getType(stack)`: the type of the item in [itemKey].
EdgePointType<TrackEdgePoint>? typeOfTargetingItem(String itemKey) =>
    targetingTypeOf(itemKey);

/// `stack.has(...)` helpers for the placement path.
bool hasTargetSelection(ItemStack stack) =>
    TrackTargetingComponents.readSelectedPos(stack) != null;

// -- the host placement path ---------------------------------------------------------------------

/// A target a targeting item selected, waiting for its station / signal / observer to be placed.
final class _PendingTarget {
  final String worldId;
  final Pos selectedPos;
  final bool front;
  final BezierTrackPointLocation? bezier;

  _PendingTarget(this.worldId, this.selectedPos, this.front, this.bezier);
}

/// The targets waiting for a placement, by player. `Uuid` has no `==`, so its two halves form the
/// key.
final Map<(int, int), _PendingTarget> _pendingTargets = {};

List<EventSubscription>? _trackTargetingSubscriptions;

/// Installs the two host hooks of `TrackTargetingBlockItem`:
///
///  * `itemUseFirst` runs `useOn`: a click on a track stores the target in the held stack
///    (`selectedPos`, `selectedDirection`, `selectedBezier`); a click anywhere else consumes that
///    selection and lets the host place the block. This is what makes a station, signal or
///    observer attach to the track the player pointed at - without it the placement carries no
///    target at all and the block entity never finds a track (`TrackTargetingBehaviour`).
///  * `customBlockPlaced` writes the remembered target into the placed block entity, which Java
///    does by putting `BLOCK_ENTITY_DATA` on the stack before `super.useOn` places it.
void installTrackTargeting(CreateContext ctx) {
  final subscriptions = _trackTargetingSubscriptions ??= [];
  subscriptions.add(
    ctx.host.intercept(Events.itemUseFirst, _onTargetingItemUse),
  );
  subscriptions.add(
    ctx.host.intercept(Events.customBlockPlaced, _onTargetingBlockPlaced),
  );
}

/// Removes the hooks and forgets the targets waiting for a placement.
void uninstallTrackTargeting() {
  for (final subscription in _trackTargetingSubscriptions ?? const <EventSubscription>[]) {
    subscription.cancel();
  }
  _trackTargetingSubscriptions = null;
  _pendingTargets.clear();
}

(int, int) _playerKey(Player player) {
  final id = player.getId();
  return (id.high, id.low);
}

/// `player.isShiftKeyDown()`. The entity handle is borrowed: release it before returning.
bool _isSneaking(Player player) {
  final entity = player.asEntity();
  try {
    return entity.isSneaking();
  } finally {
    entity.dispose();
  }
}

/// `TrackTargetingBlockItem.useOn`, from the host's `itemUseFirst` (the host has no item
/// behaviour hook). The station, signal and observer items select a position on a track first and
/// place the block on the next click.
Future<ItemUseFirstEventData> _onTargetingItemUse(
  Server server,
  ItemUseFirstEventData e,
) async {
  if (e.useResult != ItemUseFirstResult.pass) return e;

  final String itemKey;
  try {
    itemKey = await e.stack.getRegistryKey();
  } on Object {
    return e;
  }

  final player = e.player;
  final key = _playerKey(player);
  final type = targetingTypeOf(itemKey);
  if (type == null) {
    // Another item: a selection left over from before is not the one being placed now.
    _pendingTargets.remove(key);
    return e;
  }

  final stack = player.getItemInHand(hand: e.hand);
  if (stack == null) return e;

  final world = player.getWorld();
  final level = HostTrackLevel(world, Tr.i.store);
  final pos = e.blockPos.toPos();

  // `player.isShiftKeyDown() && stack.has(TRACK_TARGETING_ITEM_SELECTED_POS)`: a sneak click clears
  // the selection (`CreateLang` "track_target.clear" and `CONTROLLER_CLICK`).
  if (hasTargetSelection(stack) && _isSneaking(player)) {
    _pendingTargets.remove(key);
    sendOverlay(player, trainsLang('create.track_target.clear'));
    TrackTargetingComponents.clearAll(stack);
    await player.setItemInHand(hand: e.hand, stack: stack);
    playCreateSound(world, pos, 'controller_click', volume: 1, pitch: 0.5);
    return e.copyWith(useResult: ItemUseFirstResult.success);
  }

  final state = level.stateAt(pos);

  final track = TrackBlockRegistry.ofState(state);
  if (track != null) {
    _pendingTargets.remove(key);
    return _selectTarget(
      world,
      level,
      track,
      state,
      pos,
      type,
      player,
      e,
      stack,
    );
  }

  final selectedPos = TrackTargetingComponents.readSelectedPos(stack);
  if (selectedPos == null) {
    // `CreateLang.translateDirect("track_target.missing")` with `ChatFormatting.RED`.
    sendOverlay(player, trainsLang('create.track_target.missing'), color: 'c');
    return e.copyWith(useResult: ItemUseFirstResult.consume);
  }

  final front = TrackTargetingComponents.readSelectedDirection(stack) ?? false;
  final bezier = TrackTargetingComponents.readBezier(stack);
  // `pos.relative(clickedFace, state.canBeReplaced() ? 0 : 1)`.
  final placedPos =
      level.canBeReplaced(pos) ? pos : pos.relative(e.face.toDirection());

  final maxDistance = (bezier != null
          ? TrainSettings.current.maxTrackPlacementLength + 16
          : 16)
      .toDouble();
  if (!selectedPos.closerThan(placedPos, maxDistance)) {
    // `CreateLang.translateDirect("track_target.too_far")` with `ChatFormatting.RED`.
    sendOverlay(player, trainsLang('create.track_target.too_far'), color: 'c');
    return e.copyWith(useResult: ItemUseFirstResult.consume);
  }

  // Java clears the three components before `super.useOn` places the block; the target it would
  // have put on the stack as `BLOCK_ENTITY_DATA` waits here instead.
  TrackTargetingComponents.clearAll(stack);
  await player.setItemInHand(hand: e.hand, stack: stack);
  _pendingTargets[key] = _PendingTarget(
    Tr.i.worldId(world),
    selectedPos,
    front,
    bezier,
  );

  // `super.useOn`: the host places the block, which `_onTargetingBlockPlaced` then points at the
  // target.
  return e;
}

/// The click on a track: validate the position and store it in the held stack.
Future<ItemUseFirstEventData> _selectTarget(
  World world,
  HostTrackLevel level,
  ITrackBlock track,
  BState state,
  Pos pos,
  EdgePointType<TrackEdgePoint> type,
  Player player,
  ItemUseFirstEventData e,
  ItemStack stack,
) async {
  final front = track
          .getNearestTrackAxis(level, pos, state, player.lookDirection)
          .second ==
      AxisDirection.positive;

  var result = OverlapResult.valid;
  withGraphLocation(level, pos, front, null, type, (r, _) => result = r);
  if (result != OverlapResult.valid) {
    // `CreateLang.translateDirect(result.feedback)` with `ChatFormatting.RED`.
    sendOverlay(player, trainsLang('create.${result.feedback}'), color: 'c');
    playCreateSound(world, pos, 'deny', volume: 0.5, pitch: 1);
    return e.copyWith(useResult: ItemUseFirstResult.consume);
  }

  TrackTargetingComponents.writeSelectedPos(stack, pos);
  TrackTargetingComponents.writeSelectedDirection(stack, front);
  TrackTargetingComponents.clearBezier(stack);
  await player.setItemInHand(hand: e.hand, stack: stack);

  // `CreateLang.translateDirect("track_target.set")` and `CONTROLLER_CLICK`.
  sendOverlay(player, trainsLang('create.track_target.set'));
  playCreateSound(world, pos, 'controller_click', volume: 1, pitch: 1);
  return e.copyWith(useResult: ItemUseFirstResult.success);
}

/// The placement of a station, signal or observer: point its `TrackTargetingBehaviour` at the
/// target the item remembered, the way Java's `BLOCK_ENTITY_DATA` seeds the block entity.
Future<CustomBlockPlacedEventData> _onTargetingBlockPlaced(
  Server server,
  CustomBlockPlacedEventData e,
) async {
  // Only the `player-placed` half carries the player; the `placed` half (`null`) runs for the same
  // placement first.
  final uuid = e.player;
  if (uuid == null) return e;
  if (targetingTypeOf(e.block) == null) return e;

  final pending = _pendingTargets.remove((uuid.high, uuid.low));
  if (pending == null) return e;
  if (pending.worldId != e.targetWorld.getId()) return e;

  // The block key of a targeting block is its block entity type key (`create:track_station`, ...).
  final be = Tr.i.store.createAt(e.targetWorld, e.pos, e.block);
  final behaviour = be?.getBehaviour<TrackTargetingBehaviour<TrackEdgePoint>>();
  if (be == null || behaviour == null) return e;

  behaviour.targetTrack = targetOffset(e.pos.toPos(), pending.selectedPos);
  behaviour.targetDirection = pending.front
      ? AxisDirection.positive
      : AxisDirection.negative;
  behaviour.targetBezier = pending.bezier;
  be.sendData();

  // `CreateLang.translateDirect("track_target.success")` with `ChatFormatting.GREEN`.
  final player = server.getPlayerByUuid(id: uuid);
  if (player != null) {
    sendOverlay(player, trainsLang('create.track_target.success'), color: 'a');
  }
  return e;
}

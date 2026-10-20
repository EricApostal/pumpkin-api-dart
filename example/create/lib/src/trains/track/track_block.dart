// `TrackBlock` (pure): the logic of the track block. The host half (the registered block, its
// shapes, events and the block entity) is `track_host.dart`.
//
// Java -> Dart: block callbacks that write blocks are `Future`s; `getStateForPlacement` takes the
// state the host placed and the player's look direction; the block's entity is a
// [TrackBlockEntity] found through [TrackLevel.getTrackBlockEntity].
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../graph/dimension_palette.dart' show overworldId;
import '../graph/track_node_location.dart';
import 'all_portal_tracks.dart';
import 'i_track_block.dart';
import 'track_block_entity.dart';
import 'track_level.dart';
import 'track_material.dart';
import 'track_propagator.dart';
import 'track_shape.dart';

/// `state.getBlock() instanceof TrackBlock`.
bool isTrackBlockState(BState state) => TrackBlockRegistry.ofState(state) is TrackBlock;

/// `GirderBlock` key.
const String metalGirderKey = 'create:metal_girder';

/// `AllBlocks.SMALL_BOGEY`.
const String smallBogeyKey = 'create:small_bogey';

class TrackBlock extends ITrackBlock {
  /// The key of the registered block.
  final String blockKey;
  final TrackMaterial material;

  TrackBlock(this.material, {String? blockKey}) : blockKey = blockKey ?? material.getBlockKey() {
    TrackBlockRegistry.register(this.blockKey, this);
  }

  /// `registerDefaultState`: `shape=zo, turn=false, waterlogged=false`.
  BState get defaultState =>
      BState(blockKey, {trackShapeProperty: 'zo', trackHasBeProperty: 'false', waterloggedProperty: 'false'});

  /// `getStateForPlacement(ctx)`: [baseState] is the state the host placed (with water already
  /// applied), [lookAngle] and [yRot] describe the placing player (`null` look: no player).
  BState getStateForPlacement(BlockGetter level, Pos clickedPos, BState baseState, {Vec3? lookAngle, double yRot = 0}) {
    final stateForPlacement = withWater(level, baseState, clickedPos)!;
    if (lookAngle == null) return stateForPlacement;

    var look = vmul(lookAngle, 1, 0, 1);
    if (mthEqual(look.length, 0)) look = VecHelper.rotate((0.0, 0.0, 1.0), -yRot, Axis.y);

    look = vnorm(look);

    var best = TrackShape.zo;
    var bestValue = toFloat(3.4028234663852886E38);
    for (final shape in TrackShape.values) {
      if (shape.isJunction() || shape.isPortal()) continue;
      final axis = shape.getAxes()[0];
      final distance = math.min(vdistSqr(axis, look), vdistSqr(vnorm(axis) * -1, look));
      if (distance > bestValue) continue;
      bestValue = distance;
      best = shape;
    }

    final bestAxis = best.getAxes()[0];
    if (bestAxis.lengthSquared == 1) {
      for (final neg in Iterate.trueAndFalse) {
        final scaled = bestAxis * (neg ? -1 : 1);
        final offset = clickedPos + posContaining(scaled);

        if (level.isFaceSturdy(offset, Direction.up) && !level.isFaceSturdy(offset.above, Direction.down)) {
          if (best == TrackShape.xo) best = neg ? TrackShape.aw : TrackShape.ae;
          if (best == TrackShape.zo) best = neg ? TrackShape.an : TrackShape.as_;
        }
      }
    }

    return withTrackShape(stateForPlacement, best);
  }

  /// `playerWillDestroy(level, pos, state, player)`.
  Future<void> playerWillDestroy(TrackLevel level, Pos pos, BState state, {required bool isCreative}) async {
    if (!isCreative) return;
    final be = level.getTrackBlockEntity(pos);
    if (be == null) return;
    be.cancelDrops = true;
    await be.removeInboundConnections(true);
  }

  /// `onPlace(state, level, pos, oldState, isMoving)`.
  Future<void> onPlace(TrackLevel level, Pos pos, BState state, BState oldState) async {
    // 26.3: a same-block transition (HAS_BE toggling off, or SHAPE changing) needs the old onRemove
    // cleanup handled here, where both the old and new state are available.
    if (oldState.key == blockKey && state.key == blockKey) {
      if (hasBe(oldState) && !hasBe(state)) {
        final tbe = level.getTrackBlockEntity(pos);
        if (tbe != null && !level.isClientSide) await tbe.removeInboundConnections(true);
        if (!level.isClientSide) await level.removeBlockEntity(pos);
      }
      if (withHasBe(state, true) != withHasBe(oldState, true)) TrackPropagator.onRailRemoved(level, pos, oldState);
    }

    if (oldState.key == blockKey && withHasBe(state, true) == withHasBe(oldState, true)) return;
    if (level.isClientSide) return;
    if (!level.hasScheduledTick(pos, blockKey)) level.scheduleTick(pos, blockKey, 1);
    updateGirders(state, level, pos);
  }

  /// `setPlacedBy(...)`: validates the curves of the block entity.
  Future<void> setPlacedBy(TrackLevel level, Pos pos) async {
    final be = level.getTrackBlockEntity(pos);
    if (be != null) await be.validateConnections();
  }

  /// `tick(state, level, pos, random)` (the scheduled tick).
  Future<void> tick(TrackLevel level, Pos pos, BState state) async {
    TrackPropagator.onRailAdded(level, pos, state);
    final tbe = level.getTrackBlockEntity(pos);
    if (tbe != null) await tbe.tilt.undoSmoothing();
    if (!trackShapeOf(state).isPortal()) await connectToPortal(level, pos, state);
  }

  /// `connectToPortal(level, pos, state)`.
  Future<void> connectToPortal(TrackLevel level, Pos pos, BState state) async {
    final shape = trackShapeOf(state);
    final portalTest = shape == TrackShape.xo ? Axis.x : shape == TrackShape.zo ? Axis.z : null;
    if (portalTest == null) return;

    var pop = false;
    String? fail;
    Pos? failPos;

    for (final d in Iterate.directionsInAxis(portalTest)) {
      final portalPos = pos.relative(d);
      final portalState = level.stateAt(portalPos);
      if (!PortalTrackProvider.isSupportedPortal(portalState)) continue;

      pop = true;
      final otherSide = PortalTrackProvider.getOtherSide(level, BlockFace(pos, d));
      if (otherSide == null) {
        fail = 'missing';
        continue;
      }

      final otherLevel = otherSide.level;
      final otherTrack = otherSide.face;
      final otherTrackPos = otherTrack.pos;
      if (!otherLevel.canBeReplaced(otherTrackPos)) {
        fail = 'blocked';
        failPos = otherTrackPos;
        continue;
      }

      await level.setBlock(pos, withHasBe(withTrackShape(state, TrackShape.asPortal(d)), true));
      level.getTrackBlockEntity(pos)?.bind(otherLevel.dimension, otherTrackPos);

      final otherState = withWater(
        otherLevel,
        withHasBe(withTrackShape(state, TrackShape.asPortal(otherTrack.face)), true),
        otherTrackPos,
      )!;
      await otherLevel.setBlock(otherTrackPos, otherState);
      otherLevel.getTrackBlockEntity(otherTrackPos)?.bind(level.dimension, pos);

      pop = false;
    }

    if (!pop) return;

    await level.destroyBlock(pos, true);

    if (fail == null) return;
    level.notifyPortalFailure(pos, fail, failPos);
  }

  /// `updateShape(...)`: the state after a neighbour changed. A portal track whose portal is gone
  /// becomes air.
  BState updateShape(BlockGetter level, BState state, Direction direction, Pos currentPos) {
    final shape = trackShapeOf(state);
    if (!shape.isPortal()) return state;

    for (final d in Iterate.horizontalDirections) {
      if (TrackShape.asPortal(d) != trackShapeOf(state)) continue;
      if (direction != d) continue;

      final portalPos = currentPos.relative(d);
      final portalState = level.stateAt(portalPos);
      if (!PortalTrackProvider.isSupportedPortal(portalState)) return BState.air;
    }

    return state;
  }

  @override
  int getYOffsetAt(BlockGetter world, Pos pos, BState state, Vec3 end) {
    if (world is! TrackLevel) return 0;
    return world.getTrackBlockEntity(pos)?.tilt.getYOffsetForAxisEnd(end) ?? 0;
  }

  @override
  List<DiscoveredLocation> getConnected(
    BlockGetter worldIn,
    Pos pos,
    BState state,
    bool linear,
    TrackNodeLocation? connectedTo,
  ) {
    List<DiscoveredLocation> list;
    final BlockGetter world = connectedTo != null && worldIn is TrackLevel
        ? (worldIn.getLevel(connectedTo.dimension) ?? worldIn)
        : worldIn;

    if (getTrackAxes(world, pos, state).length > 1) {
      final center = atBottomCenterOf(pos) + (0.0, getElevationAtCenter(world, pos, state), 0.0);
      final shape = trackShapeOf(state);
      list = <DiscoveredLocation>[];
      for (final axis in getTrackAxes(world, pos, state)) {
        for (final fromCenter in Iterate.trueAndFalse) {
          ITrackBlock.addToListIfConnected(
            connectedTo,
            list,
            (d, b) => axis * (b ? 0 : fromCenter ? -d : d) + center,
            (b) => shape.getNormal(),
            (b) => world is TrackLevel ? world.dimension : overworldId,
            (v) => 0,
            axis,
            null,
            (b, v) => ITrackBlock.getMaterialSimple(world, v),
          );
        }
      }
    } else {
      list = super.getConnected(world, pos, state, linear, connectedTo);
    }

    if (!hasBe(state)) return list;
    if (linear) return list;

    if (world is! TrackLevel) return list;
    final trackBE = world.getTrackBlockEntity(pos);
    if (trackBE == null) return list;

    final connections = trackBE.getConnections();
    connections.forEach((connectedPos, bc) {
      ITrackBlock.addToListIfConnected(
        connectedTo,
        list,
        (d, b) => d == 1 ? bc.bePositions.get(b).toVec3() : bc.starts.get(b),
        (b) => bc.normals.get(b),
        (b) => world.dimension,
        bc.yOffsetAt,
        null,
        bc,
        (b, v) => ITrackBlock.getMaterialSimple(world, v, bc.getMaterial()),
      );
    });

    final bound = trackBE.boundLocation;
    if (bound == null) return list;

    final otherDim = bound.getFirst();
    final otherLevel = world.getLevel(otherDim);
    if (otherLevel == null) return list;
    final boundPos = bound.getSecond();
    final boundState = otherLevel.stateAt(boundPos);
    if (!TrackBlockRegistry.isTrack(boundState)) return list;

    final center = atBottomCenterOf(pos) + (0.0, getElevationAtCenter(world, pos, state), 0.0);
    final boundCenter = atBottomCenterOf(boundPos) + (0.0, getElevationAtCenter(otherLevel, boundPos, boundState), 0.0);
    final shape = trackShapeOf(state);
    final boundShape = trackShapeOf(boundState);
    final boundAxis = getTrackAxes(otherLevel, boundPos, boundState)[0];

    for (final axis in getTrackAxes(world, pos, state)) {
      ITrackBlock.addToListIfConnected(
        connectedTo,
        list,
        (d, b) => (b ? axis : boundAxis) * d + (b ? center : boundCenter),
        (b) => (b ? shape : boundShape).getNormal(),
        (b) => b ? world.dimension : otherLevel.dimension,
        (v) => 0,
        axis,
        null,
        (b, v) => ITrackBlock.getMaterialSimple(b ? world : otherLevel, v),
      );
    }

    return list;
  }

  /// `affectNeighborsAfterRemoval(state, level, pos, isMoving)`: the block is gone.
  void onRemoved(TrackLevel level, Pos pos, BState state) {
    TrackPropagator.onRailRemoved(level, pos, state);
    updateGirders(state, level, pos);
  }

  /// `updateGirders(state, level, pos, blockTicks)`: girders below the track re-check their
  /// connection to it.
  void updateGirders(BState state, TrackLevel level, Pos pos) {
    for (final vec3 in getTrackAxes(level, pos, state)) {
      if (vec3.length > 1 || vec3.y != 0) continue;
      for (final side in Iterate.positiveAndNegative) {
        final girderPos = pos.below + posContaining((vec3.z * side, 0.0, vec3.x * side));
        final girderState = level.stateAt(girderPos);
        if (girderState.key == metalGirderKey && !level.hasScheduledTick(girderPos, metalGirderKey)) {
          level.scheduleTick(girderPos, metalGirderKey, 1);
        }
      }
    }
  }

  /// `canSurvive(state, reader, pos)`.
  bool canSurvive(BlockGetter reader, Pos pos) => reader.stateAt(pos.below).key != blockKey;

  /// `getNearestTrackAxis` etc. use [getTrackAxes].
  @override
  Vec3 getUpNormal(BlockGetter world, Pos pos, BState state) => trackShapeOf(state).getNormal();

  @override
  List<Vec3> getTrackAxes(BlockGetter world, Pos pos, BState state) => trackShapeOf(state).getAxes();

  @override
  Vec3 getCurveStart(BlockGetter world, Pos pos, BState state, Vec3 axis) {
    final vertical = axis.y != 0;
    return VecHelper.getCenterOf(pos) + (0.0, vertical ? 0.0 : toFloat(-.5), 0.0) + axis * .5;
  }

  /// `onSneakWrenched` part before the dismantle: hands the curves' items to the player.
  void onSneakWrenched(TrackBlockEntity? trackBE, BState state, TrackPlacementPlayer player) {
    if (!player.isCreative() && hasBe(state) && trackBE != null) {
      trackBE.cancelDrops = true;
      for (final bc in trackBE.connections.values) {
        bc.addItemsToPlayer(player);
      }
    }
  }

  @override
  BState overlay(BlockGetter world, Pos pos, BState existing, BState placed) {
    if (placed.key != blockKey) return existing;

    final existingShape = trackShapeOf(existing);
    final placedShape = trackShapeOf(placed);
    TrackShape? combinedShape;

    for (final flip in Iterate.trueAndFalse) {
      final s1 = flip ? existingShape : placedShape;
      final s2 = flip ? placedShape : existingShape;
      if (s1 == TrackShape.xo && s2 == TrackShape.zo) combinedShape = TrackShape.crO;
      if (s1 == TrackShape.pd && s2 == TrackShape.nd) combinedShape = TrackShape.crD;
      if (s1 == TrackShape.xo && s2 == TrackShape.pd) combinedShape = TrackShape.crPdx;
      if (s1 == TrackShape.zo && s2 == TrackShape.pd) combinedShape = TrackShape.crPdz;
      if (s1 == TrackShape.xo && s2 == TrackShape.nd) combinedShape = TrackShape.crNdx;
      if (s1 == TrackShape.zo && s2 == TrackShape.nd) combinedShape = TrackShape.crNdz;
    }

    if (combinedShape != null) existing = withTrackShape(existing, combinedShape);
    return existing;
  }

  /// `rotate(state, rotation)`.
  BState rotate(BState state, BlockRotation rotation) => withTrackShape(state, trackShapeOf(state).rotate(rotation));

  /// `mirror(state, mirror)`.
  BState mirror(BState state, BlockMirror mirror) => withTrackShape(state, trackShapeOf(state).mirror(mirror));

  @override
  BState getBogeyAnchor(BlockGetter world, Pos pos, BState state) => BState(smallBogeyKey, {
    'axis': trackShapeOf(state) == TrackShape.xo ? 'x' : 'z',
    'waterlogged': 'false',
  });

  @override
  bool trackEquals(BState state1, BState state2) =>
      state1.key == blockKey && state2.key == blockKey && withHasBe(state1, false) == withHasBe(state2, false);

  /// `getRequiredItems(state, be)`: the items a schematic needs for this track (the block, the
  /// items of its curves and their girders).
  List<TrackItemStack> getRequiredItems(BState state, TrackBlockEntity? be) {
    var sameTypeTrackAmount = 1;
    final otherTrackAmounts = <TrackMaterial, int>{};
    var girderAmount = 0;

    if (be != null) {
      for (final bezierConnection in be.getConnections().values) {
        if (!bezierConnection.isPrimary()) continue;
        final material = bezierConnection.getMaterial();
        if (identical(material, getMaterial())) {
          sameTypeTrackAmount += bezierConnection.getTrackItemCost();
        } else {
          otherTrackAmounts[material] = (otherTrackAmounts[material] ?? 0) + 1;
        }
        girderAmount += bezierConnection.getGirderItemCost();
      }
    }

    final stacks = <TrackItemStack>[];
    while (sameTypeTrackAmount > 0) {
      stacks.add(TrackItemStack(state.key, math.min(sameTypeTrackAmount, 64)));
      sameTypeTrackAmount -= 64;
    }
    for (final material in otherTrackAmounts.keys) {
      var amt = otherTrackAmounts[material] ?? 0;
      while (amt > 0) {
        stacks.add(TrackItemStack(material.getItemKey(), math.min(amt, 64)));
        amt -= 64;
      }
    }
    while (girderAmount > 0) {
      stacks.add(TrackItemStack(metalGirderKey, math.min(girderAmount, 64)));
      girderAmount -= 64;
    }
    return stacks;
  }

  @override
  TrackMaterial getMaterial() => material;
}

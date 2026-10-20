// `TrackTargetingBehaviour` (host): the behaviour a block entity uses to point at a position on a
// track - the station marker, a signal, a track observer. It resolves that position to an edge
// point of the track graph, keeps the point attached to the block entity, and writes the point's
// migration data when the target changes.
//
// Java -> Dart: the block entity is [owner] (`CreateBlockEntity`); `getWorld()` / `getPos()` are
// [owner]'s `world` / `pos`; `blockEntity.sendData()` / `notifyUpdate()` are [owner.sendData]. The
// client-only `render` overlay is not ported. `BehaviourType` has no counterpart: the behaviour id
// identifies it.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/data.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../contraptions/core/structure_transform.dart';
import '../../core/block_entity.dart';
import '../../api/block_state.dart';
import '../graph/dimension_palette.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_graph_helper.dart';
import '../graph/track_graph_location.dart';
import '../manager/create.dart';
import '../signal/single_block_entity_edge_point.dart';
import '../signal/track_edge_point.dart';
import '../support/ctag_host.dart';
import '../util/ctag.dart';
import '../util/uuid.dart';
import 'bezier_track_point_location.dart';
import 'i_track_block.dart';
import 'track_host.dart';
import 'track_targeting_data.dart';

class TrackTargetingBehaviour<T extends TrackEdgePoint>
    extends BlockEntityBehaviour {
  static const String behaviourId = 'TrackTargeting';

  @override
  String get id => behaviourId;

  final EdgePointType<T> edgePointType;

  /// The target position relative to the block entity (`targetTrack`).
  Pos targetTrack = posZero;

  /// The curve segment the target is on, `null` for a straight track.
  BezierTrackPointLocation? targetBezier;

  AxisDirection targetDirection = AxisDirection.positive;

  /// `id`: the uuid of the edge point. `id` is taken by [BlockEntityBehaviour], so the field keeps
  /// the Java name with an `edgePoint` prefix.
  String edgePointId = randomUuid();

  Vec3? prevDirection;
  Vec3? rotatedDirection;

  CTag? migrationData;
  T? edgePoint;
  bool orthogonal = false;

  TrackTargetingBehaviour(this.edgePointType);

  Pos get _pos => owner.pos.toPos();

  /// The world as the track logic sees it, `null` when the entity's world is gone.
  HostTrackLevel? get _trackLevel {
    final w = owner.world;
    return w == null ? null : HostTrackLevel(w, owner.store);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putIntArray('Id', uuidToInts(edgePointId));
    tag.putIntArray('TargetTrack', [
      targetTrack.$1,
      targetTrack.$2,
      targetTrack.$3,
    ]);
    tag.putBool('Ortho', orthogonal);
    tag.putBool('TargetDirection', targetDirection == AxisDirection.positive);
    final rotated = rotatedDirection;
    if (rotated != null) tag.putList('RotatedAxis', _vec3Tags(rotated));
    final prev = prevDirection;
    if (prev != null) tag.putList('PrevAxis', _vec3Tags(prev));
    final migrate = migrationData;
    if (migrate != null && !clientPacket) {
      tag.putCompound('Migrate', migrate.toHost());
    }
    final bezier = targetBezier;
    if (bezier != null) {
      final bezierTag = NbtCompound();
      bezierTag.putInt('Segment', bezier.segment);
      final key = bezier.curveTarget - _pos;
      bezierTag.putIntArray('Key', [key.$1, key.$2, key.$3]);
      tag.putCompound('Bezier', bezierTag);
    }
    super.write(tag, clientPacket: clientPacket);
  }

  static List<Object> _vec3Tags(Vec3 v) => [
    NbtTagDouble(v.$1),
    NbtTagDouble(v.$2),
    NbtTagDouble(v.$3),
  ];

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final uuidInts = tag.getIntArray('Id');
    edgePointId = uuidInts != null && uuidInts.length == 4
        ? uuidFromInts(uuidInts)
        : randomUuid();

    final track = tag.getIntArray('TargetTrack');
    targetTrack = track != null && track.length >= 3
        ? (track[0], track[1], track[2])
        : posZero;
    targetDirection = (tag.getBool('TargetDirection') ?? false)
        ? AxisDirection.positive
        : AxisDirection.negative;
    orthogonal = tag.getBool('Ortho') ?? false;

    final pure = tag.toCTag();
    if (pure.contains('PrevAxis')) prevDirection = pure.getVec3('PrevAxis');
    if (pure.contains('RotatedAxis')) {
      rotatedDirection = pure.getVec3('RotatedAxis');
    }

    final migrate = tag.getCompound('Migrate');
    if (migrate != null) migrationData = migrate.toCTag();

    if (clientPacket) edgePoint = null;

    final bezierTag = tag.getCompound('Bezier');
    if (bezierTag != null) {
      final key = bezierTag.getIntArray('Key');
      final keyPos = key != null && key.length >= 3
          ? (key[0], key[1], key[2])
          : posZero;
      targetBezier = BezierTrackPointLocation(
        keyPos + _pos,
        bezierTag.getInt('Segment') ?? 0,
      );
    }

    super.read(tag, clientPacket: clientPacket);
  }

  T? getEdgePoint() => edgePoint;

  void invalidateEdgePoint(CTag migrationData) {
    this.migrationData = migrationData;
    edgePoint = null;
    owner.sendData();
  }

  @override
  void tick() {
    super.tick();
    if (edgePoint == null) edgePoint = createEdgePoint();
  }

  /// `createEdgePoint()`: finds the point that already exists on the graph, or creates it from the
  /// targeted track position.
  T? createEdgePoint() {
    final level = _trackLevel;
    if (level == null) return null;

    if (migrationData == null) {
      for (final graph in Create.RAILWAYS.sided(level).trackNetworks.values) {
        final point = graph.getPoint(edgePointType, edgePointId);
        if (point == null) continue;
        return point;
      }
    }

    if (!hasValidTrack()) return null;
    final loc = determineGraphLocation();
    if (loc == null) return null;

    final graph = loc.graph;
    final node1 = graph.locateNode(loc.edge.getFirst());
    final node2 = graph.locateNode(loc.edge.getSecond());
    if (node1 == null || node2 == null) return null;
    final edge = graph.getConnectionsFrom(node1)[node2];
    if (edge == null) return null;

    final point = edgePointType.create();
    final front = getTargetDirection() == AxisDirection.positive;

    prevDirection = edge.getDirectionAt(loc.position) * (front ? -1 : 1);

    final rotated = rotatedDirection;
    if (rotated != null) {
      final dot = prevDirection!.dot(rotated);
      if (dot < -0.85) {
        rotatedDirection = null;
        targetDirection = targetDirection.opposite;
        return null;
      }
      rotatedDirection = null;
    }

    final length = edge.getLength();
    final data = migrationData;
    migrationData = null;

    orthogonal = targetBezier == null;
    final direction = edge.getDirection(true);
    var nonZeroComponents = 0;
    for (final axis in Iterate.axes) {
      if (axis.choose(direction.$1, direction.$2, direction.$3) != 0) {
        nonZeroComponents++;
      }
    }
    orthogonal = orthogonal && nonZeroComponents <= 1;

    final signalData = edge.getEdgeData();
    if (signalData.hasPoints()) {
      for (final otherType in EdgePointType.TYPES.values) {
        final otherPoint = signalData.get(otherType, loc.position);
        if (otherPoint == null) continue;
        if (otherType != edgePointType) {
          if (!otherPoint.canCoexistWith(edgePointType, front)) return null;
          continue;
        }
        if (!otherPoint.canMerge()) return null;
        otherPoint.blockEntityAdded(owner, front);
        edgePointId = otherPoint.getId();
        owner.sendData();
        return otherPoint as T;
      }
    }

    if (data != null) point.read(data, true, DimensionPalette.read(data));

    point.setId(edgePointId);
    final reverseEdge = front || point is SingleBlockEntityEdgePoint;
    point.setLocation(
      reverseEdge ? loc.edge : loc.edge.swap(),
      reverseEdge ? loc.position : length - loc.position,
    );
    point.blockEntityAdded(owner, front);
    loc.graph.addPoint(edgePointType, point);
    owner.sendData();
    return point;
  }

  /// `destroy()`.
  @override
  void onRemoved() {
    final point = edgePoint;
    final level = _trackLevel;
    if (point != null && level != null && !level.isClientSide) {
      point.blockEntityRemoved(
        _pos,
        getTargetDirection() == AxisDirection.positive,
      );
    }
  }

  bool isOnCurve() => targetBezier != null;

  bool isOrthogonal() => orthogonal;

  bool hasValidTrack() =>
      _trackLevel != null &&
      TrackBlockRegistry.ofState(getTrackBlockState()) != null;

  ITrackBlock? getTrack() => TrackBlockRegistry.ofState(getTrackBlockState());

  BState getTrackBlockState() =>
      _trackLevel?.stateAt(getGlobalPosition()) ?? BState.air;

  Pos getGlobalPosition() => resolvedTarget(_pos, targetTrack);

  /// `getPositionForMapMarker()`: the block position of the marker on the targeted curve.
  Pos getPositionForMapMarker() {
    final target = getGlobalPosition();
    final bezier = targetBezier;
    final level = _trackLevel;
    if (bezier != null && level != null) {
      final trackEntity = level.getTrackBlockEntity(target);
      if (trackEntity != null) {
        final bc = trackEntity.getConnections()[bezier.curveTarget];
        if (bc == null) return target;
        final length = (bc.getLength() * 2).floor();
        final seg = bezier.segment + 1;
        final t = seg / length;
        return posContaining(bc.getPosition(t));
      }
    }
    return target;
  }

  AxisDirection getTargetDirection() => targetDirection;

  BezierTrackPointLocation? getTargetBezier() => targetBezier;

  TrackGraphLocation? determineGraphLocation() {
    final level = _trackLevel;
    if (level == null) return null;
    final pos = getGlobalPosition();
    final state = getTrackBlockState();
    final track = TrackBlockRegistry.ofState(state);
    if (track == null) return null;
    final trackAxes = track.getTrackAxes(level, pos, state);
    if (trackAxes.isEmpty) return null;

    final bezier = targetBezier;
    return bezier != null
        ? TrackGraphHelper.getBezierGraphLocationAt(
            level,
            pos,
            targetDirection,
            bezier,
          )
        : TrackGraphHelper.getGraphLocationAt(
            level,
            pos,
            targetDirection,
            trackAxes[0],
          );
  }

  /// `transform(be, transform)` (`TransformableBlockEntity`).
  void transform(StructureTransform transform) {
    edgePointId = randomUuid();
    targetTrack = transform.applyPosWithoutOffset(targetTrack);
    final prev = prevDirection;
    if (prev != null) {
      rotatedDirection = transform.applyWithoutOffsetUncentered(prev);
    }
    final bezier = targetBezier;
    if (bezier != null) {
      final moved =
          transform.applyPosWithoutOffset(bezier.curveTarget - _pos) + _pos;
      targetBezier = BezierTrackPointLocation(moved, bezier.segment);
    }
    owner.sendData();
  }

  /// `RenderedTrackOverlayType`: the overlay the client draws for the block. Server side it only
  /// names the kind of target (kept for the block definitions).
}

/// `TrackTargetingBehaviour.RenderedTrackOverlayType`.
enum RenderedTrackOverlayType { station, signal, dualSignal, observer }

// `AirCurrent` and `IAirCurrentSource`: the stream of air an encased fan blows or sucks, its
// bounding box, the fan processing segments and the items and entities it moves.
// `content/kinetics/fan/AirCurrent.java`, `IAirCurrentSource.java`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../support/kinetics_bridge.dart';
import '../processing_runtime.dart';
import '../transport/transport_behaviours.dart';
import 'fan_processing.dart';

/// `IAirCurrentSource`: a block entity that emits an [AirCurrent] (the encased fan).
abstract interface class IAirCurrentSource {
  /// The current, `null` when there is none.
  AirCurrent? get airCurrent;

  /// The world the current is in, `null` when unloaded.
  World? get airCurrentWorld;

  /// The world id of [airCurrentWorld].
  String get airCurrentWorldId;

  /// `getAirCurrentPos`.
  Pos get airCurrentPos;

  /// `getSpeed`.
  double get speed;

  /// `getAirflowOriginSide`: the side the air leaves the source through.
  Dir get airflowOriginSide;

  /// `getAirFlowDirection`: `null` while the source does not turn.
  Dir? get airFlowDirection;

  /// `getMaxDistance`.
  double get maxDistance;

  /// `isSourceRemoved`.
  bool get isSourceRemoved;

  /// `source instanceof EncasedFanBlockEntity fan -> fan.award(FAN_PROCESSING)`
  /// (`AirCurrent.java:126,157`): the fan awards its owner when the current processed something.
  void onFanProcessed();
}

/// One stretch of the current with one processing type (`AirCurrentSegment`).
final class AirCurrentSegment {
  FanProcessingType? type;
  int startOffset = 0;
  int endOffset = 0;

  @override
  String toString() => 'segment($startOffset..$endOffset, ${type?.key})';
}

/// The air current of one fan.
final class AirCurrent {
  AirCurrent(this.source);

  final IAirCurrentSource source;

  Aabb bounds = const Aabb(0, 0, 0, 0, 0, 0);
  final List<AirCurrentSegment> segments = [];
  Dir? direction;
  bool pushing = false;
  double maxDistance = 0;

  final List<(TransportedItemStackHandlerBehaviour, FanProcessingType?)>
  affectedItemHandlers = [];
  List<EntitySnapshot> caughtEntities = const [];

  /// `tick`.
  void tick() {
    if (direction == null) rebuild();
    tickAffectedEntities();
    tickAffectedHandlers();
  }

  /// `tickAffectedEntities`.
  void tickAffectedEntities() {
    final world = source.airCurrentWorld;
    if (world == null) return;
    final dir = direction;
    if (dir == null) return;

    final kept = <EntitySnapshot>[];
    for (final snapshot in caughtEntities) {
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      final living = entity.asLiving();
      if (living != null && living.isDead()) continue;
      final bb = entity.getBoundingBox();
      final box = Aabb(
        bb.min.$1,
        bb.min.$2,
        bb.min.$3,
        bb.max.$1,
        bb.max.$2,
        bb.max.$3,
      );
      if (!box.intersects(bounds)) continue;

      final flow = pushing ? dir : dir.opposite;
      final speed = source.speed.abs();
      final sneakModifier = entity.isSneaking() ? 4096.0 : 512.0;
      final axisValue = dir.axis.chooseD(
        snapshot.position.$1,
        snapshot.position.$2,
        snapshot.position.$3,
      );
      final originValue = dir.axis.chooseD(
        source.airCurrentPos.x.toDouble(),
        source.airCurrentPos.y.toDouble(),
        source.airCurrentPos.z.toDouble(),
      );
      final entityDistance =
          (axisValue - (originValue + (dir.isPositive ? 1 : 0))).abs();
      final entityDistanceOld = _distance(
        snapshot.position,
        source.airCurrentPos.center,
      );
      final acceleration =
          speed / sneakModifier / (entityDistanceOld / maxDistance);
      final previous = entity.velocity;
      const maxAcceleration = 5.0;

      double axis(double f, double p) => (f * acceleration - p)
          .clamp(-maxAcceleration, maxAcceleration)
          .toDouble();
      final dx = axis(flow.dx.toDouble(), previous.$1);
      final dy = axis(flow.dy.toDouble(), previous.$2);
      final dz = axis(flow.dz.toDouble(), previous.$3);
      entity.velocity = (
        previous.$1 + dx / 8,
        previous.$2 + dy / 8,
        previous.$3 + dz / 8,
      );
      entity.fallDistance = 0;

      final type = getTypeAt(entityDistance);
      if (type == null) {
        kept.add(snapshot);
        continue;
      }

      final item = entity.asItem();
      if (item != null) {
        unawaited(() async {
          // `if (FanProcessing.applyProcessing(itemEntity, processingType)
          //  && source instanceof EncasedFanBlockEntity fan)
          //  fan.award(FAN_PROCESSING)` (`AirCurrent.java:124-126`).
          if (await FanProcessing.canProcess(item, type)) {
            if (await FanProcessing.applyProcessing(item, type)) {
              source.onFanProcessed();
            }
          }
        }());
        kept.add(snapshot);
        continue;
      }
      type.affectEntity(entity);
      kept.add(snapshot);
    }
    caughtEntities = kept;
  }

  static double _distance(Vec3 a, Vec3 b) {
    final dx = a.$1 - b.$1, dy = a.$2 - b.$2, dz = a.$3 - b.$3;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// `tickAffectedHandlers`.
  void tickAffectedHandlers() {
    for (final (handler, type) in affectedItemHandlers) {
      if (type == null) continue;
      handler.handleProcessingOnAllItems((transported) {
        final result = FanProcessing.applyProcessingTransported(
          transported,
          type,
        );
        // `if (!applyProcessing.doesNothing() && source instanceof EncasedFanBlockEntity fan)
        //  fan.award(FAN_PROCESSING)` (`AirCurrent.java:155-157`).
        if (!result.doesNothing) source.onFanProcessed();
        return result;
      });
    }
  }

  /// `rebuild`.
  void rebuild() {
    if (source.speed == 0) {
      maxDistance = 0;
      segments.clear();
      bounds = const Aabb(0, 0, 0, 0, 0, 0);
      return;
    }

    final dir = direction = source.airflowOriginSide;
    pushing = source.airFlowDirection == dir;
    final world = source.airCurrentWorld;
    final start = source.airCurrentPos;

    maxDistance = world == null
        ? source.maxDistance
        : getFlowLimit(world, start, source.maxDistance, dir);

    segments.clear();
    AirCurrentSegment? current;
    FanProcessingType? type;
    final limit = _limit;
    final searchStart = pushing ? 1 : limit;
    final searchEnd = pushing ? limit : 1;
    final step = pushing ? 1 : -1;
    final toOffset = pushing ? -1 : 0;

    for (var i = searchStart; i * step <= searchEnd * step; i += step) {
      final currentPos = _offset(start, dir, i);
      final newType = world == null
          ? null
          : FanProcessingTypes.at(world, currentPos.toBlockPos());
      if (newType != null) type = newType;
      if (current == null) {
        current = AirCurrentSegment()
          ..startOffset = i + toOffset
          ..type = type;
      } else if (current.type != type) {
        current.endOffset = i + toOffset;
        segments.add(current);
        current = AirCurrentSegment()
          ..startOffset = i + toOffset
          ..type = type;
      }
    }
    if (current != null) {
      current.endOffset = searchEnd + step + toOffset;
      segments.add(current);
    }

    if (maxDistance < .25) {
      bounds = const Aabb(0, 0, 0, 0, 0, 0);
    } else {
      final factor = maxDistance - 1;
      final base = Aabb.ofBlock(_offset(start, dir, 1));
      if (factor > 0) {
        bounds = base.expandTowards(
          dir.dx * factor,
          dir.dy * factor,
          dir.dz * factor,
        );
      } else {
        final sx = dir.dx * factor, sy = dir.dy * factor, sz = dir.dz * factor;
        bounds = _contract(base, sx, sy, sz).move(sx, sy, sz);
      }
    }

    findAffectedHandlers();
  }

  /// `AABB.contract`.
  static Aabb _contract(Aabb b, double x, double y, double z) {
    var minX = b.minX, minY = b.minY, minZ = b.minZ;
    var maxX = b.maxX, maxY = b.maxY, maxZ = b.maxZ;
    if (x < 0) {
      minX -= x;
    } else if (x > 0) {
      maxX -= x;
    }
    if (y < 0) {
      minY -= y;
    } else if (y > 0) {
      maxY -= y;
    }
    if (z < 0) {
      minZ -= z;
    } else if (z > 0) {
      maxZ -= z;
    }
    return Aabb(minX, minY, minZ, maxX, maxY, maxZ);
  }

  /// `getFlowLimit`.
  static double getFlowLimit(World world, Pos start, double max, Dir facing) {
    for (var i = 0; i < max; i++) {
      final current = _offset(start, facing, i + 1);
      final bp = current.toBlockPos();
      if (!world.isLoaded(pos: bp)) return i.toDouble();

      final state = world.getBlockState(pos: bp);
      if (Tags.block(state.blockName, 'create:fan_transparent')) continue;

      final shapes = state.collisionShapes;
      if (shapes.isEmpty) continue;
      if (state.isFullCube) return i.toDouble();

      final depth = _findMaxDepth(shapes, facing);
      if (depth.isInfinite) continue;
      final limit = i + depth + 1 / 32;
      return limit < max ? limit : max;
    }
    return max;
  }

  /// The five probe points of `AirCurrent.DEPTH_TEST_COORDINATES`.
  static const List<List<double>> _depthCoordinates = [
    [.25, .25],
    [.25, .75],
    [.5, .5],
    [.75, .25],
    [.75, .75],
  ];

  /// `findMaxDepth`: how far into the shape the current reaches, `infinity` when there is a hole.
  static double _findMaxDepth(List<BoundingBox> shape, Dir direction) {
    final axis = direction.axis;
    final others = [
      for (final a in KAxis.values)
        if (a != axis) a,
    ];
    final positive = direction.isPositive;
    var maxDepth = 0.0;

    double lo(BoundingBox b, KAxis a) =>
        a.chooseD(b.min.$1, b.min.$2, b.min.$3);
    double hi(BoundingBox b, KAxis a) =>
        a.chooseD(b.max.$1, b.max.$2, b.max.$3);

    for (final coords in _depthCoordinates) {
      final c1 = coords[0], c2 = coords[1];
      final a1 = others[0], a2 = others[1];
      double? best;
      for (final b in shape) {
        if (c1 < lo(b, a1) || c1 > hi(b, a1)) continue;
        if (c2 < lo(b, a2) || c2 > hi(b, a2)) continue;
        final v = positive ? lo(b, axis) : hi(b, axis);
        if (best == null || (positive ? v < best : v > best)) best = v;
      }
      if (best == null) return double.infinity;
      final depth = positive ? best : 1 - best;
      if (depth > maxDepth) maxDepth = depth;
    }
    return maxDepth;
  }

  int get _limit {
    final asInt = maxDistance.toInt();
    return asInt.toDouble() == maxDistance ? asInt : asInt + 1;
  }

  /// `findAffectedHandlers`: the belts and depots inside the current.
  void findAffectedHandlers() {
    final world = source.airCurrentWorld;
    final dir = direction;
    if (world == null || dir == null || !ProcessingRuntime.isLoaded) return;
    final rt = ProcessingRuntime.instance;
    final start = source.airCurrentPos;

    affectedItemHandlers.clear();
    final limit = _limit;
    for (var i = 1; i <= limit; i++) {
      final segmentType = getTypeAt((i - 1).toDouble());
      for (final offset in const [0, 1]) {
        final pos = _offset(_offset(start, dir, i), Dir.down, offset);
        final bp = pos.toBlockPos();
        final be = rt.store.at(source.airCurrentWorldId, bp);
        final behaviour = be
            ?.getBehaviour<TransportedItemStackHandlerBehaviour>();
        if (behaviour != null) {
          final type = FanProcessingTypes.at(world, bp) ?? segmentType;
          affectedItemHandlers.add((behaviour, type));
        }
        if (dir.axis.isVertical) break;
      }
    }
  }

  /// `findEntities`.
  void findEntities() {
    final world = source.airCurrentWorld;
    if (world == null) return;
    caughtEntities = world.getEntitiesInBox(
      min: bounds.minPos,
      max: bounds.maxPos,
      filter: const EntityFilterAll(),
    );
  }

  /// `getTypeAt`.
  FanProcessingType? getTypeAt(double offset) {
    if (offset < 0 || offset > maxDistance) return null;
    if (pushing) {
      for (final s in segments) {
        if (offset <= s.endOffset) return s.type;
      }
    } else {
      for (final s in segments) {
        if (offset >= s.endOffset) return s.type;
      }
    }
    return null;
  }

  static Pos _offset(Pos p, Dir d, int n) =>
      (p.x + d.dx * n, p.y + d.dy * n, p.z + d.dz * n);
}

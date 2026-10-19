// `NozzleBlock` / `NozzleBlockEntity`: the nozzle focuses a fan's air current into a narrow
// stream. `content/kinetics/fan/NozzleBlock.java`, `NozzleBlockEntity.java`.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import '../processing_runtime.dart';
import 'air_current.dart';

/// `NozzleBlockEntity`.
final class NozzleBlockEntity extends CreateBlockEntity {
  NozzleBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 5;
  }

  /// The ids of the entities the nozzle pushes (`pushingEntities`).
  final List<int> pushingEntities = [];

  /// `range`.
  double range = 0;

  /// `pushing`.
  bool pushing = false;

  /// `fanPos`.
  Pos? fanPos;

  Dir _facing() {
    final w = world;
    if (w == null) return Dir.north;
    final state = w.getBlockState(pos: pos);
    for (final (k, v) in state.properties) {
      if (k == 'facing') return Dir.fromName(v) ?? Dir.north;
    }
    return Dir.north;
  }

  @override
  void initialize() {
    fanPos = _offset(pos.toPos(), _facing().opposite, 1);
    super.initialize();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (!clientPacket) return;
    tag.putFloat('Range', range);
    tag.putBool('Pushing', pushing);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (!clientPacket) return;
    range = tag.getDouble('Range') ?? 0;
    pushing = tag.getBool('Pushing') ?? false;
  }

  @override
  void tick() {
    super.tick();

    final r = _calcRange();
    if (range != r) setRange(r);

    final w = world;
    if (w == null || range <= 0) return;
    final centre = pos.toPos().center;

    for (final id in List.of(pushingEntities)) {
      final entity = w.getEntityById(id: id);
      if (entity == null) {
        pushingEntities.remove(id);
        continue;
      }
      final diff = _sub(entity.position, centre);
      final distance = _length(diff);
      if (distance > range || entity.isSneaking()) {
        pushingEntities.remove(id);
        continue;
      }
      if (!pushing && distance < 1.5) continue;

      final factor = entity.asItem() != null ? 1 / 128 : 1 / 32;
      final push = _scale(
        _normalize(diff),
        (range - distance) * (pushing ? 1 : -1),
      );
      entity.velocity = _add(entity.velocity, _scale(push, factor));
      entity.fallDistance = 0;
    }
  }

  /// `setRange`.
  void setRange(double value) {
    range = value;
    if (value == 0) pushingEntities.clear();
    sendData();
  }

  /// `calcRange`.
  double _calcRange() {
    final w = world;
    final fp = fanPos;
    if (w == null || fp == null || !ProcessingRuntime.isLoaded) return 0;
    final be = ProcessingRuntime.instance.store.at(worldId, fp.toBlockPos());
    if (be is! IAirCurrentSource) return 0;
    final source = be as IAirCurrentSource;
    if (source.airCurrent == null || source.speed == 0) return 0;
    pushing = source.airFlowDirection == source.airflowOriginSide;
    return source.maxDistance;
  }

  @override
  void lazyTick() {
    super.lazyTick();

    final w = world;
    if (w == null || range == 0) return;
    final centre = pos.toPos().center;
    final r = range / 2;

    final snapshots = w.getEntitiesInBox(
      min: (centre.$1 - r, centre.$2 - r, centre.$3 - r),
      max: (centre.$1 + r, centre.$2 + r, centre.$3 + r),
      filter: const EntityFilterAll(),
    );
    for (final snapshot in snapshots) {
      final diff = _sub(snapshot.position, centre);
      final distance = _length(diff);
      if (distance > range) continue;
      final entity = w.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      if (entity.isSneaking()) continue;
      if (!_canSee(w, snapshot.position)) {
        pushingEntities.remove(snapshot.id);
        continue;
      }
      if (!pushingEntities.contains(snapshot.id)) {
        pushingEntities.add(snapshot.id);
      }
    }

    for (final id in List.of(pushingEntities)) {
      final entity = w.getEntityById(id: id);
      if (entity == null) {
        pushingEntities.remove(id);
        continue;
      }
      final living = entity.asLiving();
      if (living != null && living.isDead()) pushingEntities.remove(id);
    }

    if (!pushing && pushingEntities.length > 256) {
      w.createExplosion(
        pos: centre,
        power: 2,
        createFire: false,
        interaction: ExplosionInteraction.none,
      );
      for (final id in List.of(pushingEntities)) {
        w.getEntityById(id: id)?.remove();
        pushingEntities.remove(id);
      }
    }
  }

  /// `canSee`.
  bool _canSee(World world, Vec3 from) {
    final centre = pos.toPos().center;
    final hit = world.rayTraceBlock(
      start: from,
      end: centre,
      includeFluids: false,
    );
    return hit != null &&
        hit.pos.x == pos.x &&
        hit.pos.y == pos.y &&
        hit.pos.z == pos.z;
  }

  static Pos _offset(Pos p, Dir d, int n) =>
      (p.x + d.dx * n, p.y + d.dy * n, p.z + d.dz * n);
  static Vec3 _sub(Vec3 a, Vec3 b) => (a.$1 - b.$1, a.$2 - b.$2, a.$3 - b.$3);
  static Vec3 _add(Vec3 a, Vec3 b) => (a.$1 + b.$1, a.$2 + b.$2, a.$3 + b.$3);
  static Vec3 _scale(Vec3 a, double k) => (a.$1 * k, a.$2 * k, a.$3 * k);
  static double _length(Vec3 a) =>
      math.sqrt(a.$1 * a.$1 + a.$2 * a.$2 + a.$3 * a.$3);
  static Vec3 _normalize(Vec3 a) {
    final l = _length(a);
    return l == 0 ? a : _scale(a, 1 / l);
  }
}

/// `AllShapes.NOZZLE.forDirectional()`: a 12x14x12 tube with a wider ring near the mouth.
List<ShapeRule> nozzleRules() => [
  for (final d in Direction.values)
    ShapeRule(
      when: {'facing': d.serializedName},
      collisionShape: BlockShape.boxes([
        _orientedBox(2, 0, 2, 14, 14, 14, d),
        _orientedBox(1, 13, 1, 15, 15, 15, d),
      ]),
      selectionShape: BlockShape.boxes([
        _orientedBox(2, 0, 2, 14, 14, 14, d),
        _orientedBox(1, 13, 1, 15, 15, 15, d),
      ]),
    ),
];

/// `VoxelShaper.forDirectional`: [u], [t] and [v] in 16ths, [t] runs from the back to the front
/// along [facing].
BlockBox _orientedBox(
  double u0,
  double t0,
  double v0,
  double u1,
  double t1,
  double v1,
  Direction facing,
) {
  final axis = facing.axis;
  final others = [
    for (final a in Axis.values)
      if (a != axis) a,
  ];
  final ua = others[0], va = others[1];
  var a0 = t0 / 16, a1 = t1 / 16;
  if (facing.axisDirection == AxisDirection.negative) {
    final t = 1 - a1;
    a1 = 1 - a0;
    a0 = t;
  }
  final lo = <Axis, double>{ua: u0 / 16, va: v0 / 16, axis: a0};
  final hi = <Axis, double>{ua: u1 / 16, va: v1 / 16, axis: a1};
  return BlockBox(
    lo[Axis.x]!,
    lo[Axis.y]!,
    lo[Axis.z]!,
    hi[Axis.x]!,
    hi[Axis.y]!,
    hi[Axis.z]!,
  );
}

/// `NozzleBlock.canSurvive`: the block behind the nozzle must be an air current source whose
/// origin side points at the nozzle.
bool nozzleCanSurvive(World world, BlockPos pos) {
  if (!ProcessingRuntime.isLoaded) return true;
  final state = world.getBlockState(pos: pos);
  Dir facing = Dir.north;
  for (final (k, v) in state.properties) {
    if (k == 'facing') facing = Dir.fromName(v) ?? Dir.north;
  }
  final towardsFan = facing.opposite;
  final worldId = ProcessingRuntime.instance.worlds.touch(world);
  final be = ProcessingRuntime.instance.store.at(
    worldId,
    _offset(pos.toPos(), towardsFan, 1).toBlockPos(),
  );
  return be is IAirCurrentSource &&
      (be as IAirCurrentSource).airflowOriginSide == towardsFan.opposite;
}

/// The block and block entity type of the nozzle.
CreateBlock nozzleBlock() => createBlockFromManifest(
  'nozzle',
  blockEntityType: 'create:nozzle',
  shapeRules: nozzleRules(),
  placement: const [PlacementRule.clickedFace('facing')],
  behavior: BlockBehavior(
    onCanPlace: (server, e) => nozzleCanSurvive(e.targetWorld, e.pos),
    onNeighborUpdate: (server, e) async {
      if (nozzleCanSurvive(e.targetWorld, e.pos)) return;
      await e.targetWorld.destroyBlock(
        pos: e.pos,
        drop: true,
        player: null,
        withParticles: true,
      );
    },
    isPathfindable: (server, e) => false,
  ),
);

Pos _offset(Pos p, Dir d, int n) =>
    (p.x + d.dx * n, p.y + d.dy * n, p.z + d.dz * n);

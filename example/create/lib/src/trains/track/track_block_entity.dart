// `TrackBlockEntity` (pure): the curves leaving a track block, its tilt and the portal it is bound
// to. The host block entity (`track_host.dart`, `TrackBlockEntityHost`) owns one of these and
// forwards its lifecycle; everything the Java class does is here, against [TrackLevel].
//
// Java -> Dart: the methods that change blocks (`addConnection`, `removeConnection`, ...) are
// `Future`s that finish when the blocks were written; `connections` is `Map<Pos, BezierConnection>`
// (insertion ordered); `level` is [getLevel] and `getBlockState()` reads [TrackLevel.stateAt].
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../contraptions/core/structure_transform.dart';
import '../../core/nbt.dart' show NbtKind;
import '../graph/track_node_location.dart';
import '../util/ctag.dart';
import 'bezier_connection.dart';
import 'fake_track_block.dart';
import 'i_track_block.dart';
import 'track_block_entity_tilt.dart';
import 'track_level.dart';

/// What a [TrackBlockEntity] needs from the block entity that owns it.
abstract interface class TrackBlockEntityEnv {
  /// The world the block entity is in, `null` when it is gone.
  TrackLevel? get level;

  /// `setChanged()` + `sendData()` (`SmartBlockEntity.notifyUpdate`).
  void notifyUpdate();

  /// `setChanged()`.
  void setChanged();

  /// `isRemoved()`.
  bool get isRemoved;
}

class TrackBlockEntity {
  final Pos worldPosition;
  final TrackBlockEntityEnv env;

  Map<Pos, BezierConnection> connections = <Pos, BezierConnection>{};
  bool cancelDrops = false;

  /// `boundLocation`: the dimension and position of the portal track on the other side.
  Pair<String, Pos>? boundLocation;
  late final TrackBlockEntityTilt tilt;

  TrackBlockEntity(this.worldPosition, this.env) {
    tilt = TrackBlockEntityTilt(this);
  }

  /// `getLevel()`.
  TrackLevel? getLevel() => env.level;

  /// `getBlockPos()`.
  Pos getBlockPos() => worldPosition;

  /// `getBlockState()`.
  BState getBlockState() => getLevel()?.stateAt(worldPosition) ?? BState.air;

  /// `isRemoved()`.
  bool get isRemoved => env.isRemoved;

  /// `notifyUpdate()`.
  void notifyUpdate() => env.notifyUpdate();

  /// `setChanged()`.
  void setChanged() => env.setChanged();

  Map<Pos, BezierConnection> getConnections() => connections;

  /// `setLazyTickRate(100)`.
  static const int lazyTickRate = 100;

  /// `tick()`.
  Future<void> tick() => tilt.undoSmoothing();

  /// `lazyTick()`.
  Future<void> lazyTick() async {
    for (final connection in connections.values.toList()) {
      if (connection.isPrimary()) await manageFakeTracksAlong(connection, false);
    }
  }

  /// `validateConnections()`.
  Future<void> validateConnections() async {
    final level = getLevel();
    if (level == null) return;
    final invalid = <Pos>{};

    for (final entry in connections.entries.toList()) {
      final key = entry.key;
      final bc = entry.value;

      if (key != bc.getKey() || worldPosition != bc.bePositions.getFirst()) {
        invalid.add(key);
        continue;
      }

      final blockState = level.stateAt(key);
      final trackBlock = TrackBlockRegistry.ofState(blockState);
      if (trackBlock != null && !hasBe(blockState)) {
        for (final v in trackBlock.getTrackAxes(level, key, blockState)) {
          final bcEndAxis = bc.axes.getSecond();
          if (v.distanceTo(bcEndAxis) < toFloat(1 / 1024) || v.distanceTo(bcEndAxis * -1) < toFloat(1 / 1024)) {
            await level.setBlock(key, withHasBe(blockState, true));
          }
        }
      }

      final trackBE = level.getTrackBlockEntity(key);
      if (trackBE == null || trackBE.isRemoved) {
        invalid.add(key);
        continue;
      }

      if (!trackBE.connections.containsKey(worldPosition)) {
        await trackBE.addConnection(bc.secondary());
        await trackBE.tilt.tryApplySmoothing();
      }
    }

    for (final blockPos in invalid) {
      await removeConnection(blockPos);
    }
  }

  /// `addConnection(connection)`.
  Future<void> addConnection(BezierConnection connection) async {
    // don't replace existing connections with different materials
    final existing = connections[connection.getKey()];
    if (existing != null && connection.equalsSansMaterial(existing)) return;
    connections[connection.getKey()] = connection;
    final level = getLevel();
    level?.scheduleTick(worldPosition, level.stateAt(worldPosition).key, 1);
    notifyUpdate();

    if (connection.isPrimary()) await manageFakeTracksAlong(connection, false);
  }

  /// `removeConnection(target)`.
  Future<void> removeConnection(Pos target) async {
    if (isTilted()) tilt.captureSmoothingHandles();

    final removed = connections.remove(target);
    notifyUpdate();

    if (removed != null) await manageFakeTracksAlong(removed, true);

    final level = getLevel();
    if (level == null) return;
    final state = getBlockState();
    if (connections.isNotEmpty || (state.has(trackShapeProperty) && trackShapeOf(state).isPortal())) return;

    final blockState = level.stateAt(worldPosition);
    if (blockState.has(trackHasBeProperty)) {
      await level.setBlockAndUpdate(worldPosition, withHasBe(blockState, false));
    }
    level.sendRemoveBlockEntity(worldPosition);
  }

  /// `removeInboundConnections(dropAndDiscard)`.
  Future<void> removeInboundConnections(bool dropAndDiscard) async {
    final level = getLevel();
    if (level == null) return;
    for (final bezierConnection in connections.values.toList()) {
      final tbe = level.getTrackBlockEntity(bezierConnection.getKey());
      if (tbe == null) return;
      await tbe.removeConnection(bezierConnection.bePositions.getFirst());
      if (!dropAndDiscard) continue;
      if (!cancelDrops) bezierConnection.spawnItems(level);
      bezierConnection.spawnDestroyParticles(level);
    }
    if (dropAndDiscard) level.sendRemoveBlockEntity(worldPosition);
  }

  /// `bind(boundDimension, boundLocation)`.
  void bind(String boundDimension, Pos boundLocation) {
    this.boundLocation = Pair<String, Pos>(boundDimension, boundLocation);
    setChanged();
  }

  bool isTilted() => tilt.smoothingAngle != null;

  /// `writeSafe(tag)`: the NBT that is safe to copy (schematics): the curves in their untilted form.
  void writeSafe(CTag tag) {
    _writeTurns(tag, true);
  }

  /// `write(tag, clientPacket)`.
  void write(CTag tag, {required bool clientPacket}) {
    _writeTurns(tag, false);
    if (isTilted()) tag.putDouble('Smoothing', tilt.smoothingAngle!);
    final bound = boundLocation;
    if (bound == null) return;
    tag.putBlockPos('BoundLocation', bound.getSecond());
    tag.putString('BoundDimension', bound.getFirst());
  }

  void _writeTurns(CTag tag, bool restored) {
    final list = <CTag>[];
    for (final bezierConnection in connections.values) {
      list.add((restored ? tilt.restoreToOriginalCurve(bezierConnection.clone()) : bezierConnection).write(worldPosition));
    }
    tag.putCompoundList('Connections', list);
  }

  /// `read(tag, clientPacket)`.
  void read(CTag tag, {required bool clientPacket}) {
    connections.clear();
    for (final t in tag.getList('Connections')) {
      if (t.kind != NbtKind.compound) return;
      final connection = BezierConnection.fromTag(CTag.fromNbt(t), worldPosition);
      connections[connection.getKey()] = connection;
    }

    tilt.smoothingAngle = tag.contains('Smoothing') ? tag.getDouble('Smoothing') : null;

    if (tag.contains('BoundLocation')) {
      boundLocation = Pair<String, Pos>(tag.getString('BoundDimension'), tag.getBlockPos('BoundLocation'));
    }
  }

  /// `accept(other)` (`IMergeableBE`).
  Future<void> accept(TrackBlockEntity other) async {
    connections.addAll(other.connections);
    await validateConnections();
    final level = getLevel();
    level?.scheduleTick(worldPosition, level.stateAt(worldPosition).key, 1);
  }

  /// `hasInteractableConnections()`.
  bool hasInteractableConnections() {
    for (final connection in connections.values) {
      if (connection.isPrimary()) return true;
    }
    return false;
  }

  /// `transform(be, transform)` (`TransformableBlockEntity`).
  void transform(StructureTransform transform) {
    final restoredConnections = <Pos, BezierConnection>{};
    for (final entry in connections.entries) {
      restoredConnections[entry.key] = tilt.restoreToOriginalCurve(
        tilt.restoreToOriginalCurve(entry.value.secondary()).secondary(),
      );
    }
    connections = restoredConnections;
    tilt.smoothingAngle = null;

    if (transform.rotationAxis != Axis.y) return;

    final transformedConnections = <Pos, BezierConnection>{};
    for (final entry in connections.entries) {
      final newConnection = entry.value;
      newConnection.normals.replace(transform.applyWithoutOffsetUncentered);
      newConnection.axes.replace(transform.applyWithoutOffsetUncentered);

      final diff = newConnection.bePositions.getSecond() - newConnection.bePositions.getFirst();
      newConnection.bePositions.setSecond(
        posContaining(newConnection.bePositions.getFirst().center + transform.applyWithoutOffsetUncentered(diff.toVec3())),
      );

      final beVec = worldPosition.toVec3();
      final teCenterVec = beVec + (0.5, 0.5, 0.5);
      final start = newConnection.starts.getFirst();
      var startToBE = start - teCenterVec;
      var endToStart = newConnection.starts.getSecond() - start;
      startToBE = transform.applyWithoutOffsetUncentered(startToBE) + teCenterVec;
      endToStart = transform.applyWithoutOffsetUncentered(endToStart) + startToBE;

      newConnection.starts.setFirst(TrackNodeLocation.fromVec(startToBE).getLocation());
      newConnection.starts.setSecond(TrackNodeLocation.fromVec(endToStart).getLocation());

      final newTarget = newConnection.getKey();
      transformedConnections[newTarget] = newConnection;
    }

    connections = transformedConnections;
  }

  /// `remove()`: the block entity was removed for good (the block was broken or replaced).
  Future<void> remove() async {
    for (final connection in connections.values.toList()) {
      await manageFakeTracksAlong(connection, true);
    }

    final bound = boundLocation;
    final level = getLevel();
    if (bound != null && level != null) {
      final otherLevel = level.getLevel(bound.getFirst());
      if (otherLevel == null) return;
      if (TrackBlockRegistry.isTrack(otherLevel.stateAt(bound.getSecond()))) {
        await otherLevel.destroyBlock(bound.getSecond(), false);
      }
    }
  }

  /// `manageFakeTracksAlong(bc, remove)`: the invisible blocks that keep entities off the curve.
  Future<void> manageFakeTracksAlong(BezierConnection bc, bool remove) async {
    final level = getLevel();
    if (level == null) return;
    final yLevels = bc.rasterise();

    for (final entry in yLevels.entries) {
      final yValue = entry.value;
      final floor = yValue.floor();
      final origin = bc.bePositions.getFirst();
      final targetPos = (entry.key.first + origin.x, floor + origin.y + 1, entry.key.second + origin.z);

      final stateAtPos = level.stateAt(targetPos);
      final present = stateAtPos.key == fakeTrackKey;

      if (remove) {
        if (present) await level.removeBlock(targetPos);
        continue;
      }

      if (level.hasNonWaterFluid(targetPos)) continue;

      if (!present && level.canBeReplaced(targetPos)) {
        await level.setBlock(targetPos, withWater(level, fakeTrackDefaultState, targetPos)!);
      }
      FakeTrackBlock.keepAlive(level, targetPos);
    }
  }
}

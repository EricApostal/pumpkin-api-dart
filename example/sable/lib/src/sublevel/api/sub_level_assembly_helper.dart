// `dev.ryanhcode.sable.api.SubLevelAssemblyHelper`: mass movement of blocks
// between the world and a sub-level plot.
//
// The Java class talks to `ServerLevel` directly. The port writes through two
// host seams:
//
//  * [AssemblyBlockHost] for block states and block-entity data (the plugin's
//    chunk host implements it; the plain `PlotChunkHost` fallback can only move
//    block keys, and refuses to move block-entity data);
//  * [AssemblyEntityHost] for the entities inside the bounds.
//
// Everything else (the flood fill, the transform, the tracking-point move) is
// pure and runs on the VM in tests.
//
// Pure: no host imports.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:collection';
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:create/src/common/pos.dart' show Pos;

import '../host/sub_level_host.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../model/sub_level.dart';
import '../model/sub_level_container.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../storage/sub_level_saved_data.dart';
import '../tracking_points/tracking_point.dart';
import '../util/bounded_bit_volume3i.dart';
import 'block/block_sub_level_assembly_listener.dart';
import '../system/physics_system.dart';
import 'sub_level_helper.dart';

/// The block and block-entity access the assembly needs from the host.
abstract interface class AssemblyBlockHost {
  /// The state at the global block position.
  BState blockStateAt(int x, int y, int z);

  /// Writes the state at the global block position.
  void setBlockStateAt(int x, int y, int z, BState state);

  /// The saved block-entity data at the position, or `null`.
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z);

  /// Writes block-entity data at the position.
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data);

  /// Removes the block entity at the position.
  void removeBlockEntityAt(int x, int y, int z);

  /// Notifies the level that the block changed (neighbour updates, clients).
  void notifyBlockChanged(int x, int y, int z, BState oldState, BState newState);
}

/// A block host that can cache its reads for one batch of queries.
///
/// The structure search asks for the same position many times (every block of
/// the frontier re-reads its 18 neighbours), and a host whose reads cross a
/// boundary — a plugin host calling the server per block — pays for each of them.
/// A host that implements this turns the batch into one cached pass; the search
/// stays identical.
abstract interface class BatchingBlockHost {
  /// Starts caching reads.
  void beginBatch();

  /// Stops caching and drops the cache.
  void endBatch();
}

/// A block host that can answer a whole batch of reads in one host call
/// (`World.get-block-states`).
///
/// [BatchingBlockHost] removes the *repeat* reads within one search, but the
/// first read of every position is still a host call: a walk over terrain reads
/// ~18 positions per collected block, and each call costs a wasm boundary
/// crossing (~4 us measured on a live server), so a search of tens of thousands
/// of blocks stalls the tick loop. A host that implements this lets the search
/// read a whole frontier — thousands of positions — in one call.
abstract interface class BulkBlockHost {
  /// Reads the states at [positions] in one host call. The result has one entry
  /// per position, in the same order; a position in an unloaded chunk reads as
  /// [BState.air] (the host does not load a chunk for a read).
  List<BState> readBlockStates(List<Pos> positions);
}

/// An entity the assembly moves when it sits on a moved block.
abstract interface class AssemblyEntity {
  /// The entity position.
  Vector3d get position;

  /// The blocks that support the entity (hanging entities), or `null`.
  BoundingBox3ic? get supportBox;

  /// Moves the entity.
  void setPosition(Vector3d position);
}

/// The entity query the assembly needs from the host.
abstract interface class AssemblyEntityHost {
  /// Every entity inside [bounds].
  List<AssemblyEntity> entitiesIn(BoundingBox3dc bounds);
}

/// Utility class for mass movement of collections of blocks between world and
/// plot.
abstract final class SubLevelAssemblyHelper {
  /// The block keys that get their block entity removed silently
  /// (`SableTags.SILENT_ASSEMBLY_REMOVAL`); filled in by the plugin's tags.
  static final Set<String> silentAssemblyRemoval = {};

  /// The assembly listeners, by block key.
  static final Map<String, BlockSubLevelAssemblyListener> assemblyListeners = {};

  /// Registers the listener of [blockKey].
  static void registerListener(String blockKey, BlockSubLevelAssemblyListener listener) =>
      assemblyListeners[blockKey] = listener;

  /// Removes the listener of [blockKey].
  static void unregisterListener(String blockKey) => assemblyListeners.remove(blockKey);

  /// Assembles [blocks] into a new sub-level of [level].
  ///
  /// [anchor] becomes the centre of the sub-level; [bounds] is the volume whose
  /// tracking points and entities move with it.
  static ServerSubLevel assembleBlocks(
    SableLevel level,
    Pos anchor,
    Iterable<Pos> blocks,
    BoundingBox3ic bounds,
  ) {
    final container = SubLevelContainer.of(level);
    if (container == null) {
      throw StateError('Level ${level.dimensionId} has no sub-level container');
    }

    final physics = container is ServerSubLevelContainer && container.physics is SubLevelPhysicsSystem
        ? container.physics as SubLevelPhysicsSystem
        : null;

    final containingSubLevel = SubLevelHelper.getContaining(level, anchor);
    final pose = Pose3d();
    pose.position().set(anchor.$1 + 0.5, anchor.$2 + 0.5, anchor.$3 + 0.5);

    final containingAngularVelocity = Vector3d();
    final containingLinearVelocity = Vector3d();
    Pose3d? containingPose;

    if (containingSubLevel != null) {
      if (containingSubLevel.isRemoved()) {
        throw StateError('Sub-level assembly attempted inside plot of already removed sub-level');
      }

      containingPose = Pose3d.copy(containingSubLevel.logicalPose);
      pose.position().setFrom(containingPose.transformPosition(pose.position()));
      pose.orientation().setFrom(containingPose.orientation());

      if (physics != null && containingSubLevel is ServerSubLevel) {
        final containingHandle = physics.getPhysicsHandle(containingSubLevel);
        containingHandle.getLinearVelocity(containingLinearVelocity);
        containingHandle.getAngularVelocity(containingAngularVelocity);
      }
    }

    final subLevel = container.allocateNewSubLevel(pose);
    if (subLevel is! ServerSubLevel) {
      throw StateError(
        'SubLevelAssemblyHelper needs a ServerSubLevelContainer; '
        '${level.dimensionId} allocated a ${subLevel.runtimeType}.',
      );
    }

    final plot = subLevel.getPlot();
    plot.newEmptyChunk(plot.getCenterChunk());

    final plotAnchor = plot.getCenterBlock();
    final transform = AssemblyTransform(anchor, plotAnchor, 0, Rotation.none, level);
    moveOtherStuff(level, transform, blocks, bounds);
    moveBlocks(level, transform, blocks);

    // Java's `getMassTracker().getCenterOfMass()` returns `null` for an empty
    // tracker and the else branch below handles it; this port's getter *throws*
    // instead, which turned "the selection had no solid block" into a raw
    // `StateError` out of the command (`/sable assemble cube` over air).
    final tracker = subLevel.massTracker;
    final centerOfMass = tracker == null || tracker.isInvalid() ? null : tracker.getCenterOfMass();
    var subLevelCenter = Vector3d(anchor.$1.toDouble(), anchor.$2.toDouble(), anchor.$3.toDouble());

    if (centerOfMass != null) {
      subLevelCenter = subLevelCenter
          .sub(Vector3d(plotAnchor.$1.toDouble(), plotAnchor.$2.toDouble(), plotAnchor.$3.toDouble()))
          .add(centerOfMass);
      // `MergedMassTracker.uploadData` (`MergedMassTracker.java:105-126`) sets the
      // rotation point to the centre of mass; Java's next physics tick does it for
      // an assembly, the port did not, and a pose with a zero rotation point
      // rotates the plot bounds (~20M blocks out) about the world origin — a
      // `/sable physics rotation` then threw the sub-level's global bounds to
      // 28.9M and the ticket manager unloaded it.
      subLevel.logicalPose.rotationPoint().setFrom(centerOfMass);
    } else {
      subLevel.logicalPose.rotationPoint().set(
        plotAnchor.$1 + 0.5,
        plotAnchor.$2 + 0.5,
        plotAnchor.$3 + 0.5,
      );
    }

    subLevel.logicalPose.position().setFrom(subLevelCenter);

    if (containingSubLevel != null && physics != null) {
      kickFromContainingSubLevel(
        physics,
        subLevel,
        containingLinearVelocity,
        containingAngularVelocity,
        containingPose!,
        containingSubLevel.isRemoved() ? null : containingSubLevel,
      );
    }

    if (!subLevel.isRemoved() && physics != null) {
      physics.getPipeline().teleport(
        physics.getPhysicsHandle(subLevel),
        subLevel.logicalPose.position(),
        subLevel.logicalPose.orientation(),
      );
    }

    subLevel.updateLastPose();

    moveTrackingPoints(level, bounds, subLevel, transform);

    return subLevel;
  }

  /// Kicks [subLevel] out of [containingSubLevel], preserving its velocity.
  static void kickFromContainingSubLevelSystem(
    SubLevelPhysicsSystem physicsSystem,
    ServerSubLevel subLevel,
    ServerSubLevel containingSubLevel,
  ) {
    final containingHandle = physicsSystem.getPhysicsHandle(containingSubLevel);
    final linearVelocity = containingHandle.getLinearVelocity();
    final angularVelocity = containingHandle.getAngularVelocity();
    final containingPose = Pose3d.copy(containingSubLevel.logicalPose);

    kickFromContainingSubLevel(
      physicsSystem,
      subLevel,
      linearVelocity,
      angularVelocity,
      containingPose,
      containingSubLevel,
    );
  }

  /// The core of [kickFromContainingSubLevelSystem].
  static void kickFromContainingSubLevel(
    SubLevelPhysicsSystem physicsSystem,
    ServerSubLevel subLevel,
    Vector3d containingLinearVelocity,
    Vector3d containingAngularVelocity,
    Pose3d containingPose,
    SubLevel? containingSubLevel,
  ) {
    final originalPose = Pose3d.copy(subLevel.logicalPose);

    // Re-transform after the centre of mass is fixed; the orientation cannot
    // have changed.
    subLevel.logicalPose.position().setFrom(
      containingPose.transformPosition(subLevel.logicalPose.position()),
    );

    // `SubLevelAssemblyHelper.java:172`: Java computes the offset into a fresh
    // `Vector3d` (`sub(other, new Vector3d())`); the Dart `sub` mutates its
    // receiver, which here is the sub-level's own position vector.
    final localPos = subLevel.logicalPose.position().subInto(containingPose.position(), Vector3d());
    if (!subLevel.isRemoved()) {
      // `SubLevelAssemblyHelper.java:174`: the linear velocity is
      // `ω × r + v`, and the angular velocity stays `ω`. Java writes the cross
      // product into `localPos`, leaving `containingAngularVelocity` untouched;
      // the Dart `cross`/`add` mutate their receiver, so the sum goes into a
      // temp and `containingAngularVelocity` is passed unchanged.
      final velocity = containingAngularVelocity.crossInto(localPos, Vector3d())
        ..add(containingLinearVelocity);
      physicsSystem.getPipeline().addLinearAndAngularVelocity(
        physicsSystem.getPhysicsHandle(subLevel),
        velocity,
        containingAngularVelocity,
      );
    }

    if (containingSubLevel is ServerSubLevel) {
      subLevel.setSplitFrom(containingSubLevel, originalPose);
    }
  }

  /// Gathers all connected blocks from [gatherOrigin].
  ///
  /// Searches the 26 neighbours of every block but only connects through edges
  /// and faces, not corners.
  static GatherResult gatherConnectedBlocks(
    Pos gatherOrigin,
    SableLevel level,
    int maximumBlocksToAssemble,
    FrontierPredicate? frontierPredicate,
  ) {
    final host = _blockHostOf(level);

    // A host that answers a whole wave of reads in one host call ([BulkBlockHost])
    // needs no read cache: the walk reads each position once, through the wave
    // batch. A host that reads per query uses the cache of [BatchingBlockHost],
    // which turns the ~18 repeat reads of every position into one call.
    final BatchingBlockHost? batching = host is BulkBlockHost
        ? null
        : host is BatchingBlockHost
            ? host as BatchingBlockHost
            : null;

    if (batching == null) {
      return _gatherConnected(host, gatherOrigin, maximumBlocksToAssemble, frontierPredicate, null);
    }

    batching.beginBatch();
    try {
      return _gatherConnected(host, gatherOrigin, maximumBlocksToAssemble, frontierPredicate, batching);
    } finally {
      batching.endBatch();
    }
  }

  /// Whether the gather connects from a block to its neighbour `(x, y, z)` away:
  /// the 26 neighbours except the block itself, minus the 8 corners.
  static bool _connects(int x, int y, int z) =>
      !(x == 0 && y == 0 && z == 0) && x.abs() + y.abs() + z.abs() != 3;

  /// Packs the position `(x, y, z)` into one int key, relative to the gather
  /// origin, so membership in the walk's "already known" set is a Smi hash
  /// lookup instead of a three-field record hash.
  ///
  /// That matters: the walk asks about the ~18 neighbours of every position it
  /// dequeues, and a `Set<(int, int, int)>` in dart2wasm costs microseconds per
  /// question — measured on a live server, the set lookups of the neighbour scan
  /// cost 48 s of the 90 s a 256 000-position walk took, while the host reads
  /// for it cost 1.1 s.
  ///
  /// 21 bits per axis (±1 048 575) are collision free here: the walk collects at
  /// most [maximumExaminedPositions] positions, and a connected set of N
  /// positions extends at most N blocks along any axis, so N ≤ 256 001 stays
  /// four times inside the range.
  static int _pack(int x, int y, int z, int originX, int originY, int originZ) =>
      (((x - originX) & 0x1FFFFF) << 42) |
      (((y - originY) & 0x1FFFFF) << 21) |
      ((z - originZ) & 0x1FFFFF);

  /// The search of [gatherConnectedBlocks], over an already-configured [host].
  ///
  /// The neighbour reads of one *wave* of the frontier run in one host call when
  /// the host has a bulk read ([_GatherReads]); a host without one reads per
  /// query. Either way the frontier is dequeued in the same order, so the walk
  /// collects the same blocks with the same bounds and the same
  /// `checked-blocks` count.
  static GatherResult _gatherConnected(
    AssemblyBlockHost host,
    Pos gatherOrigin,
    int maximumBlocksToAssemble,
    FrontierPredicate? frontierPredicate,
    BatchingBlockHost? batchCache,
  ) {
    final frontier = ListQueue<(Pos, BState)>();
    // The positions the walk already knows: queued or visited. Both the old
    // checks (frontier membership, then visited) said "skip" for either, so one
    // set of packed keys answers both — and the result [blocks] set is then only
    // ever written, never queried.
    final known = <int>{};
    final blocks = <Pos>{};
    final reads = _GatherReads(host);
    final originX = gatherOrigin.$1, originY = gatherOrigin.$2, originZ = gatherOrigin.$3;

    final gatherOriginState = host.blockStateAt(gatherOrigin.$1, gatherOrigin.$2, gatherOrigin.$3);
    if (gatherOriginState.isAir) {
      return GatherResult(null, 0, null, GatherState.noBlocks);
    }

    frontier.add((gatherOrigin, gatherOriginState));
    known.add(0); // _pack(gatherOrigin, gatherOrigin) == 0

    var minX = gatherOrigin.$1, minY = gatherOrigin.$2, minZ = gatherOrigin.$3;
    var maxX = gatherOrigin.$1, maxY = gatherOrigin.$2, maxZ = gatherOrigin.$3;

    var blockCount = 0;
    // Java only bounds the blocks it collects (`maximumBlocksToAssemble`); the
    // port also bounds the positions the walk examines, because the walk is not
    // free even with a bulk read. Measured on a live server over a solid stone
    // mass (see `docs/sable-core-port.md`), a 256 000-position walk costs:
    // 0.3 s of host reads (2003 `get-block-states` calls for 361 367 positions),
    // ~6 s of guest bookkeeping in this loop, ~6 s in the wave scan and ~1 s
    // decoding state ids — so the host call is no longer the wall, the guest's
    // neighbour scan and hash work are. Before the bulk read the walk refused at
    // 65 536 positions (~60 us each, ~18 host reads per position of which the
    // read cache served all but ~1.4); the cap is now Java's 256 000.
    const maximumExaminedPositions = 256000;
    final maximumExamined = maximumBlocksToAssemble < maximumExaminedPositions
        ? maximumBlocksToAssemble
        : maximumExaminedPositions;
    var examined = 0;
    while (frontier.isNotEmpty) {
      // One read for the whole wave: every neighbour state the next [wave] of the
      // frontier asks about comes back in a single host call. A host without a
      // bulk read answers a wave of one.
      final wave = reads.prefetch(frontier, known, originX, originY, originZ);
      for (var i = 0; i < wave; i++) {
        final pair = frontier.removeFirst();
        final pos = pair.$1;

        blockCount++;
        examined++;
        if (blockCount > maximumBlocksToAssemble || examined > maximumExamined) {
          return GatherResult(null, blockCount, null, GatherState.tooManyBlocks);
        }

        minX = minX < pos.$1 ? minX : pos.$1;
        minY = minY < pos.$2 ? minY : pos.$2;
        minZ = minZ < pos.$3 ? minZ : pos.$3;
        maxX = maxX > pos.$1 ? maxX : pos.$1;
        maxY = maxY > pos.$2 ? maxY : pos.$2;
        maxZ = maxZ > pos.$3 ? maxZ : pos.$3;

        blocks.add(pos);

        // The batch cache is a cache: dropping it periodically keeps a walk of
        // hundreds of thousands of blocks from growing it without bound.
        if (batchCache != null && examined % 32768 == 0) {
          batchCache
            ..endBatch()
            ..beginBatch();
        }

        for (var x = -1; x <= 1; x++) {
          for (var y = -1; y <= 1; y++) {
            for (var z = -1; z <= 1; z++) {
              // Do not connect corners, only edges.
              if (!_connects(x, y, z)) continue;
              final absTotal = x.abs() + y.abs() + z.abs();

              final candidate = (pos.$1 + x, pos.$2 + y, pos.$3 + z);
              final key = _pack(candidate.$1, candidate.$2, candidate.$3, originX, originY, originZ);
              // Queued or already collected: its state is known, so the read
              // below would be one of the ~18 host calls per block that made a
              // walk through terrain cost minutes.
              if (known.contains(key)) continue;

              final direction = absTotal == 1
                  ? _nearestDirection(x, y, z)
                  : null;
              final candidateState = reads.stateAt(candidate);

              if (candidateState.isAir) continue;

              if (frontierPredicate != null &&
                  !frontierPredicate(pos, pair.$2, candidate, candidateState, direction)) {
                continue;
              }

              frontier.add((candidate, candidateState));
              known.add(key);
            }
          }
        }
      }
    }

    final bounds = BoundingBox3i.values(minX, minY, minZ, maxX, maxY, maxZ);
    if (blocks.isEmpty) {
      return GatherResult(null, blockCount, null, GatherState.noBlocks);
    }

    return GatherResult(blocks, blockCount, bounds, GatherState.success);
  }

  /// Moves the tracking points inside [bounds] with the assembly [transform].
  static void moveTrackingPoints(
    SableLevel level,
    BoundingBox3ic bounds,
    ServerSubLevel? subLevel,
    AssemblyTransform transform,
  ) {
    final container = SubLevelContainer.of(level);
    final host = container is ServerSubLevelContainer ? container.hostOrNull : null;
    final raw = host?.readSavedData(trackingPointsSavedDataName);
    final store = raw == null ? TrackingPointStore() : TrackingPointStore.load(raw);

    for (final entry in store.pointsIn(bounds).toList()) {
      final point = entry.value;
      store.setTrackingPoint(
        entry.key,
        TrackingPoint(
          subLevel != null,
          subLevel?.uniqueIdOrNull,
          subLevel?.getLastSerializationPointer(),
          transform.applyVector(point.point),
          point.globalPlaceholderPosition,
        ),
      );
    }

    if (host != null) {
      host.writeSavedData(trackingPointsSavedDataName, store.save());
      host.markSavedDataDirty(trackingPointsSavedDataName);
    }
  }

  /// Moves the entities sitting on the assembled blocks.
  static void moveOtherStuff(
    SableLevel level,
    AssemblyTransform transform,
    Iterable<Pos> blocks,
    BoundingBox3ic bounds,
  ) {
    final host = SubLevelContainer.of(level)?.chunkHost;
    if (host is! AssemblyEntityHost) return;
    final entityHost = host as AssemblyEntityHost;

    final entities = entityHost.entitiesIn(BoundingBox3d.fromBoundingBox3i(bounds).expand(2.0));
    if (entities.isEmpty) return;

    final volume = BoundedBitVolume3i.fromBlocks(blocks);
    if (volume == null) return;

    for (final entity in entities) {
      final supportBox = entity.supportBox;
      if (supportBox == null) continue;

      var moveEntity = false;
      for (var x = supportBox.minX; x <= supportBox.maxX && !moveEntity; x++) {
        for (var y = supportBox.minY; y <= supportBox.maxY && !moveEntity; y++) {
          for (var z = supportBox.minZ; z <= supportBox.maxZ && !moveEntity; z++) {
            if (volume.getOccupied(x, y, z)) moveEntity = true;
          }
        }
      }

      if (moveEntity) {
        entity.setPosition(transform.applyVector(entity.position));
      }
    }
  }

  /// Moves every block of [blocks] through [transform] into the resulting
  /// level, then clears the originals.
  static void moveBlocks(SableLevel level, AssemblyTransform transform, Iterable<Pos> blocks) {
    final resultingLevel = transform.resultingLevel;
    final host = _blockHostOf(level);
    final resultingHost = _blockHostOf(resultingLevel);

    final blockList = blocks.toList();
    if (blockList.isEmpty) return;

    // Ensure every destination chunk exists.
    Pos? firstBlock;
    (int, int)? chunkBoundsMin;
    (int, int)? chunkBoundsMax;
    for (final block in blockList) {
      firstBlock ??= block;
      final newPos = transform.applyBlock(block);
      final chunk = (newPos.$1 >> 4, newPos.$3 >> 4);
      if (chunkBoundsMin == null) {
        chunkBoundsMin = chunk;
        chunkBoundsMax = chunk;
      }
      chunkBoundsMin = (chunk.$1 < chunkBoundsMin.$1 ? chunk.$1 : chunkBoundsMin.$1,
          chunk.$2 < chunkBoundsMin.$2 ? chunk.$2 : chunkBoundsMin.$2);
      chunkBoundsMax = (chunk.$1 > chunkBoundsMax!.$1 ? chunk.$1 : chunkBoundsMax.$1,
          chunk.$2 > chunkBoundsMax.$2 ? chunk.$2 : chunkBoundsMax.$2);
    }

    final firstNewPos = transform.applyBlock(firstBlock!);
    final subLevel = SubLevelHelper.getContaining(level, firstNewPos);
    if (subLevel != null) {
      final plot = subLevel.getPlot();
      for (var chunkX = chunkBoundsMin!.$1; chunkX <= chunkBoundsMax!.$1; chunkX++) {
        for (var chunkZ = chunkBoundsMin.$2; chunkZ <= chunkBoundsMax.$2; chunkZ++) {
          if (plot.getChunkHolder(plot.toLocal((chunkX, chunkZ))) == null) {
            plot.newEmptyChunk((chunkX, chunkZ));
          }
        }
      }
    }

    final states = <BState>[];
    for (final block in blockList) {
      final state = host.blockStateAt(block.$1, block.$2, block.$3);
      final newPos = transform.applyBlock(block);

      final listener = assemblyListeners[state.key];
      listener?.beforeMove(level, resultingLevel, state, block, newPos);

      final data = host.blockEntityDataAt(block.$1, block.$2, block.$3);
      final subLevelState = transform.applyState(state);

      resultingHost.setBlockStateAt(newPos.$1, newPos.$2, newPos.$3, subLevelState);
      states.add(subLevelState);

      if (data != null) {
        resultingHost.setBlockEntityDataAt(newPos.$1, newPos.$2, newPos.$3, data);
      }

      listener?.afterMove(level, resultingLevel, state, block, newPos);
      resultingHost.notifyBlockChanged(
        newPos.$1,
        newPos.$2,
        newPos.$3,
        BState.air,
        subLevelState,
      );
    }

    // Notify the destination once every block is in place.
    for (var i = 0; i < blockList.length; i++) {
      final pos = transform.applyBlock(blockList[i]);
      resultingHost.notifyBlockChanged(pos.$1, pos.$2, pos.$3, BState.air, states[i]);
    }

    // Destroy the old blocks.
    for (final block in blockList) {
      final state = host.blockStateAt(block.$1, block.$2, block.$3);
      if (silentAssemblyRemoval.contains(state.key)) {
        host.removeBlockEntityAt(block.$1, block.$2, block.$3);
      }
      host.setBlockStateAt(block.$1, block.$2, block.$3, BState.air);
    }

    for (final block in blockList) {
      host.notifyBlockChanged(block.$1, block.$2, block.$3, BState.air, BState.air);
    }
  }

  /// `markAndNotifyBlock`: the host notifies the block's neighbours.
  static void markAndNotifyBlock(
    SableLevel level,
    Pos pos,
    BState oldState,
    BState newState,
    int flags,
    int recursionLeft,
  ) {
    final host = _blockHostOf(level);
    host.notifyBlockChanged(pos.$1, pos.$2, pos.$3, oldState, newState);
  }

  /// The block host of [level] (the chunk host, when it implements
  /// [AssemblyBlockHost], else a key-only fallback).
  static AssemblyBlockHost blockHostOf(SableLevel level) => _blockHostOf(level);

  static AssemblyBlockHost _blockHostOf(SableLevel level) {
    final container = SubLevelContainer.of(level);
    if (container == null) {
      throw StateError('Level ${level.dimensionId} has no sub-level container');
    }
    return _hostAdapter(container.chunkHost);
  }

  /// Wraps a plain [PlotChunkHost] when the plugin has not installed a richer
  /// [AssemblyBlockHost].
  static AssemblyBlockHost _hostAdapter(PlotChunkHost host) {
    if (host is AssemblyBlockHost) return host as AssemblyBlockHost;
    return _PlotChunkAssemblyHost(host);
  }

  static Direction? _nearestDirection(int x, int y, int z) {
    for (final direction in Direction.values) {
      if (direction.stepX == x && direction.stepY == y && direction.stepZ == z) {
        return direction;
      }
    }
    return null;
  }

  /// Rotates [state] with [rotation].
  static BState rotateState(BState state, Rotation rotation) {
    if (rotation == Rotation.none) return state;
    final steps = switch (rotation) {
      Rotation.none => 0,
      Rotation.clockwise90 => 1,
      Rotation.clockwise180 => 2,
      Rotation.counterclockwise90 => 3,
    };

    final props = <String, String>{};
    for (final entry in state.props.entries) {
      final value = entry.value;
      if (entry.key == 'facing') {
        Direction? direction;
        for (final candidate in Direction.values) {
          if (candidate.serializedName == value) {
            direction = candidate;
            break;
          }
        }
        if (direction != null && direction.axis != Axis.y) {
          var rotated = direction;
          for (var i = 0; i < steps; i++) {
            rotated = rotated.clockWise;
          }
          props[entry.key] = rotated.serializedName;
          continue;
        }
      }
      if (entry.key == 'axis') {
        if (steps.isOdd && (value == 'x' || value == 'z')) {
          props[entry.key] = value == 'x' ? 'z' : 'x';
          continue;
        }
      }
      if (entry.key == 'rotation') {
        final current = int.tryParse(value);
        if (current != null) {
          props[entry.key] = ((current + steps * 4) % 16).toString();
          continue;
        }
      }
      props[entry.key] = value;
    }

    return BState(state.key, props);
  }
}

/// `Rotation`: the quarter turns a block state is rotated by.
enum Rotation {
  none,
  clockwise90,
  clockwise180,
  counterclockwise90;

  /// The same rotation as [Axis.rotate] uses: 90° clockwise steps.
  int get quarterTurns => switch (this) {
    Rotation.none => 0,
    Rotation.clockwise90 => 1,
    Rotation.clockwise180 => 2,
    Rotation.counterclockwise90 => 3,
  };
}

/// The transform for assembly/disassembly.
final class AssemblyTransform {
  final Pos anchorPos;
  final Pos resultingAnchorPos;

  /// 90-degree counter-clockwise increments.
  final int angle;
  final Rotation rotation;
  final SableLevel resultingLevel;

  AssemblyTransform(
    this.anchorPos,
    this.resultingAnchorPos,
    this.angle,
    this.rotation,
    this.resultingLevel,
  );

  /// Transforms a world position.
  Vector3d applyVector(Vector3d pos) {
    final out = Vector3d.copy(pos)
      ..sub(Vector3d(anchorPos.$1 + 0.5, anchorPos.$2 + 0.5, anchorPos.$3 + 0.5));
    final radians = angle * (math.pi / 2.0);
    if (radians != 0.0) {
      final cos = math.cos(radians);
      final sin = math.sin(radians);
      final x = out.x * cos + out.z * sin;
      final z = out.z * cos - out.x * sin;
      out.set(x, out.y, z);
    }
    return out.add(Vector3d(resultingAnchorPos.$1 + 0.5, resultingAnchorPos.$2 + 0.5, resultingAnchorPos.$3 + 0.5));
  }

  /// Transforms a block position (`BlockPos.containing`).
  Pos applyBlock(Pos pos) {
    final transformed = applyVector(Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5));
    return (transformed.x.floor(), transformed.y.floor(), transformed.z.floor());
  }

  /// Transforms a block state.
  BState applyState(BState state) => SubLevelAssemblyHelper.rotateState(state, rotation);

  /// The level the blocks are moved to.
  SableLevel getLevel() => resultingLevel;

  /// The rotation applied to block states.
  Rotation getRotation() => rotation;
}

// Local trig helpers were replaced by `dart:math` above.

/// The predicate deciding whether two blocks connect during a gather.
typedef FrontierPredicate =
    bool Function(
      Pos originPos,
      BState originState,
      Pos pos,
      BState state,
      Direction? directionFrom,
    );

/// The state of a gather.
enum GatherState {
  success('commands.sable.sub_level.assemble.connected.success'),
  tooManyBlocks('commands.sable.sub_level.assemble.connected.too_many_blocks'),
  noBlocks('commands.sable.sub_level.assemble.no_blocks');

  const GatherState(this.errorKey);

  /// The translation key the command reports.
  final String errorKey;
}

/// The result of [SubLevelAssemblyHelper.gatherConnectedBlocks].
final class GatherResult {
  final Set<Pos>? blocks;
  final int checkedBlocks;
  final BoundingBox3i? boundingBox;
  final GatherState assemblyState;

  const GatherResult(this.blocks, this.checkedBlocks, this.boundingBox, this.assemblyState);
}

/// The neighbour reads of the connected search.
///
/// The search asks about the neighbours of every block it dequeues (the
/// 26-neighbour cube minus the centre and the corners, minus the positions it
/// already knows). A host with a bulk read ([BulkBlockHost]) answers the whole
/// wave in one call, which is what turns a walk over a hundred thousand
/// positions from a hundred thousand host calls into a few hundred. A host
/// without one reads per query, exactly as before.
final class _GatherReads {
  /// The frontier positions one host call reads for. Each one asks about at
  /// most 18 neighbours ([SubLevelAssemblyHelper._connects]), so a full wave
  /// requests at most `waveSize * 18` positions — a few tens of KB in the
  /// plugin's wasm store, well inside what the host takes in one call.
  static const int waveSize = 128;

  final AssemblyBlockHost _host;

  /// The host bulk read, or `null` for a host that reads per query.
  final BulkBlockHost? _bulk;

  /// The decoded states of the wave being processed, by position. Empty for a
  /// host without a bulk read, so [stateAt] falls through to it.
  Map<Pos, BState> _wave = const {};

  _GatherReads(this._host)
      : _bulk = _host is BulkBlockHost ? _host as BulkBlockHost : null;

  /// Reads the states the next wave of [frontier] will ask about, and returns
  /// how many entries the caller may dequeue.
  ///
  /// Positions whose packed key is already in [known] are left out: the walk
  /// checks the same key before it reads, so their state is known and the host
  /// must not read it again. The read set of a wave is computed before any of it
  /// is dequeued, and a position queued *during* the wave is read here rather
  /// than later, which only ever costs one extra read of a non-air block.
  int prefetch(
    ListQueue<(Pos, BState)> frontier,
    Set<int> known,
    int originX,
    int originY,
    int originZ,
  ) {
    final bulk = _bulk;
    if (bulk == null) return 1;

    final waveCount = frontier.length < waveSize ? frontier.length : waveSize;

    final requested = <int>{};
    final positions = <Pos>[];
    var queuedInWave = 0;
    outer:
    for (final entry in frontier) {
      if (queuedInWave == waveCount) break;
      queuedInWave++;
      final pos = entry.$1;
      for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
          for (var z = -1; z <= 1; z++) {
            if (!SubLevelAssemblyHelper._connects(x, y, z)) continue;
            final candidate = (pos.$1 + x, pos.$2 + y, pos.$3 + z);
            final key =
                SubLevelAssemblyHelper._pack(candidate.$1, candidate.$2, candidate.$3, originX, originY, originZ);
            // Positions the walk already knows are left out: it checks the same
            // key before it reads, so its state is known and the host must not
            // read it again. A set keeps the request free of duplicates, so the
            // list stays at most one entry per position.
            if (known.contains(key) || !requested.add(key)) continue;
            positions.add(candidate);
            if (positions.length == waveSize * 18) break outer;
          }
        }
      }
    }
    if (positions.isEmpty) {
      _wave = const {};
      return waveCount;
    }
    final states = bulk.readBlockStates(positions);
    final decoded = <Pos, BState>{};
    for (var i = 0; i < positions.length; i++) {
      decoded[positions[i]] = states[i];
    }
    _wave = decoded;
    return waveCount;
  }

  /// The state at [candidate], with the semantics of
  /// [AssemblyBlockHost.blockStateAt].
  BState stateAt(Pos candidate) {
    final cached = _wave[candidate];
    if (cached != null) return cached;
    return _host.blockStateAt(candidate.$1, candidate.$2, candidate.$3);
  }
}

/// The `PlotChunkHost` fallback: it can read block keys and write block keys,
/// but cannot move block-entity data (the host has no setter).
final class _PlotChunkAssemblyHost implements AssemblyBlockHost {
  final PlotChunkHost host;

  _PlotChunkAssemblyHost(this.host);

  @override
  BState blockStateAt(int x, int y, int z) {
    final chunk = host.getLoadedChunk(x >> 4, z >> 4);
    if (chunk == null) return BState.air;
    return BState(chunk.blockAt(x & 15, y, z & 15));
  }

  @override
  void setBlockStateAt(int x, int y, int z, BState state) => host.setBlock(x, y, z, state.key);

  @override
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z) {
    final chunk = host.getLoadedChunk(x >> 4, z >> 4);
    return chunk?.blockEntityData(x & 15, y, z & 15);
  }

  @override
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data) {
    throw UnimplementedError(
      'Moving block-entity data during assembly needs a block-entity '
      'write on the plot chunk host (block at $x,$y,$z); install '
      'AssemblyBlockHost on the chunk host to move block entities.',
    );
  }

  @override
  void removeBlockEntityAt(int x, int y, int z) {}

  @override
  void notifyBlockChanged(int x, int y, int z, BState oldState, BState newState) {}
}

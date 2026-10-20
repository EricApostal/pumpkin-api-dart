// A structure filled with hot air and enclosed by airtight blocks.
//
// Java: `content/blocks/hot_air/balloon/Balloon`.
//
// A balloon owns the layer graph of its air volume, the gas heaters that fill
// it, and a capacity (the number of air blocks that are not solid). It is
// rebuilt from its controller position whenever the enclosure changes; the
// server subclass turns the gas amounts into a lift force.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart' show BoundingBox3i, AssemblyTransform, SubLevel, SubLevelHelper;

import 'balloon_builder.dart';
import 'balloon_layer_data.dart';
import 'balloon_layer_graph.dart';
import 'balloon_world.dart';
import 'lifting_gas_provider.dart';

/// `Balloon`.
abstract class Balloon {
  /// The world the balloon lives in.
  final BalloonWorld world;

  /// The heaters currently filling this balloon.
  final Set<BlockEntityLiftingGasProvider> heaters;

  /// The rough bounds (larger than the bounds of the hot-air blocks alone).
  final BoundingBox3i bounds = BoundingBox3i();

  /// The graph of the air volume.
  BalloonLayerGraph graph;

  /// The position the flood fill started from.
  Pos controllerPos;

  /// The number of air blocks that are not solid.
  int capacity = 0;

  bool _assembling = false;

  Balloon(this.world, this.controllerPos, this.graph, List<BlockEntityLiftingGasProvider> heaters)
    : heaters = {...heaters} {
    _recomputeBalloonData();
  }

  /// Advances the balloon by one tick: finishes a pending assembly and checks
  /// that its heaters are still valid.
  void tick() {
    if (_assembling) {
      _rebuildBalloonFromController();
      _assembling = false;
    }

    checkHeaters();
  }

  /// Drops heaters that stopped outputting or moved to another sub-level, and
  /// moves the controller to the highest heater.
  void checkHeaters() {
    Pos? highestPos;
    final subLevel = SubLevelHelper.getContaining(world.level, controllerPos);

    heaters.removeWhere((heater) {
      final heaterPos = heater.castPosition;
      if (!heater.canOutputGas || heaterPos == null) {
        heater.balloon = null;
        return true;
      }

      if (!_sameSubLevel(SubLevelHelper.getContaining(world.level, heaterPos), subLevel)) {
        heater.balloon = null;
        return true;
      }

      if (highestPos == null || heaterPos.$2 > highestPos!.$2) highestPos = heaterPos;
      return false;
    });

    final highest = highestPos;
    if (highest != null) {
      moveController(highest);
    }

    _splitHeaters();
  }

  static bool _sameSubLevel(SubLevel? a, SubLevel? b) => a == b;

  /// Drops heaters whose cast position is no longer part of this balloon (the
  /// region was split).
  void _splitHeaters() {
    heaters.removeWhere((heater) {
      final heaterPos = heater.castPosition;
      if (heaterPos == null || !graph.hasBlockAt(heaterPos)) {
        heater.balloon = null;
        return true;
      }
      return false;
    });
  }

  /// A solid block appeared inside the volume: it takes capacity away.
  void onSolidBlockAdded(Pos pos) {
    if (_assembling) return;

    final layer = graph.getLayerAt(pos);
    if (layer == null) return;

    if (!layer.getSolidBlock(pos.$1, pos.$3)) {
      layer.addSolidBlock(pos.$1, pos.$3);
      layer.solidCount++;
      capacity--;
      onHotAirRemoved(pos);
    }
  }

  /// A solid block inside the volume was removed: the capacity grows back.
  void onSolidBlockRemoved(Pos pos) {
    final layer = graph.getLayerAt(pos);
    if (layer == null) return;

    if (layer.getSolidBlock(pos.$1, pos.$3)) {
      layer.removeSolidBlock(pos.$1, pos.$3);
      layer.solidCount--;
      capacity++;
      onHotAirAdded(pos);
    }
  }

  /// An airtight block of the envelope was removed: the volume may have opened.
  void onAirtightBlockRemoved(Pos pos) {
    if (_assembling) return;

    final shouldSpawnGust = this.shouldSpawnGust(pos);
    var gusted = false;

    for (final direction in Direction.values) {
      final adjacent = (
        pos.$1 + direction.stepX,
        pos.$2 + direction.stepY,
        pos.$3 + direction.stepZ,
      );

      final layer = graph.getLayerAt(adjacent);
      if (layer == null) continue;

      layer.removeHotAirBlock(adjacent.$1, adjacent.$3);
      final result = BalloonBuilder.buildBalloon(world, adjacent, graph);
      layer.addHotAirBlock(adjacent.$1, adjacent.$3);

      if (result == null) {
        // The volume is open to the outside: the balloon leaks.
        final gustDirections = shouldSpawnGust ? _findGustDirections(pos) : const <Direction>[];

        if (layer.inwardConnections.isEmpty) {
          if (shouldSpawnGust && !gusted) {
            for (final gustDirection in gustDirections) {
              spawnGust(pos.$1 + gustDirection.stepX, pos.$2 + gustDirection.stepY, pos.$3 + gustDirection.stepZ, gustDirection);
            }
          }
          setLeaking();
          return;
        }

        final beforeCapacity = capacity;
        final removedLayers = graph.propagateRemoval(layer);

        for (final removedLayer in removedLayers) {
          onHotAirRemovedAll(removedLayer.nonSolidBlocks.toList());
        }

        final lostHotAir = beforeCapacity - capacity;
        if (lostHotAir > 0 && shouldSpawnGust && !gusted) {
          for (final gustDirection in gustDirections) {
            spawnGust(pos.$1 + gustDirection.stepX, pos.$2 + gustDirection.stepY, pos.$3 + gustDirection.stepZ, gustDirection);
          }
          gusted = true;
        }

        graph.rebuildConnections(controllerPos);
        _recomputeBalloonData();
      } else {
        _rebuildBalloonFromController();
        return;
      }
    }
  }

  List<Direction> _findGustDirections(Pos pos) {
    final directions = <Direction>[];
    for (final direction in Direction.values) {
      final opposite = direction.opposite;
      final state = world.stateAt(
        pos.$1 + opposite.stepX,
        pos.$2 + opposite.stepY,
        pos.$3 + opposite.stepZ,
      );
      final beyond = (pos.$1 + direction.stepX, pos.$2 + direction.stepY, pos.$3 + direction.stepZ);
      if ((state.isAir || !world.isAirtight(state)) && graph.hasBlockAt(beyond)) {
        directions.add(opposite);
      }
    }
    return directions;
  }

  /// An airtight block was added: the enclosure may have changed shape.
  void onAirtightBlockAdded(Pos pos) {
    if (_assembling) return;
    _rebuildBalloonFromController();
  }

  /// Whether removing the airtight block at [pos] should push nearby entities
  /// away with a gust. Only the server balloon says yes.
  bool shouldSpawnGust(Pos pos) => false;

  /// Spawns one gust at [x], [y], [z] pointing in [direction]. The server
  /// balloon's host adapter spawns the entity.
  void spawnGust(int x, int y, int z, Direction direction) {}

  /// Called when the volume opened to the outside.
  void setLeaking() {}

  /// Called after the graph was rebuilt.
  void onRebuilt() {}

  /// Called when one block of the volume became hot air (or its solid block was
  /// removed).
  void onHotAirAdded(Pos pos) {}

  /// Called when one block of the volume stopped being hot air (or a solid
  /// block appeared).
  void onHotAirRemoved(Pos pos) {}

  /// Called when a whole batch of blocks left the volume.
  void onHotAirRemovedAll(List<Pos> positions) {
    for (final pos in positions) {
      onHotAirRemoved(pos);
    }
  }

  /// Moves the controller, rebuilding the region when the layer changed.
  void moveController(Pos newControllerPos) {
    if (controllerPos == newControllerPos) return;

    final needsRebuild = graph.getLayerAt(newControllerPos) != graph.getLayerAt(controllerPos);
    controllerPos = newControllerPos;
    if (needsRebuild) _rebuildBalloonFromController();
  }

  void _rebuildBalloonFromController() {
    final result = BalloonBuilder.buildBalloon(world, controllerPos);
    if (result == null) {
      setLeaking();
      return;
    }

    graph = result;
    _recomputeBalloonData();
    onRebuilt();
  }

  void _recomputeBalloonData() {
    bounds.minY = graph.minY;
    bounds.maxY = graph.maxY;
    bounds.minX = controllerPos.$1;
    bounds.maxX = controllerPos.$1;
    bounds.minZ = controllerPos.$3;
    bounds.maxZ = controllerPos.$3;
    capacity = 0;

    for (var y = graph.minY; y <= graph.maxY; y++) {
      for (final layer in graph.getLayersAtY(y)) {
        capacity += layer.hotAirCount;
        capacity -= layer.solidCount;

        for (final chunkKey in layer.chunkKeys) {
          final originX = chunkKey.$1 << BalloonLayerData.layerChunkShift;
          final originZ = chunkKey.$2 << BalloonLayerData.layerChunkShift;
          bounds.expandToValues(originX, y, originZ);
          bounds.expandToValues(originX + 7, y, originZ + 7);
        }
      }
    }
  }

  /// The number of air blocks that are not solid.
  int get capacityValue => capacity;

  void addHeater(BlockEntityLiftingGasProvider heater) => heaters.add(heater);

  void removeHeater(BlockEntityLiftingGasProvider heater) => heaters.remove(heater);

  /// The heaters filling this balloon.
  Iterable<BlockEntityLiftingGasProvider> get heaterSet => heaters;

  /// The height of the balloon, in blocks.
  double get height => (bounds.maxY - bounds.minY + 1).toDouble();

  /// Whether the balloon still holds enough gas to exist.
  bool get isValid;

  /// Detaches every heater.
  void onRemoved() {
    for (final heater in heaters) {
      heater.balloon = null;
    }
  }

  /// Absorbs [other], whose heaters now point at this balloon.
  void merge(Balloon other) {
    heaters.addAll(other.heaters);
    for (final heater in other.heaters) {
      heater.balloon = this;
    }
  }

  BalloonLayerGraph get layerGraph => graph;

  /// The balloon moved with an assembly: the controller and bounds follow the
  /// transform, and the heaters re-join on their own.
  void setAssembling(AssemblyTransform transform) {
    _assembling = true;
    controllerPos = transform.applyBlock(controllerPos);

    for (final heater in heaters) {
      heater.balloon = null;
    }
    heaters.clear();

    final min = transform.applyBlock((bounds.minX, bounds.minY, bounds.minZ));
    final max = transform.applyBlock((bounds.maxX, bounds.maxY, bounds.maxZ));
    bounds.setValues(min.$1, min.$2, min.$3, max.$1, max.$2, max.$3);
  }

  /// Whether an assembly is being applied.
  bool get isAssembling => _assembling;

  /// The state at a global position, for the balloon's own checks.
  BState stateAt(int x, int y, int z) => world.stateAt(x, y, z);
}

// Builds the layer graph of a balloon by flooding the space enclosed by
// airtight blocks.
//
// Java: `content/blocks/hot_air/balloon/graph/BalloonBuilder`.
//
// The flood fill is upwards-biased: it walks the whole horizontal plane, and
// whenever the block above a candidate is also a candidate, it recurses into
// that plane first. A plane that cannot be closed off (it reaches the top of
// the world, or a block that is not a candidate) aborts the whole build.
//
// Pure: no host imports.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

import 'balloon_layer_data.dart';
import 'balloon_layer_graph.dart';
import 'balloon_world.dart';

/// `BalloonBuilder`.
abstract final class BalloonBuilder {
  /// The four directions the flood fill walks horizontally.
  static const List<Direction> horizontalDirections = [
    Direction.north,
    Direction.south,
    Direction.west,
    Direction.east,
  ];

  /// `isCandidatePosition`: a block that may join the balloon.
  ///
  /// It must not be part of [graph], [existingGraph] or [mainGraph], and it
  /// must be air or a non-airtight block.
  static bool isCandidatePositionIn(
    BalloonWorld world,
    Pos pos,
    BalloonLayerGraph graph, [
    BalloonLayerGraph? existingGraph,
    BalloonLayerGraph? mainGraph,
  ]) {
    if (_containsBlockAt(pos, graph)) return false;
    if (existingGraph != null && _containsBlockAt(pos, existingGraph)) return false;
    if (mainGraph != null && _containsBlockAt(pos, mainGraph)) return false;

    final state = world.stateAtPos(pos);
    return state.isAir || !world.isAirtight(state);
  }

  static bool _containsBlockAt(Pos pos, BalloonLayerGraph graph) {
    for (final layer in graph.getLayersAtY(pos.$2)) {
      if (layer.getHotAirBlock(pos.$1, pos.$3)) return true;
    }
    return false;
  }

  /// `buildBalloon(world, startPos, mainGraph)`: the graph of the balloon whose
  /// air volume contains [startPos], or `null` when the space is not closed.
  static BalloonLayerGraph? buildBalloon(
    BalloonWorld world,
    Pos startPos, [
    BalloonLayerGraph? mainGraph,
  ]) {
    final graph = BalloonLayerGraph(startPos.$2);
    final firstSafe = upwardsBiasedFloodFill(world, startPos, graph, null, mainGraph);
    if (!firstSafe) return null;

    completeBalloon(world, graph, mainGraph);
    graph.rebuildConnections(startPos);
    return graph;
  }

  /// Fills in the layers the upwards pass did not reach.
  ///
  /// Every layer that is not complete hands its lower neighbours to the flood
  /// fill; positions that can only be reached through open space are dropped
  /// again with [removeReachable].
  static void completeBalloon(
    BalloonWorld world,
    BalloonLayerGraph graph, [
    BalloonLayerGraph? mainGraph,
  ]) {
    var progressMade = true;

    while (progressMade) {
      progressMade = false;

      // The bounds are captured like the Java array is: layers added by this
      // pass are visited by the next one.
      final fromY = graph.minY;
      final toY = graph.maxY;

      for (var layerY = fromY; layerY <= toY; layerY++) {
        final layersAtY = List<BalloonLayerData>.of(graph.getLayersAtY(layerY));

        for (final layer in layersAtY) {
          if (layer.state == BalloonLayerDataState.complete) continue;

          final queue = LinkedHashSet<Pos>();
          for (final block in layer.blocks) {
            queue.add((block.$1, block.$2 - 1, block.$3));
          }

          while (queue.isNotEmpty) {
            final candidate = queue.first;
            queue.remove(candidate);

            final newGraph = BalloonLayerGraph(candidate.$2);
            if (!isCandidatePositionIn(world, candidate, newGraph, graph, mainGraph)) {
              continue;
            }

            final safe = upwardsBiasedFloodFill(world, candidate, newGraph, graph, mainGraph);
            if (!safe) {
              removeReachable(world, queue, candidate);
              continue;
            }

            final newLayersAtY = newGraph.getLayersAtY(candidate.$2);
            queue.removeWhere(
              (p) => newLayersAtY.any((layerData) => layerData.getHotAirBlock(p.$1, p.$3)),
            );

            graph.addAll(newGraph);
            progressMade = true;
          }

          layer.state = BalloonLayerDataState.complete;
        }
      }
    }
  }

  /// Drops every queued position that [origin] can reach horizontally without
  /// crossing an airtight block.
  static void removeReachable(BalloonWorld world, Set<Pos> queue, Pos origin) {
    final visited = <Pos>{origin};
    final frontier = <Pos>[origin];
    queue.remove(origin);

    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();

      for (final direction in horizontalDirections) {
        final neighbor = (
          current.$1 + direction.stepX,
          current.$2 + direction.stepY,
          current.$3 + direction.stepZ,
        );

        if (!queue.contains(neighbor) || visited.contains(neighbor)) continue;

        final state = world.stateAtPos(neighbor);
        if (!state.isAir && world.isAirtight(state)) continue;

        queue.remove(neighbor);
        frontier.add(neighbor);
        visited.add(neighbor);
      }
    }
  }

  /// One upwards-biased plane flood fill, written into [outputGraph].
  ///
  /// Returns whether the plane was closed off.
  static bool upwardsBiasedFloodFill(
    BalloonWorld world,
    Pos startPos,
    BalloonLayerGraph outputGraph, [
    BalloonLayerGraph? existingGraph,
    BalloonLayerGraph? mainGraph,
  ]) {
    if (startPos.$2 < world.minY || startPos.$2 >= world.maxY) return false;

    if (!isCandidatePositionIn(world, startPos, outputGraph, existingGraph, mainGraph)) {
      return false;
    }

    final queue = <Pos>[startPos];
    final visited = <Pos>{startPos};
    final newLayer = BalloonLayerData(startPos.$2);

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final state = world.stateAtPos(current);

      if (isCandidatePositionIn(world, current, outputGraph, existingGraph, mainGraph)) {
        newLayer.hotAirCount++;
        newLayer.addHotAirBlock(current.$1, current.$3);

        if (!state.isAir) {
          newLayer.solidCount++;
          newLayer.addSolidBlock(current.$1, current.$3);
        }
      } else {
        continue;
      }

      final above = (current.$1, current.$2 + 1, current.$3);
      if (!visited.contains(above) &&
          isCandidatePositionIn(world, above, outputGraph, existingGraph, mainGraph)) {
        if (!upwardsBiasedFloodFill(world, above, outputGraph, existingGraph, mainGraph)) {
          return false;
        }
      }

      for (final direction in horizontalDirections) {
        final neighbor = (
          current.$1 + direction.stepX,
          current.$2 + direction.stepY,
          current.$3 + direction.stepZ,
        );

        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          queue.add(neighbor);
        }
      }
    }

    outputGraph.addLayer(startPos.$2, newLayer);
    return true;
  }

  /// `isSolid`: any block that is not air takes up volume.
  static bool isSolid(BState state) => !state.isAir;
}

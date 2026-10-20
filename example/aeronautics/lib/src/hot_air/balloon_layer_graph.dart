// The layer graph of a balloon: the layers of every Y level, and the
// connections between layers of adjacent levels.
//
// Java: `content/blocks/hot_air/balloon/graph/BalloonLayerGraph`.
//
// The Java class keeps an array of layer lists indexed by `y - minY`. The port
// keeps a map from Y level to the layers of that level and tracks the bounds;
// every operation that walks the graph sorts the Y levels, so iteration order
// is the same as the array's.
//
// Pure: no host imports.
import 'dart:collection';

import 'package:create/src/common/pos.dart' show Pos;

import 'balloon_layer_data.dart';

/// `BalloonLayerGraph`.
final class BalloonLayerGraph {
  /// Layers by Y level.
  final SplayTreeMap<int, List<BalloonLayerData>> _layers = SplayTreeMap();

  BalloonLayerGraph(int yLevel) {
    _layers[yLevel] = [];
  }

  /// Adds [layer] at [y].
  void addLayer(int y, BalloonLayerData layer) {
    _layers.putIfAbsent(y, () => []).add(layer);
  }

  /// Removes [layer].
  void removeLayer(BalloonLayerData layer) {
    final layers = _layers[layer.yLevel];
    layers?.remove(layer);
  }

  /// Drops the empty Y levels at both ends.
  void trim() {
    final empty = [
      for (final entry in _layers.entries)
        if (entry.value.isEmpty) entry.key,
    ];
    for (final y in empty) {
      _layers.remove(y);
    }
  }

  /// The layers at [y] (empty when the graph has none).
  List<BalloonLayerData> getLayersAtY(int y) => _layers[y] ?? const [];

  /// Every layer, in increasing Y, each Y's layers in insertion order.
  Iterable<List<BalloonLayerData>> get allLayers => _layers.values;

  /// Every layer, flattened, in increasing Y.
  Iterable<BalloonLayerData> get layers sync* {
    for (final list in _layers.values) {
      yield* list;
    }
  }

  int get minY => _layers.isEmpty ? 0 : _layers.firstKey()!;

  int get maxY => _layers.isEmpty ? 0 : _layers.lastKey()!;

  /// Adds all the layers of [other].
  void addAll(BalloonLayerGraph other) {
    for (final entry in other._layers.entries) {
      for (final layer in entry.value) {
        addLayer(entry.key, layer);
      }
    }
  }

  /// The layer whose hot-air mask contains [pos], or `null`.
  BalloonLayerData? getLayerAt(Pos pos) {
    for (final layer in getLayersAtY(pos.$2)) {
      if (layer.getHotAirBlock(pos.$1, pos.$3)) return layer;
    }
    return null;
  }

  /// Whether [pos] is inside the balloon's air volume.
  bool hasBlockAt(Pos pos) => getLayerAt(pos) != null;

  /// Rebuilds the layer connections from [startPos], walking up and down.
  ///
  /// Two layers of adjacent Y levels connect when their hot-air masks share a
  /// column; the walk only goes *down* through inward edges, so a layer's
  /// inward edges are the layers it was reached from.
  void rebuildConnections(Pos startPos) {
    for (final layer in layers) {
      layer.inwardConnections.clear();
      layer.outwardConnections.clear();
    }

    final startLayer = getLayerAt(startPos);
    if (startLayer == null) return;

    final queue = <BalloonLayerData>[startLayer];
    final visited = <BalloonLayerData>{startLayer};

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final currentY = current.yLevel;

      for (var dy = -1; dy <= 1; dy += 2) {
        final neighborLayers = getLayersAtY(currentY + dy);
        if (neighborLayers.isEmpty) continue;

        for (final neighbor in neighborLayers) {
          if (current.overlaps(neighbor) &&
              !neighbor.outwardConnections.contains(current) &&
              !neighbor.inwardConnections.contains(current)) {
            current.outwardConnections.add(neighbor);
            neighbor.inwardConnections.add(current);

            if (!visited.contains(neighbor)) {
              visited.add(neighbor);
              queue.add(neighbor);
            }
          }
        }
      }
    }
  }

  /// Removes every layer reachable from [startLayer] and returns them.
  Set<BalloonLayerData> propagateRemoval(BalloonLayerData startLayer) {
    final frontier = <BalloonLayerData>[startLayer];
    final visited = <BalloonLayerData>{startLayer};

    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();

      for (final outward in current.outwardConnections) {
        if (!visited.contains(outward)) {
          visited.add(outward);
          frontier.add(outward);
        }
      }

      for (final inward in current.inwardConnections) {
        if (current.yLevel > inward.yLevel && !visited.contains(inward)) {
          visited.add(inward);
          frontier.add(inward);
        }
      }
    }

    for (final layer in visited) {
      removeLayer(layer);
    }

    trim();
    return visited;
  }

  @override
  String toString() => 'BalloonLayerGraph(minY: $minY, maxY: $maxY, layers: ${layers.length})';
}

// Dyeing an envelope: one block, its six neighbours, or the whole connected
// envelope.
//
// Java: `content/blocks/hot_air/envelope/EnvelopeBlock#applyDye`.
//
// A dye first colours the clicked envelope; if that was already the colour, the
// six neighbours; if none of those took the colour, the whole connected envelope
// (including encased shafts), breadth first with a budget of 125 blocks.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

/// The block and property access the dye needs.
abstract interface class EnvelopeDyeWorld {
  BState stateAt(Pos pos);

  void setStateAt(Pos pos, BState state);

  /// The dye colour of an envelope block (`white`, `light_blue`, ...), or `null`
  /// when [state] is not an envelope.
  String? envelopeColor(BState state);

  /// The dye colour of an encased envelope shaft, or `null`.
  String? encasedColor(BState state);

  /// The `axis` of an encased envelope shaft.
  String? encasedAxis(BState state);
}

/// The keys the dye writes.
final class EnvelopeKeys {
  /// The envelope block key of a colour (`aeronautics:white_envelope`).
  final String Function(String color) envelope;

  /// The encased shaft key of a colour.
  final String Function(String color) encased;

  /// The properties of the encased shaft block (`axis`).
  final List<String> encasedProperties;

  const EnvelopeKeys({
    required this.envelope,
    required this.encased,
    this.encasedProperties = const ['axis'],
  });
}

/// `EnvelopeBlock.applyDye`.
abstract final class EnvelopeDye {
  /// The offsets the whole-envelope pass visits: the six faces plus the twelve
  /// edge-adjacent diagonals and the eight corners' face pairs the Java list
  /// names.
  static const List<(int, int, int)> directionOffsets = [
    (1, 0, 0),
    (-1, 0, 0),
    (0, 1, 0),
    (0, -1, 0),
    (0, 0, 1),
    (0, 0, -1),
    (1, 1, 0),
    (-1, -1, 0),
    (1, -1, 0),
    (-1, 1, 0),
    (1, 0, 1),
    (-1, 0, -1),
    (1, 0, -1),
    (-1, 0, 1),
    (0, 1, 1),
    (0, -1, -1),
    (0, -1, 1),
    (0, 1, -1),
  ];

  /// The budget of the whole-envelope pass.
  static const int floodBudget = 125;

  /// Applies [color] at [pos].
  ///
  /// Returns whether anything was dyed.
  static bool apply(
    EnvelopeDyeWorld world,
    Pos pos,
    String color,
    EnvelopeKeys keys,
  ) {
    final state = world.stateAt(pos);
    if (_selfDye(world, pos, state, color, keys)) return true;

    var hasDyed = false;
    for (final direction in Direction.values) {
      final adjacent = (
        pos.$1 + direction.stepX,
        pos.$2 + direction.stepY,
        pos.$3 + direction.stepZ,
      );
      if (_selfDye(world, adjacent, world.stateAt(adjacent), color, keys)) hasDyed = true;
    }
    if (hasDyed) return true;

    final newEnvelope = BState(keys.envelope(color));
    final newEncased = BState(keys.encased(color), {
      for (final property in keys.encasedProperties) property: 'y',
    });

    final frontier = <Pos>[pos];
    final visited = <Pos>{};
    var budget = floodBudget;

    while (frontier.isNotEmpty) {
      if (budget-- < 0) break;

      final current = frontier.removeAt(0);
      visited.add(current);

      for (final offset in directionOffsets) {
        final adjacent = (
          current.$1 + offset.$1,
          current.$2 + offset.$2,
          current.$3 + offset.$3,
        );
        if (visited.contains(adjacent)) continue;

        final adjacentState = world.stateAt(adjacent);
        if (!_multiDye(world, adjacent, adjacentState, newEnvelope) &&
            !_multiDye(world, adjacent, adjacentState, newEncased)) {
          continue;
        }

        frontier.add(adjacent);
        visited.add(adjacent);
      }
    }

    return true;
  }

  static bool _selfDye(EnvelopeDyeWorld world, Pos pos, BState state, String color, EnvelopeKeys keys) {
    final envelopeColor = world.envelopeColor(state);
    if (envelopeColor != null && envelopeColor != color) {
      world.setStateAt(pos, BState(keys.envelope(color)));
      return true;
    }

    final encasedColor = world.encasedColor(state);
    if (encasedColor != null && encasedColor != color) {
      final axis = world.encasedAxis(state) ?? 'y';
      world.setStateAt(pos, BState(keys.encased(color), {'axis': axis}));
      return true;
    }

    return false;
  }

  static bool _multiDye(EnvelopeDyeWorld world, Pos pos, BState state, BState newState) {
    final fromEnvelope = world.envelopeColor(state) != null;
    final toEnvelope = world.envelopeColor(newState) != null;

    if (fromEnvelope && toEnvelope) {
      if (state != newState) world.setStateAt(pos, newState);
      return true;
    }

    final fromEncased = world.encasedColor(state) != null;
    final toEncased = world.encasedColor(newState) != null;

    if (fromEncased && toEncased) {
      if (state != newState) {
        final axis = world.encasedAxis(state) ?? 'y';
        world.setStateAt(pos, newState.setValue('axis', axis));
      }
      return true;
    }

    return false;
  }
}

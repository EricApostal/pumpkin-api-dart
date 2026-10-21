// `PlaceSpringPacket.handle`, minus the world: which two blocks a spring may
// join and how long it starts out.
//
// The Java method is
//
//   distanceSquared = HELPER.distanceSquaredWithSubLevels(level, centre(parentRelative), centre(childRelative))
//   if (!(held item instanceof SpringItem) || distanceSquared > (MAX_LENGTH + 1)^2) return;
//   ... place both ends ...
//   distance = clamp(sqrt(distanceSquared) + 1, 1, MAX_LENGTH)
//
// so a spring is only placeable within ten blocks, and it always starts one
// block longer than the gap it spans.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.PlaceSpringPacket
//       …content.items.spring.SpringItemHandler
import 'dart:math' as math;

// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart';

import 'spring_logic.dart';

/// The placement rules of a spring.
abstract final class SpringPlacement {
  /// `SpringItemHandler.MAX_LENGTH`.
  static const double maxLength = 9.0;

  /// `SpringItemHandler.MIN_LENGTH`.
  static const double minLength = 1.0;

  /// The block a spring end attaches to: the clicked block, offset by the face
  /// the player clicked.
  static Pos relativeEnd(Pos clicked, Direction facing) => clicked.relative(facing);

  /// Whether the click may place a spring at [distanceSquared] (the squared
  /// distance between the two ends' centres).
  ///
  /// A missing spring item refuses; the distance bound is
  /// `(MAX_LENGTH + 1)^2`, i.e. 100.
  static bool canPlace({required bool holdingSpring, required double distanceSquared}) =>
      holdingSpring && distanceSquared <= (maxLength + 1) * (maxLength + 1);

  /// `Math.clamp(Math.sqrt(distanceSquared) + 1, 1, MAX_LENGTH)`.
  static double desiredLength(double distanceSquared) =>
      (math.sqrt(distanceSquared) + 1).clamp(minLength, maxLength);

  /// The desired length is what both ends store, and it is inside the range the
  /// spring block itself accepts.
  static bool isValidLength(double length) => length >= SpringLogic.minLength && length <= SpringLogic.maxLength;
}

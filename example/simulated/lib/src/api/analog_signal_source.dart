// A block that exposes an analog value to the rest of the mod: the throttle
// lever (its redstone signal) and the steering wheel (its steering input).
//
// This is the port's shape of the Java `ThrottleLeverBlockEntity#getState` /
// `SteeringWheelBlockEntity#targetAngleToUpdate` pair, which other content reads
// directly. One interface lets Aeronautics read either without knowing the
// block.
//
// Pure: no host imports.
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/common/pos.dart' show Pos;

/// A block entity that reports a normalized analog value.
abstract interface class AnalogSignalSource {
  /// The value, in `[-1, 1]`.
  double get analogOutput;

  /// The block position of the source.
  Pos get signalPos;
}

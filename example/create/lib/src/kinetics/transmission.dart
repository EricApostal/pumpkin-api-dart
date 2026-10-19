// The speed ratios of gearboxes, gearshifts and clutches (pure).
import 'geometry.dart';

/// `RotationPropagator.getAxisModifier` for a `GearboxBlockEntity`: the factor of
/// the shaft on the side [direction] when the input comes from [source].
double gearboxModifier(Dir direction, Dir source) {
  if (direction.axis == source.axis) return direction == source ? 1 : -1;
  return direction.isPositive == source.isPositive ? -1 : 1;
}

/// `GearshiftBlockEntity.getRotationSpeedModifier`.
double gearshiftModifier({required bool hasSource, required Dir face, required Dir sourceFacing, required bool powered}) {
  if (hasSource && face != sourceFacing && powered) return -1;
  return 1;
}

/// `ClutchBlockEntity.getRotationSpeedModifier`.
double clutchModifier({required bool hasSource, required Dir face, required Dir sourceFacing, required bool powered}) {
  if (hasSource && face != sourceFacing && powered) return 0;
  return 1;
}

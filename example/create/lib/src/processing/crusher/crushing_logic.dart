// The pure geometry and timing of the crushing wheels (`CrushingWheelBlock` and
// `CrushingWheelControllerBlockEntity` of the Java mod). Kept free of host imports so the
// controller's behaviour can be reasoned about (and tested) on the plain VM.
import 'dart:math' as math;

import '../../kinetics/geometry.dart';
import '../common/stack.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';

/// `Math.round(Math.signum(be.getSpeed())) * side.getAxisDirection().getStep()`: which way the
/// two wheels turn relative to [side].
int controllerStep(double wheelSpeed, Dir side) =>
    wheelSpeed.sign.round() * side.step;

/// The facing of the controller between two wheels turning in opposite directions
/// (`CrushingWheelBlock.updateControllers`): the cross product of the wheel axis and the side
/// axis, pointing with the rotation of the wheel at [pos].
Dir controllerDirection(KAxis wheelAxis, Dir side, double wheelSpeed) {
  final (ax, ay, az) = _unit(wheelAxis);
  final (bx, by, bz) = _unit(side.axis);
  final (cx, cy, cz) = (
    ay * bz - az * by,
    az * bx - ax * bz,
    ax * by - ay * bx,
  );
  final step = controllerStep(wheelSpeed, side);
  return Dir.approximateNearest(cx * step, cy * step, cz * step);
}

(double, double, double) _unit(KAxis axis) => switch (axis) {
  KAxis.x => (1, 0, 0),
  KAxis.y => (0, 1, 0),
  KAxis.z => (0, 0, 1),
};

/// `outSpeed` of the controller tick: the motion the processed items are ejected with.
(double, double, double) ejectionMotion(Dir facing) {
  final offset = facing.step;
  return (
    (facing.axis == KAxis.x ? .25 : 0.0) * offset,
    offset == 1 ? (facing.axis == KAxis.y ? .5 : 0.0) : 0.0,
    (facing.axis == KAxis.z ? .25 : 0.0) * offset,
  );
}

/// `outPos`: the block centre pushed [distance] towards [facing].
(double, double, double) ejectionPosition(
  (double, double, double) center,
  Dir facing, {
  double distance = .55,
}) {
  final offset = facing.step;
  return (
    center.$1 + (facing.axis == KAxis.x ? distance * offset : 0),
    center.$2 + (facing.axis == KAxis.y ? distance * offset : 0),
    center.$3 + (facing.axis == KAxis.z ? distance * offset : 0),
  );
}

/// `entityOutPos`: where a crushed entity is moved before the lethal blow lands.
(double, double, double) entityEjectionPosition(
  (double, double, double) outPos,
  Dir facing,
) {
  final offset = facing.step;
  return (
    outPos.$1 + (facing.axis == KAxis.x ? .5 * offset : 0),
    outPos.$2 + (facing.axis == KAxis.y ? .5 * offset : 0),
    outPos.$3 + (facing.axis == KAxis.z ? .5 * offset : 0),
  );
}

/// The velocity the controller keeps the entity at while it is being crushed: pulled towards
/// the centre across the wheel axis and pushed along [facing] (`crushingspeed * 4` is the speed).
(double, double, double) entityPushVelocity({
  required Dir facing,
  required double crushingspeed,
  required (double, double, double) center,
  required (double, double, double) entityPos,
  required bool sneaking,
}) {
  final speed = crushingspeed * 4;
  var xMotion = (center.$1 - entityPos.$1) / 2;
  var zMotion = (center.$3 - entityPos.$3) / 2;
  if (sneaking) {
    xMotion = 0;
    zMotion = 0;
  }
  // `Math.max(-speed / 4f, -.5f) * -offset`: never faster than half a block per tick.
  final movement = math.max(-speed / 4, -.5) * -facing.step;
  return (
    facing.axis == KAxis.x ? movement : xMotion,
    facing.axis == KAxis.y ? movement : 0,
    facing.axis == KAxis.z ? movement : zMotion,
  );
}

/// How fast the inventory timer runs down. Bigger stacks are crushed slower
/// (`log2(count)`); once the recipe was applied the remaining time runs at full speed.
double itemProcessingSpeed(double speed, int count, bool appliedRecipe) {
  final divisor = appliedRecipe ? 1.0 : math.log(count) / math.log(2);
  return (speed / divisor).clamp(.25, 20.0).toDouble();
}

/// Whether an entity at [entityCoord] on the facing axis is far enough into the block to be
/// taken into the inventory (`intakeItem`): past the centre minus a quarter block.
bool intakesItem(Dir facing, double entityCoord, double centerCoord) =>
    entityCoord * -facing.step < (centerCoord - .25) * -facing.step;

/// `CrushingWheelControllerBlockEntity.findRecipe`: a `create:crushing` recipe first, then a
/// `create:milling` one (the wheels also grind everything the millstone accepts). Pure, so the
/// selection can be tested without a server.
RecipeMatch? crushingRecipeFor(RecipeBook book, PStack stack) {
  if (stack.isEmpty) return null;
  return book.findForInput(CreateRecipeType.crushing, stack) ??
      book.findForInput(CreateRecipeType.milling, stack);
}

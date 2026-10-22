// The portable engine's state machine: what it burns, what it generates and
// what its comparator says.
//
// Java keeps all of this in `PortableEngineBlockEntity.tick` and
// `PortableEngineBlock`; the numbers below are theirs. The block entity file
// adds the host glue (kinetics, the inventory, the state write).
//
// Pure: no host imports, so the tests run on the plain Dart VM.
//
// Java: dev.simulated_team.simulated.content.blocks.portable_engine.PortableEngineBlockEntity
//       dev.simulated_team.simulated.content.blocks.portable_engine.PortableEngineBlock
library;

import 'dart:math' as math;

/// `PortableEngineBlockEntity.INFINITE_THRESHOLD`: a month of burn time counts
/// as infinite fuel (a creative blaze cake sets it).
const int infiniteBurnThreshold = 20 * 3600 * 24 * 30;

/// `PortableEngineBlock.BURN_TIME_THRESHOLD`: ten seconds per comparator step.
const int burnTimeThreshold = 10 * 20;

/// The speed the engine generates (`PortableEngineBlockEntity.tick`, the
/// `// TODO: config?` constant), and `PortableEngineBlock.getSpeedRange()`.
const int portableEngineSpeed = 32;
const int portableEngineMinSpeed = 32;
const int portableEngineMaxSpeed = 32;

/// `SimStress.setCapacity(64.0)` of the block.
const double portableEngineStressCapacity = 64;

/// `IControlContraption.MovementMode.values().length`: the scroll box cycles
/// through them when the engine would turn against its network.
const int movementModeCount = 3;

/// `PortableEngineBlock.analogPower(burnTime)`: 1..15, one step per ten seconds
/// of fuel left.
int analogPower(int burnTime) {
  if (burnTime <= 0) return 0;
  return math.min(burnTime ~/ burnTimeThreshold, 14) + 1;
}

/// `PortableEngineBlockEntity.getTime(sec)`: the goggle tooltip's `1h 02m 03s`.
String burnTimeLabel(int seconds) {
  var rest = seconds;
  final hours = rest ~/ 3600;
  rest -= hours * 3600;
  final minutes = rest ~/ 60;
  rest -= minutes * 60;
  final buffer = StringBuffer();
  if (hours > 0) buffer.write('${hours}h ');
  if (minutes < 10 && hours > 0) buffer.write('0');
  if (minutes > 0 || hours > 0) buffer.write('${minutes}m ');
  if (rest < 10 && minutes > 0) buffer.write('0');
  buffer.write('${rest}s');
  return buffer.toString();
}

/// The burn state of one engine: the fuel in the slot, what is left of the
/// burning item and whether it burns superheated.
final class PortableEngineBurn {
  /// `burnTime`: ticks of fuel left in the current item.
  int burnTime = 0;

  /// `superHeated`: the current item burns superheated (twice the speed).
  bool superHeated = false;

  /// `eatingCake`: the engine is eating a cake in front of it (synced to the
  /// client so the hatch animation plays).
  bool eatingCake = false;

  /// `PortableEngineBlock.isLitState(state) != burnTime > 0` in Java; here the
  /// `lit` property follows this.
  bool get isLit => burnTime > 0;

  /// `isCurrentFuelInfinite()`.
  bool get isCurrentFuelInfinite => burnTime >= infiniteBurnThreshold;

  /// `getTotalBurnTime()`: what is burning plus what the slot still holds.
  int totalBurnTime(int slotCount, int nextFuelTicks) => burnTime + slotCount * nextFuelTicks;

  /// `isTotalFuelInfinite()`.
  bool isTotalFuelInfinite(int nextFuelTicks) =>
      nextFuelTicks >= infiniteBurnThreshold || isCurrentFuelInfinite;

  /// `getGeneratedSpeed()`: the speed this block contributes to its network.
  ///
  /// `convertToDirection(generatedSpeed * (movementDirection > 0 ? -1 : 1),
  /// HORIZONTAL_FACING) * (superHeated ? 2 : 1)`; [directionSign] is
  /// `convertToDirection(1, facing)` (`+1` for the positive side of the axis).
  double generatedSpeed(int movementDirection, int directionSign) {
    final speed = (isLit ? portableEngineSpeed : 0) * (movementDirection > 0 ? -1 : 1);
    return speed * directionSign * (superHeated ? 2 : 1);
  }

  /// One server tick of `PortableEngineBlockEntity.tick`'s fuel half.
  ///
  /// [nextFuelTicks] is `getBurnTime` of the stack in the slot, [slotCount] how
  /// many of it there are, [nextSuperHeated] `getSuperheatedBurnTime(stack) > 0`
  /// and [consumeOne] takes one item out of the slot (with its crafting
  /// remainder). Returns whether the comparator output changed, which is when
  /// Java updates the neighbours.
  bool tick({
    required int nextFuelTicks,
    required int slotCount,
    required bool nextSuperHeated,
    required void Function() consumeOne,
  }) {
    var neighbours = false;
    if (burnTime > 0 && !isCurrentFuelInfinite) {
      final before = analogPower(burnTime);
      burnTime--;
      neighbours = before != analogPower(burnTime);
    }
    if (burnTime <= 0 && slotCount > 0) {
      burnTime = nextFuelTicks;
      superHeated = nextSuperHeated;
      if (burnTime > 0) consumeOne();
    }
    if (burnTime <= 0) superHeated = false;
    return neighbours;
  }

  /// `useItemOn` with a creative blaze cake: superheat the current fuel, or
  /// toggle it off, or make the engine burn forever.
  void applyCreativeBlazeCake() {
    if (isCurrentFuelInfinite) {
      if (superHeated) {
        burnTime = 0;
        superHeated = false;
      } else {
        superHeated = true;
      }
    } else {
      burnTime = infiniteBurnThreshold;
    }
  }

  /// `tick`'s direction half: when the engine would turn against its network,
  /// Java moves the scroll box one step and re-generates.
  ///
  /// Returns the new `movementDirection`, or `null` when nothing changed.
  /// [generated] is the *cached* speed (`generatedSpeed` field), [speed] the
  /// network's, [directionSign] `convertToDirection(1, facing)` and
  /// [movementDirection] the scroll box's value.
  int? directionFix({
    required int movementDirection,
    required double speed,
    required int directionSign,
  }) {
    if (!isLit || speed == 0) return null;
    final wanted = (movementDirection > 0 ? -1 : 1) * directionSign;
    if (wanted.sign == speed.sign) return null;
    return (movementDirection + 1) % movementModeCount;
  }

  /// `read`/`write` of the three NBT keys.
  void read({required int burnTime, required bool superHeated, required bool eatingCake}) {
    this.burnTime = burnTime;
    this.superHeated = superHeated;
    this.eatingCake = eatingCake;
  }

  /// The `lit` state the block must have for the current burn time.
  bool get litState => isLit;
}

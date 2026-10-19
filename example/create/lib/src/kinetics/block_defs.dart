// `IRotate` / `ICogWheel` / `KineticBlock` rules as data (pure): which faces of
// a block have a shaft, the rotation axis of a state, cogwheel sizes. Every
// kinetic block of every module registers one [KineticBlockDef] by block key.
import 'geometry.dart';
import 'settings.dart';

/// How a kinetic block connects to its neighbours (Create's `IRotate`).
abstract class KineticBlockDef {
  const KineticBlockDef();

  /// `hasShaftTowards`: whether the block has a shaft sticking out of [face].
  bool hasShaftTowards(KState state, Dir face);

  /// `getRotationAxis`.
  KAxis rotationAxis(KState state);

  /// `getMinimumRequiredSpeedLevel`.
  SpeedLevel get minimumRequiredSpeedLevel => SpeedLevel.none;

  /// `hideStressImpact`.
  bool get hideStressImpact => false;

  /// `ICogWheel.isSmallCog` / `isLargeCog` / `isDedicatedCogWheel`.
  bool get isSmallCog => false;
  bool get isLargeCog => false;
  bool get isDedicatedCogWheel => false;

  /// `KineticBlock.areStatesKineticallyEquivalent`.
  bool areStatesKineticallyEquivalent(KState oldState, KState newState) {
    if (oldState.block != newState.block) return false;
    return rotationAxis(newState) == rotationAxis(oldState);
  }
}

/// A block whose axis is the state property [property] (shafts, cogwheels,
/// gearboxes, ...). [shaftAlongAxis] is `hasShaftTowards(face) = face.axis == axis`.
class AxisBlockDef extends KineticBlockDef {
  final String property;
  final bool shaftAlongAxis;
  final bool _small;
  final bool _large;
  final bool _dedicated;
  final bool _hideStress;
  final SpeedLevel _minSpeed;

  const AxisBlockDef({
    this.property = 'axis',
    this.shaftAlongAxis = true,
    bool smallCog = false,
    bool largeCog = false,
    bool dedicatedCog = false,
    bool hideStressImpact = false,
    SpeedLevel minimumRequiredSpeedLevel = SpeedLevel.none,
  }) : _small = smallCog,
       _large = largeCog,
       _dedicated = dedicatedCog,
       _hideStress = hideStressImpact,
       _minSpeed = minimumRequiredSpeedLevel;

  @override
  KAxis rotationAxis(KState state) => state.axisOf(property) ?? KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      shaftAlongAxis ? face.axis == rotationAxis(state) : face.axis != rotationAxis(state);

  @override
  bool get isSmallCog => _small;

  @override
  bool get isLargeCog => _large;

  @override
  bool get isDedicatedCogWheel => _dedicated;

  @override
  bool get hideStressImpact => _hideStress;

  @override
  SpeedLevel get minimumRequiredSpeedLevel => _minSpeed;
}

/// A block with a `facing` property whose shaft sticks out of the facing side
/// (creative motor) or the opposite side (hand crank), rotating on that axis.
class FacingBlockDef extends KineticBlockDef {
  final String property;

  /// Shaft on the facing side (`true`) or the opposite side (`false`).
  final bool shaftAtFront;
  final bool _hideStress;

  const FacingBlockDef({this.property = 'facing', this.shaftAtFront = true, bool hideStressImpact = false})
    : _hideStress = hideStressImpact;

  Dir facing(KState s) => s.dirOf(property) ?? Dir.north;

  @override
  KAxis rotationAxis(KState state) => facing(state).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) => face == (shaftAtFront ? facing(state) : facing(state).opposite);

  @override
  bool get hideStressImpact => _hideStress;
}

/// A block with a `facing` property whose shaft runs through the whole block on
/// the facing axis (water wheel).
class FacingAxisBlockDef extends FacingBlockDef {
  const FacingAxisBlockDef({super.property, super.hideStressImpact});

  @override
  bool hasShaftTowards(KState state, Dir face) => facing(state).axis == face.axis;
}

/// A block with a `facing` and an `axis_along_first` property
/// (`DirectionalAxisKineticBlock`: the gauges).
class DirectionalAxisBlockDef extends KineticBlockDef {
  const DirectionalAxisBlockDef();

  @override
  KAxis rotationAxis(KState state) {
    final pistonAxis = (state.dirOf('facing') ?? Dir.north).axis;
    final alongFirst = state.flag('axis_along_first');
    return switch (pistonAxis) {
      KAxis.x => alongFirst ? KAxis.y : KAxis.z,
      KAxis.y => alongFirst ? KAxis.x : KAxis.z,
      KAxis.z => alongFirst ? KAxis.x : KAxis.y,
    };
  }

  @override
  bool hasShaftTowards(KState state, Dir face) => face.axis == rotationAxis(state);
}

/// Encased cogwheels: the cog on the axis, shafts sticking out of the ends that
/// have `top_shaft` / `bottom_shaft`.
class EncasedCogDef extends KineticBlockDef {
  final bool large;

  const EncasedCogDef({required this.large});

  @override
  KAxis rotationAxis(KState state) => state.axisOf('axis') ?? KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      face.axis == rotationAxis(state) && state.flag(face.isPositive ? 'top_shaft' : 'bottom_shaft');

  @override
  bool get isSmallCog => !large;

  @override
  bool get isLargeCog => large;

  @override
  bool areStatesKineticallyEquivalent(KState oldState, KState newState) {
    if (newState.flag('top_shaft') != oldState.flag('top_shaft')) return false;
    if (newState.flag('bottom_shaft') != oldState.flag('bottom_shaft')) return false;
    return super.areStatesKineticallyEquivalent(oldState, newState);
  }
}

/// The sequenced gearshift: a horizontal axis, or vertical when `vertical` is set.
class SequencedGearshiftDef extends KineticBlockDef {
  const SequencedGearshiftDef();

  @override
  KAxis rotationAxis(KState state) => state.flag('vertical') ? KAxis.y : (state.axisOf('axis') ?? KAxis.x);

  @override
  bool hasShaftTowards(KState state, Dir face) {
    if (state.flag('vertical')) return face.axis.isVertical;
    return face.axis == (state.axisOf('axis') ?? KAxis.x);
  }

  @override
  bool areStatesKineticallyEquivalent(KState oldState, KState newState) => false;
}

/// The gearbox: shafts on every side but the axis (`face.axis != axis`).
class GearboxDef extends AxisBlockDef {
  const GearboxDef() : super(shaftAlongAxis: false);
}

/// The chain gearshift: the powered state is part of the kinetic state.
class ChainGearshiftDef extends AxisBlockDef {
  const ChainGearshiftDef();

  @override
  bool areStatesKineticallyEquivalent(KState oldState, KState newState) =>
      super.areStatesKineticallyEquivalent(oldState, newState) && oldState.flag('powered') == newState.flag('powered');
}

/// The cuckoo clock: the shaft sticks out of the back.
class CuckooClockDef extends KineticBlockDef {
  const CuckooClockDef();

  Dir facing(KState s) => s.dirOf('facing') ?? Dir.north;

  @override
  KAxis rotationAxis(KState state) => facing(state).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) => face == facing(state).opposite;
}

/// The turntable: a shaft at the bottom, vertical axis.
class TurntableDef extends KineticBlockDef {
  const TurntableDef();

  @override
  KAxis rotationAxis(KState state) => KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) => face == Dir.down;
}

/// The radii of the rotation indicator particles (`getParticleInitialRadius` /
/// `getParticleTargetRadius`) of a kinetic block: (initial, target).
(double, double) rotationIndicatorRadii(String blockKey) => switch (blockKey) {
  'create:shaft' || 'create:powered_shaft' => (.125, .35),
  'create:large_cogwheel' => (1, 1.125),
  'create:water_wheel' => (1, 1.125),
  'create:large_water_wheel' => (2.25, 2.5),
  'create:flywheel' => (1.75, 2),
  _ => (.75, .65),
};

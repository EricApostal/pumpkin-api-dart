// The `IRotate` rule of a block of *another component*, as data.
//
// A Pumpkin server runs every plugin in its own wasm instance, so `package:create`
// is compiled into each plugin and `KineticBlockRegistry` is per component: the
// defs an addon registers are invisible to the component that runs the kinetic
// network (Create's own plugin). The owner therefore cannot name the addon's def
// classes; it rebuilds the rule from a description, and this file is that
// description: [WireKineticDef] holds a small rule vocabulary with a JSON form,
// so the addon registers the *same* def locally (its fallback when no owner is
// loaded) and sends the description over `create.kinetics`. See
// `docs/kinetics-across-plugins.md`.
//
// Pure: no host imports, so the rules are unit tested on the plain VM.
import 'block_defs.dart';
import 'geometry.dart';
import 'settings.dart';

/// How a wire def finds the rotation axis of a state.
sealed class WireAxisRule {
  const WireAxisRule();

  KAxis axisOf(KState state);

  Map<String, Object?> toJson();

  /// Rebuilds a rule from [json] (`WireKineticDef.fromJson`).
  static WireAxisRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    return switch (kind) {
      'axisProperty' => WireAxisProperty(
        property: _string(json['property'], 'axis'),
        fallback: _axis(json['fallback'], KAxis.y),
      ),
      'facingProperty' => WireFacingProperty(
        property: _string(json['property'], 'facing'),
        fallback: _dir(json['fallback'], Dir.north),
      ),
      'perpendicularToFacing' => WirePerpendicularToFacing(
        facingProperty: _string(json['facingProperty'], 'facing'),
        alongFirstProperty: _string(json['alongFirstProperty'], 'axis_along_first'),
      ),
      'vertical' => const WireVertical(),
      _ => null,
    };
  }

  static String _string(Object? value, String fallback) =>
      value is String && value.isNotEmpty ? value : fallback;

  static KAxis _axis(Object? value, KAxis fallback) =>
      value is String ? (KAxis.fromName(value) ?? fallback) : fallback;

  static Dir _dir(Object? value, Dir fallback) =>
      value is String ? (Dir.fromName(value) ?? fallback) : fallback;
}

/// The axis of the state property [property] (`AxisBlockDef`).
final class WireAxisProperty extends WireAxisRule {
  final String property;
  final KAxis fallback;

  const WireAxisProperty({this.property = 'axis', this.fallback = KAxis.y});

  @override
  KAxis axisOf(KState state) => state.axisOf(property) ?? fallback;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'axisProperty',
    'property': property,
    'fallback': fallback.name,
  };
}

/// The axis of the direction property [property] (`FacingBlockDef`).
final class WireFacingProperty extends WireAxisRule {
  final String property;
  final Dir fallback;

  const WireFacingProperty({this.property = 'facing', this.fallback = Dir.north});

  Dir facingOf(KState state) => state.dirOf(property) ?? fallback;

  @override
  KAxis axisOf(KState state) => facingOf(state).axis;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'facingProperty',
    'property': property,
    'fallback': fallback.name,
  };
}

/// The axis perpendicular to `facing`, picked by a boolean
/// (`DirectionalAxisKineticBlock`: the gauges, the mounted potato cannon).
final class WirePerpendicularToFacing extends WireAxisRule {
  final String facingProperty;
  final String alongFirstProperty;

  const WirePerpendicularToFacing({
    this.facingProperty = 'facing',
    this.alongFirstProperty = 'axis_along_first',
  });

  @override
  KAxis axisOf(KState state) {
    final pistonAxis = (state.dirOf(facingProperty) ?? Dir.north).axis;
    final alongFirst = state.flag(alongFirstProperty);
    return switch (pistonAxis) {
      KAxis.x => alongFirst ? KAxis.y : KAxis.z,
      KAxis.y => alongFirst ? KAxis.x : KAxis.z,
      KAxis.z => alongFirst ? KAxis.x : KAxis.y,
    };
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'perpendicularToFacing',
    'facingProperty': facingProperty,
    'alongFirstProperty': alongFirstProperty,
  };
}

/// A vertical axis ([`VerticalShaftDef`]).
final class WireVertical extends WireAxisRule {
  const WireVertical();

  @override
  KAxis axisOf(KState state) => KAxis.y;

  @override
  Map<String, Object?> toJson() => const {'kind': 'vertical'};
}

/// Which faces of a state have a shaft.
sealed class WireShaftRule {
  const WireShaftRule();

  bool hasShaft(KState state, Dir face, KAxis axis);

  Map<String, Object?> toJson();

  static WireShaftRule? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['kind']) {
      'alongAxis' => const WireShaftAlongAxis(),
      'notAlongAxis' => const WireShaftNotAlongAxis(),
      'facingFront' => WireShaftFacing(
        property: _string(json['property'], 'facing'),
        front: true,
      ),
      'facingBack' => WireShaftFacing(property: _string(json['property'], 'facing')),
      'alongFacingAxis' => WireShaftAlongFacingAxis(
        property: _string(json['property'], 'facing'),
      ),
      'facingBackUnlessFlag' => WireShaftFacingBackUnlessFlag(
        flag: _string(json['flag'], 'assembled'),
        property: _string(json['property'], 'facing'),
      ),
      'verticalByFlag' => WireShaftVerticalByFlag(
        flag: _string(json['flag'], 'on_floor'),
        upWhenSet: json['upWhenSet'] == true,
      ),
      _ => null,
    };
  }

  static String _string(Object? value, String fallback) =>
      value is String && value.isNotEmpty ? value : fallback;
}

/// `face.axis == axis` (shafts, cogwheels).
final class WireShaftAlongAxis extends WireShaftRule {
  const WireShaftAlongAxis();

  @override
  bool hasShaft(KState state, Dir face, KAxis axis) => face.axis == axis;

  @override
  Map<String, Object?> toJson() => const {'kind': 'alongAxis'};
}

/// `face.axis != axis` (the gearbox: a shaft on every side but the axis).
final class WireShaftNotAlongAxis extends WireShaftRule {
  const WireShaftNotAlongAxis();

  @override
  bool hasShaft(KState state, Dir face, KAxis axis) => face.axis != axis;

  @override
  Map<String, Object?> toJson() => const {'kind': 'notAlongAxis'};
}

/// The facing side (`front`) or its opposite (`back`).
final class WireShaftFacing extends WireShaftRule {
  final String property;
  final bool front;

  const WireShaftFacing({this.property = 'facing', this.front = false});

  @override
  bool hasShaft(KState state, Dir face, KAxis axis) {
    final facing = state.dirOf(property) ?? Dir.north;
    return face == (front ? facing : facing.opposite);
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': front ? 'facingFront' : 'facingBack',
    'property': property,
  };
}

/// `face.axis == facing.axis` (the water wheel).
final class WireShaftAlongFacingAxis extends WireShaftRule {
  final String property;

  const WireShaftAlongFacingAxis({this.property = 'facing'});

  @override
  bool hasShaft(KState state, Dir face, KAxis axis) {
    final facing = state.dirOf(property) ?? Dir.north;
    return face.axis == facing.axis;
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'alongFacingAxis', 'property': property};
}

/// The shaft runs along the whole facing axis while [flag] is clear and sticks
/// out of the back once it is set: `SwivelBearingBlock.hasShaftTowards`
/// (`SwivelBearingBlock.java:90-94`), where the flag is `assembled` and the hinge
/// becomes the axis.
final class WireShaftFacingBackUnlessFlag extends WireShaftRule {
  final String flag;
  final String property;

  const WireShaftFacingBackUnlessFlag({
    required this.flag,
    this.property = 'facing',
  });

  @override
  bool hasShaft(KState state, Dir face, KAxis axis) {
    final facing = state.dirOf(property) ?? Dir.up;
    if (state.flag(flag)) return face == facing.opposite;
    return face.axis == facing.axis;
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'facingBackUnlessFlag',
    'flag': flag,
    'property': property,
  };
}

/// A vertical shaft on the top or the bottom face, picked by a boolean
/// ([`VerticalShaftDef`]: the smart propeller's `ceiling`, the steering wheel's
/// `on_floor`).
final class WireShaftVerticalByFlag extends WireShaftRule {
  final String flag;
  final bool upWhenSet;

  const WireShaftVerticalByFlag({required this.flag, required this.upWhenSet});

  @override
  bool hasShaft(KState state, Dir face, KAxis axis) =>
      face == (state.flag(flag) == upWhenSet ? Dir.up : Dir.down);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'verticalByFlag',
    'flag': flag,
    'upWhenSet': upWhenSet,
  };
}

/// A [KineticBlockDef] described as data, so the component that runs the network
/// can rebuild the rule of a block that belongs to another component.
///
/// The rules cover what the propagation reads: the rotation axis, the shaft
/// faces, cogwheel sizes and the kinetic equivalence of two states. An addon
/// whose rule cannot be written with them must say so (the rule is *not*
/// approximated silently: `KineticBlockDef`s outside this vocabulary are not
/// sent, and the owner does not connect their blocks).
final class WireKineticDef extends KineticBlockDef {
  final WireAxisRule axis;
  final WireShaftRule shaft;
  final bool smallCog;
  final bool largeCog;
  final bool dedicatedCog;
  final bool _hideStressImpact;
  final SpeedLevel minimumSpeed;

  /// State properties that are part of the kinetic state of this block: two
  /// states that differ in one of them are not kinetically equivalent
  /// (`ChainGearshiftBlock.areStatesKineticallyEquivalent` reads `powered`;
  /// the encased cogwheel reads `top_shaft`/`bottom_shaft`).
  final Set<String> kineticFlags;

  const WireKineticDef({
    required this.axis,
    required this.shaft,
    this.smallCog = false,
    this.largeCog = false,
    this.dedicatedCog = false,
    bool hideStressImpact = false,
    this.minimumSpeed = SpeedLevel.none,
    this.kineticFlags = const {},
  }) : _hideStressImpact = hideStressImpact;

  /// A shaft along the `axis` property (`RotatedPillarKineticBlock`).
  WireKineticDef.axis({
    String property = 'axis',
    Set<String> kineticFlags = const {},
  }) : this(
         axis: WireAxisProperty(property: property),
         shaft: const WireShaftAlongAxis(),
         kineticFlags: kineticFlags,
       );

  /// `DirectionalKineticBlock.hasShaftTowards = face == FACING.getOpposite()`.
  WireKineticDef.facingBack({String property = 'facing'}) : this(
    axis: WireFacingProperty(property: property),
    shaft: WireShaftFacing(property: property),
  );

  /// `DirectionalKineticBlock.hasShaftTowards = face == FACING` (the creative
  /// motor and the portable engine: the shaft comes out of the front).
  WireKineticDef.facingFront({String property = 'facing'}) : this(
    axis: WireFacingProperty(property: property),
    shaft: WireShaftFacing(property: property, front: true),
  );

  /// `face.axis == FACING.getAxis()`: a shaft through the whole facing axis
  /// (`FacingAxisBlockDef`, the water wheel).
  WireKineticDef.facingAxis({String property = 'facing'}) : this(
    axis: WireFacingProperty(property: property),
    shaft: WireShaftAlongFacingAxis(property: property),
  );

  /// A vertical axis with the shaft on the top or bottom face picked by a
  /// boolean ([`VerticalShaftDef`]).
  WireKineticDef.verticalByFlag({
    required String flag,
    required bool upWhenSet,
    Set<String> kineticFlags = const {},
  }) : this(
         axis: const WireVertical(),
         shaft: WireShaftVerticalByFlag(flag: flag, upWhenSet: upWhenSet),
         kineticFlags: kineticFlags,
       );

  /// The shat along the facing axis until a flag is set, then out of the back
  /// (`SwivelBearingBlock.hasShaftTowards`).
  WireKineticDef.facingBackUnlessFlag({
    required String flag,
    String property = 'facing',
  }) : this(
         axis: WireFacingProperty(property: property),
         shaft: WireShaftFacingBackUnlessFlag(flag: flag, property: property),
       );

  /// `DirectionalAxisKineticBlock`: the axis perpendicular to `facing`.
  WireKineticDef.perpendicularToFacing({
    String facingProperty = 'facing',
    String alongFirstProperty = 'axis_along_first',
  }) : this(
         axis: WirePerpendicularToFacing(
           facingProperty: facingProperty,
           alongFirstProperty: alongFirstProperty,
         ),
         shaft: const WireShaftAlongAxis(),
       );

  @override
  KAxis rotationAxis(KState state) => axis.axisOf(state);

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      shaft.hasShaft(state, face, axis.axisOf(state));

  @override
  bool get isSmallCog => smallCog;

  @override
  bool get isLargeCog => largeCog;

  @override
  bool get isDedicatedCogWheel => dedicatedCog;

  @override
  bool get hideStressImpact => _hideStressImpact;

  @override
  SpeedLevel get minimumRequiredSpeedLevel => minimumSpeed;

  @override
  bool areStatesKineticallyEquivalent(KState oldState, KState newState) {
    if (!super.areStatesKineticallyEquivalent(oldState, newState)) return false;
    for (final flag in kineticFlags) {
      if (oldState[flag] != newState[flag]) return false;
    }
    return true;
  }

  /// This rule as JSON (the wire form of `create.kinetics`).
  Map<String, Object?> toJson() => {
    'axis': axis.toJson(),
    'shaft': shaft.toJson(),
    if (smallCog) 'smallCog': true,
    if (largeCog) 'largeCog': true,
    if (dedicatedCog) 'dedicatedCog': true,
    if (hideStressImpact) 'hideStressImpact': true,
    if (minimumSpeed != SpeedLevel.none) 'minimumSpeed': minimumSpeed.name,
    if (kineticFlags.isNotEmpty) 'kineticFlags': kineticFlags.toList(),
  };

  /// Rebuilds a rule from [json]; `null` when it is not a wire def this version
  /// knows.
  static WireKineticDef? fromJson(Object? json) {
    if (json is! Map) return null;
    final axis = WireAxisRule.fromJson(json['axis']);
    final shaft = WireShaftRule.fromJson(json['shaft']);
    if (axis == null || shaft == null) return null;
    final speed = json['minimumSpeed'];
    return WireKineticDef(
      axis: axis,
      shaft: shaft,
      smallCog: json['smallCog'] == true,
      largeCog: json['largeCog'] == true,
      dedicatedCog: json['dedicatedCog'] == true,
      hideStressImpact: json['hideStressImpact'] == true,
      minimumSpeed: speed is String
          ? SpeedLevel.values.firstWhere(
              (v) => v.name == speed,
              orElse: () => SpeedLevel.none,
            )
          : SpeedLevel.none,
      kineticFlags: {
        for (final flag in (json['kineticFlags'] as List? ?? const []))
          if (flag is String) flag,
      },
    );
  }

  @override
  String toString() => 'WireKineticDef(${toJson()})';
}
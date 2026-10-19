// The wrench's rotation of kinetic blocks (`IWrenchable.getRotatedBlockState` and
// the overrides of encased cogwheels and chain drives), pure.
import 'geometry.dart';
import 'node.dart';

/// What the generic rotation needs to know about the properties of a block
/// (the property named `axis` or `facing` can be the horizontal-only variant).
final class RotationTraits {
  /// The `axis` property only has `x` and `z` (`HORIZONTAL_AXIS`).
  final bool horizontalAxisOnly;

  /// The `facing` property only has the four horizontal directions.
  final bool horizontalFacingOnly;

  const RotationTraits({this.horizontalAxisOnly = false, this.horizontalFacingOnly = false});
}

/// `IWrenchable.getRotatedBlockState(state, targetedFace)`.
KState wrenchRotatedState(KState original, Dir targetedFace, {RotationTraits traits = const RotationTraits()}) {
  final targetAxis = targetedFace.axis;

  if (targetAxis == KAxis.y) {
    if (original.has('axis') && traits.horizontalAxisOnly) {
      final a = original.axisOf('axis')!;
      return original.set('axis', a.positive.clockWise(KAxis.y).axis.name);
    }
    if (original.has('facing') && traits.horizontalFacingOnly) {
      return original.set('facing', original.dirOf('facing')!.clockWise(KAxis.y).name);
    }
  }

  if (original.has('axis') && !traits.horizontalAxisOnly) {
    final a = original.axisOf('axis')!;
    return original.set('axis', a.positive.clockWise(targetAxis).axis.name);
  }

  if (!original.has('facing') || traits.horizontalFacingOnly) return original;

  var newState = original;
  final stateFacing = original.dirOf('facing')!;

  if (stateFacing.axis == targetAxis) {
    if (original.has('axis_along_first')) return original.toggle('axis_along_first');
    return original;
  } else {
    do {
      newState = newState.set('facing', newState.dirOf('facing')!.clockWise(targetAxis).name);
      if (targetAxis == KAxis.y && newState.has('axis_along_first')) newState = newState.toggle('axis_along_first');
    } while (newState.dirOf('facing')!.axis == targetAxis);
  }
  return newState;
}

/// `EncasedCogwheelBlock.swapShaftsForRotation(state, CLOCKWISE_90, rotationAxis)`.
KState swapShaftsForRotation(KState state, KAxis rotationAxis) {
  final axis = state.axisOf('axis') ?? KAxis.y;
  if (axis == rotationAxis) return state;

  final swap = switch (rotationAxis) {
    KAxis.x => axis == KAxis.y,
    KAxis.y => axis == KAxis.z,
    KAxis.z => axis == KAxis.x,
  };
  return swap ? swapShafts(state) : state;
}

/// `EncasedCogwheelBlock.swapShafts`.
KState swapShafts(KState state) {
  final bottom = state['bottom_shaft'] ?? 'false';
  final top = state['top_shaft'] ?? 'false';
  return state.setAll({'bottom_shaft': top, 'top_shaft': bottom});
}

/// The wrench rotation for [state] of any kinetic block of this module.
KState wrenchRotate(KState state, Dir targetedFace, {RotationTraits traits = const RotationTraits(), required KineticBlockRegistry blocks}) {
  final path = state.path;
  if (path.endsWith('encased_cogwheel') || path.endsWith('encased_large_cogwheel')) {
    final swapped = swapShaftsForRotation(state, targetedFace.axis);
    return wrenchRotatedState(swapped, targetedFace, traits: traits);
  }
  if (blocks.isChainDrive(state) && state['part'] != 'none') {
    final axis = _connectionAxis(state);
    return wrenchRotatedState(state, axis.positive, traits: traits);
  }
  return wrenchRotatedState(state, targetedFace, traits: traits);
}

KAxis _connectionAxis(KState state) {
  final axis = state.axisOf('axis') ?? KAxis.y;
  final alongFirst = state.flag('axis_along_first');
  return alongFirst ? (axis == KAxis.x ? KAxis.y : KAxis.x) : (axis == KAxis.z ? KAxis.y : KAxis.z);
}

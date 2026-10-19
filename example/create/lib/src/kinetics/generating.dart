// `GeneratingKineticBlockEntity`: the logic of kinetic sources (pure mixin).
import 'geometry.dart';
import 'node.dart';
import 'network.dart';
import 'settings.dart';

/// Mixed into a node that generates rotation. The node reports its
/// [KineticNodeMixin.generatedSpeed] and calls [updateGeneratedRotation] when it
/// changes.
mixin GeneratingNodeMixin on KineticNodeMixin {
  bool reActivateSource = false;

  void notifyStressCapacityChange(double capacity) {
    getOrCreateNetwork()?.updateCapacityFor(this, capacity);
  }

  @override
  void removeSource() {
    if (hasSource && isSource) reActivateSource = true;
    super.removeSource();
  }

  @override
  void setSource(KPos source) {
    super.setSource(source);
    final sourceBE = level.nodeAt(source);
    if (sourceBE == null) return;
    if (reActivateSource && sourceBE.speed.abs() >= generatedSpeed.abs()) reActivateSource = false;
  }

  /// The generating part of `tick()`, call after the base tick.
  void generatingTick() {
    if (reActivateSource) {
      updateGeneratedRotation();
      reActivateSource = false;
    }
  }

  void updateGeneratedRotation() {
    final speed = generatedSpeed;
    final prevSpeed = speedValue;

    if (prevSpeed != speed) {
      if (!hasSource) {
        final levelBefore = SpeedLevel.of(speedValue, level.settings);
        final levelAfter = SpeedLevel.of(speed, level.settings);
        if (levelBefore != levelAfter) queueRotationIndicators();
      }

      applyNewSpeed(prevSpeed, speed);
    }

    if (hasNetwork && speed != 0) {
      final network = getOrCreateNetwork()!;
      notifyStressCapacityChange(calculateAddedStressCapacity());
      getOrCreateNetwork()!.updateStressFor(this, calculateStressApplied());
      network.updateStress();
    }

    onSpeedChanged(prevSpeed);
    sendData();
  }

  void applyNewSpeed(double prevSpeed, double speed) {
    // Speed changed to 0
    if (speed == 0) {
      if (hasSource) {
        notifyStressCapacityChange(0);
        getOrCreateNetwork()!.updateStressFor(this, calculateStressApplied());
        return;
      }
      detachKinetics();
      setSpeed(0);
      setNetwork(null);
      return;
    }

    // Now turning - create a new network
    if (prevSpeed == 0) {
      setSpeed(speed);
      setNetwork(createNetworkId());
      attachKinetics();
      return;
    }

    // Change speed when overpowered by another generator
    if (hasSource) {
      // Staying below the overpowered speed
      if (prevSpeed.abs() >= speed.abs()) {
        if (prevSpeed.sign != speed.sign) level.destroyBlock(kpos);
        return;
      }

      // Faster than the attached network -> become the new source
      detachKinetics();
      setSpeed(speed);
      source = null;
      setNetwork(createNetworkId());
      attachKinetics();
      return;
    }

    // Reapply source
    detachKinetics();
    setSpeed(speed);
    attachKinetics();
  }

  /// `createNetworkId()`: the packed position.
  int createNetworkId() => kpos.packed;
}

/// The network of a node (convenience for tests and tools).
KineticNetwork? networkOf(KineticNode node) => node.getOrCreateNetwork();

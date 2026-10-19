// The block entities of the kinetic blocks that do not generate speed:
// transmissions, gauges, chain drives, speed controller, flywheel, turntable,
// clock. Generators are in `generators.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/decoration.dart' show BracketedBlockEntityBehaviour;
import '../api/value_settings.dart';
import 'behaviours.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'node.dart';
import 'runtime.dart';
import 'sequence.dart';
import 'settings.dart';
import 'transmission.dart';

// -- Shafts and cogwheels ---------------------------------------------------------------

/// `BracketedKineticBlockEntity`: the block entity of shafts and cogwheels, which can
/// carry a bracket (`AbstractSimpleShaftBlock`).
class BracketedKineticBlockEntity extends SimpleKineticBlockEntity {
  late final BracketedBlockEntityBehaviour brackets;

  BracketedKineticBlockEntity(super.worldId, super.pos) {
    brackets = addBehaviour(
      BracketedBlockEntityBehaviour(
        canHave: (state) =>
            state.key == 'create:shaft' ||
            state.key == 'create:cogwheel' ||
            state.key == 'create:large_cogwheel',
      ),
    );
  }

  /// `AbstractSimpleShaftBlock.affectNeighborsAfterRemoval`: the bracket pops out.
  @override
  void onRemoved() {
    super.onRemoved();
    final w = world;
    if (w == null) return;
    unawaited(() async {
      final bracket = await brackets.removeBracket(inOnReplacedContext: true);
      if (bracket == null) return;
      await w.dropItem((
        pos.x + .5,
        pos.y + .5,
        pos.z + .5,
      ), ItemStacks.plain(bracket.key));
    }());
  }
}

// -- Transmission -----------------------------------------------------------------

/// `GearboxBlockEntity`.
class GearboxBlockEntity extends DirectionalShaftHalvesBlockEntity {
  GearboxBlockEntity(super.worldId, super.pos);

  /// `getAxisModifier` for a gearbox: forward along the source axis, reversed to
  /// the opposite side, and reversed again on the perpendicular faces.
  @override
  double shaftHalvesModifier(Dir direction) {
    return gearboxModifier(direction, sourceFacing);
  }
}

/// `SplitShaftBlockEntity`: the two halves of the shaft can turn differently.
abstract class SplitShaftBlockEntity extends DirectionalShaftHalvesBlockEntity {
  SplitShaftBlockEntity(super.worldId, super.pos);

  /// The factor between the source side and [face].
  double getRotationSpeedModifier(Dir face);

  @override
  double shaftHalvesModifier(Dir direction) =>
      getRotationSpeedModifier(direction);

  bool get poweredState => blockState.flag('powered');
}

/// `GearshiftBlockEntity`: reverses the far half when powered.
class GearshiftBlockEntity extends SplitShaftBlockEntity {
  GearshiftBlockEntity(super.worldId, super.pos);

  @override
  double getRotationSpeedModifier(Dir face) {
    return gearshiftModifier(
      hasSource: hasSource,
      face: face,
      sourceFacing: sourceFacing,
      powered: poweredState,
    );
  }
}

/// `ClutchBlockEntity`: disconnects the far half when powered.
class ClutchBlockEntity extends SplitShaftBlockEntity {
  ClutchBlockEntity(super.worldId, super.pos);

  @override
  double getRotationSpeedModifier(Dir face) {
    return clutchModifier(
      hasSource: hasSource,
      face: face,
      sourceFacing: sourceFacing,
      powered: poweredState,
    );
  }
}

/// `SequencedGearshiftBlockEntity`.
class SequencedGearshiftBlockEntity extends SplitShaftBlockEntity {
  List<Instruction> instructions = Instruction.createDefault();
  int currentInstruction = -1;
  int currentInstructionDuration = -1;
  double currentInstructionProgress = 0;
  int timer = 0;
  bool poweredPreviously = false;

  SequencedGearshiftBlockEntity(super.worldId, super.pos);

  @override
  void tick() {
    super.tick();

    if (isIdle) return;
    if (currentInstructionDuration < 0) return;
    if (timer < currentInstructionDuration) {
      timer++;
      currentInstructionProgress += getInstruction(currentInstruction)!
          .getTickProgress(speedValue);
      return;
    }
    run(currentInstruction + 1);
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    if (isIdle) return;
    final currentSpeed = speedValue.abs();
    if (previousSpeed.abs() == currentSpeed) return;
    final instruction = getInstruction(currentInstruction);
    if (instruction == null) return;
    if (speed == 0) run(-1);

    // Update the instruction time with regard to the new speed.
    currentInstructionDuration = instruction.getDuration(
      currentInstructionProgress,
      theoreticalSpeed,
    );
    timer = 0;
  }

  bool get isIdle => currentInstruction == -1;

  /// `onRedstoneUpdate`: called by the block when its scheduled tick runs.
  Future<void> onRedstoneUpdate(bool isPowered, bool isRunning) async {
    if (!poweredPreviously && isPowered) risingFlank();
    poweredPreviously = isPowered;
    if (!isIdle) return;
    if (isPowered == isRunning) return;
    final w = world;
    if (w == null) return;
    if (!await w.hasRedstoneNeighborSignal(pos)) {
      setStateAsync(blockState.set('state', '0'));
      return;
    }
    if (speed == 0) return;
    run(0);
  }

  void risingFlank() {
    final instruction = getInstruction(currentInstruction);
    if (instruction == null) return;
    if (poweredPreviously) return;
    poweredPreviously = true;

    switch (instruction.onRedstonePulse()) {
      case OnIsPoweredResult.continue_:
        run(currentInstruction + 1);
      case OnIsPoweredResult.nothing:
        break;
    }
  }

  void run(int instructionIndex) {
    final instruction = getInstruction(instructionIndex);
    if (instruction == null ||
        instruction.instruction == SequencerInstructions.end) {
      if (modifier != 0) detachKinetics();
      currentInstruction = -1;
      currentInstructionDuration = -1;
      currentInstructionProgress = 0;
      sequenceContext = null;
      timer = 0;
      unawaited(_resetStateIfUnpowered());
      return;
    }

    detachKinetics();
    currentInstructionDuration = instruction.getDuration(0, theoreticalSpeed);
    currentInstruction = instructionIndex;
    currentInstructionProgress = 0;
    sequenceContext = SequenceContext.fromGearshift(
      instruction.instruction,
      theoreticalSpeed * modifier,
      instruction.value,
    );
    timer = 0;
    setStateAsync(blockState.set('state', '${instructionIndex + 1}'));
  }

  Future<void> _resetStateIfUnpowered() async {
    final w = world;
    if (w == null) return;
    if (!await w.hasRedstoneNeighborSignal(pos)) {
      setStateAsync(blockState.set('state', '0'));
    } else {
      sendData();
    }
  }

  Instruction? getInstruction(int index) =>
      index >= 0 && index < instructions.length ? instructions[index] : null;

  @override
  void copySequenceContextFrom(KineticNode sourceBE) {}

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('InstructionIndex', currentInstruction);
    tag.putInt('InstructionDuration', currentInstructionDuration);
    tag.putFloat('InstructionProgress', currentInstructionProgress);
    tag.putInt('Timer', timer);
    tag.putBool('PrevPowered', poweredPreviously);
    tag.putList('Instructions', [
      for (final i in instructions)
        NbtCompound()
          ..putString('Type', i.instruction.javaName)
          ..putString('Modifier', i.speedModifier.javaName)
          ..putInt('Value', i.value),
    ]);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    currentInstruction = tag.getInt('InstructionIndex') ?? 0;
    currentInstructionDuration = tag.getInt('InstructionDuration') ?? 0;
    currentInstructionProgress = tag.getDouble('InstructionProgress') ?? 0;
    poweredPreviously = tag.getBool('PrevPowered') ?? false;
    timer = tag.getInt('Timer') ?? 0;
    final list = tag.getList('Instructions');
    if (list == null || list.isEmpty) {
      instructions = Instruction.createDefault();
    } else {
      instructions = [
        for (final e in list)
          if (e is NbtCompound)
            Instruction(
                SequencerInstructions.fromJavaName(e.getString('Type')),
                e.getInt('Value') ?? 0,
              )
              ..speedModifier = InstructionSpeedModifiers.fromJavaName(
                e.getString('Modifier'),
              ),
      ];
    }
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  double getRotationSpeedModifier(Dir face) =>
      (!hasSource || face == sourceFacing) ? 1 : modifier.toDouble();

  int get modifier {
    if (currentInstruction >= instructions.length) return 0;
    return isIdle ? 0 : instructions[currentInstruction].modifier;
  }
}

// -- Chain drives -----------------------------------------------------------------

/// `ChainGearshiftBlockEntity`: the adjustable chain gearshift's ratio follows the redstone signal.
class ChainGearshiftBlockEntity extends KineticBlockEntity
    implements ChainModifierNode {
  int signal = 0;
  bool signalChanged = false;

  ChainGearshiftBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 40;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('Signal', signal);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    signal = tag.getInt('Signal') ?? 0;
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  double get chainModifier => getModifierForSignal(signal);

  /// `neighbourChanged`: reads the strongest neighbouring signal.
  Future<void> neighbourChanged() async {
    final w = world;
    if (w == null) return;
    final power = await w.bestNeighborSignal(pos);
    if (power != signal) signalChanged = true;
  }

  @override
  void lazyTick() {
    super.lazyTick();
    unawaited(neighbourChanged());
  }

  @override
  void tick() {
    super.tick();
    if (signalChanged) {
      signalChanged = false;
      unawaited(_applySignal());
    }
  }

  Future<void> _applySignal() async {
    final w = world;
    if (w == null) return;
    analogSignalChanged(await w.bestNeighborSignal(pos));
  }

  void analogSignalChanged(int newSignal) {
    detachKinetics();
    removeSource();
    signal = newSignal;
    attachKinetics();
  }

  double getModifierForSignal(int newPower) {
    if (newPower == 0) return 1;
    return 1 + ((newPower + 1) / 16);
  }
}

// -- Gauges -----------------------------------------------------------------------

/// `GaugeBlockEntity`: the dial position and colour the client draws.
abstract class GaugeBlockEntity extends KineticBlockEntity {
  double dialTarget = 0;
  double dialState = 0;
  double prevDialState = 0;
  int color = 0;

  GaugeBlockEntity(super.worldId, super.pos);

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putFloat('Value', dialTarget);
    tag.putInt('Color', color);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    dialTarget = tag.getDouble('Value') ?? 0;
    color = tag.getInt('Color') ?? 0;
    super.read(tag, clientPacket: clientPacket);
  }

  /// The comparator output (`GaugeBlock.getAnalogOutputSignal`).
  int get analogOutput => (dialTarget * 14).clamp(0, 15).ceil();

  int _lastOutput = -1;

  /// `setChanged()` also updates comparators next to the block in Minecraft;
  /// only done when the analog output changed.
  @override
  void markChanged() {
    super.markChanged();
    final out = analogOutput;
    if (out == _lastOutput) return;
    _lastOutput = out;
    final w = world;
    if (w != null && !removed) unawaited(w.updateComparators(pos: pos));
  }
}

/// `SpeedGaugeBlockEntity` (speedometer).
class SpeedGaugeBlockEntity extends GaugeBlockEntity {
  SpeedGaugeBlockEntity(super.worldId, super.pos);

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    final s = speed.abs();

    dialTarget = getDialTarget(s, runtime.settings);
    color = mixColors(SpeedLevel.of(s, runtime.settings).color, 0xffffff, .25);

    markChanged();
  }

  /// `getDialTarget(speed)`.
  static double getDialTarget(double speed, KineticConfig c) {
    speed = speed.abs();
    final medium = c.mediumSpeed;
    final fast = c.fastSpeed;
    final max = c.maxRotationSpeed.toDouble();
    if (speed == 0) return 0;
    if (speed < medium) return lerp(speed / medium, 0, .45);
    if (speed < fast) return lerp((speed - medium) / (fast - medium), .45, .75);
    return lerp((speed - fast) / (max - fast), .75, 1.125);
  }
}

/// `StressGaugeBlockEntity` (stressometer).
class StressGaugeBlockEntity extends GaugeBlockEntity {
  StressGaugeBlockEntity(super.worldId, super.pos);

  @override
  void updateFromNetwork(
    double maxStress,
    double currentStress,
    int networkSize,
  ) {
    super.updateFromNetwork(maxStress, currentStress, networkSize);

    if (runtime.settings.disableStress) {
      dialTarget = 0;
    } else if (isOverStressed) {
      dialTarget = 1.125;
    } else if (maxStress == 0) {
      dialTarget = 0;
    } else {
      dialTarget = currentStress / maxStress;
    }

    if (dialTarget > 0) {
      if (dialTarget < .5) {
        color = mixColors(0x00FF00, 0xFFFF00, dialTarget * 2);
      } else if (dialTarget < 1) {
        color = mixColors(0xFFFF00, 0xFF0000, dialTarget * 2 - 1);
      } else {
        color = 0xFF0000;
      }
    }

    sendData();
    markChanged();
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    if (speed == 0) {
      dialTarget = 0;
      markChanged();
      return;
    }
    updateFromNetwork(capacity, stress, getOrCreateNetwork()?.size ?? 0);
  }

  double get networkStress => stress;
  double get networkCapacity => capacity;

  /// `onObserved()` (`GaugeObservedPacket`): awards advancements in Create; the
  /// hook is [onObservedHook].
  void onObserved() => onObservedHook?.call(this);

  /// Called when a player looked at the stressometer with goggles and the client
  /// told the server (the stressometer advancements).
  static void Function(StressGaugeBlockEntity gauge)? onObservedHook;
}

// -- Misc -------------------------------------------------------------------------

/// `FlywheelBlockEntity`: nothing to do on the server.
class FlywheelBlockEntity extends KineticBlockEntity {
  FlywheelBlockEntity(super.worldId, super.pos);
}

/// `TurntableBlockEntity`.
class TurntableBlockEntity extends KineticBlockEntity {
  TurntableBlockEntity(super.worldId, super.pos);
}

/// `SpeedControllerBlockEntity`.
class SpeedControllerBlockEntity extends KineticBlockEntity
    implements SpeedControllerNode, ValueSettingsHost {
  static const int defaultSpeed = 16;

  late final ScrollValueBehaviour targetSpeed;

  SpeedControllerBlockEntity(super.worldId, super.pos) {
    final max = KineticsRuntime.isLoaded
        ? runtime.settings.maxRotationSpeed
        : 256;
    targetSpeed = addBehaviour(
      KineticScrollValueBehaviour()
        ..between(-max, max)
        ..value = defaultSpeed
        ..withCallback((_) => updateTargetRotation()),
    );
  }

  @override
  int get targetSpeedValue => targetSpeed.getValue();

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [targetSpeed];

  void updateTargetRotation() {
    if (hasNetwork) getOrCreateNetwork()?.remove(this);
    detachKinetics();
    removeSource();
    attachKinetics();
  }
}

/// `CuckooClockBlockEntity`: plays the pig / creeper animation at noon and in
/// the evening (the creeper "surprise" explodes the mysterious clock).
class CuckooClockBlockEntity extends KineticBlockEntity {
  static const List<String> animationNames = [
    'PIG',
    'CREEPER',
    'SURPRISE',
    'NONE',
  ];

  String animationType = 'NONE';
  double animationProgress = 0;
  bool _sendAnimationUpdate = false;

  CuckooClockBlockEntity(super.worldId, super.pos);

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    // The framework writes the save tag before the client tag of the same flush,
    // so the flag is only cleared by the client write (Java's `write` sees only
    // one of the two).
    if (clientPacket && _sendAnimationUpdate) {
      tag.putString('Animation', animationType);
      _sendAnimationUpdate = false;
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    // `Animation` is client-only state: the server never reads it back, but a
    // client update tag (`readClient`) restarts the animation at its first tick.
    // An unknown name falls back to the first constant, as Java's `readEnum`.
    if (clientPacket && tag.containsKey('Animation')) {
      final name = tag.getString('Animation');
      animationType = animationNames.contains(name)
          ? name!
          : animationNames.first;
      animationProgress = 0;
    }
  }

  @override
  void tick() {
    super.tick();
    if (speed == 0) return;

    final w = world;
    if (w == null) return;

    // Hasn't a fixed time: the overworld (the nether and the end are fixed).
    final isNatural = w.getDimension() == 'minecraft:overworld';
    if (!isNatural) return;
    final dayTime = w.getTimeOfDay() % 24000;
    final hours = (dayTime ~/ 1000 + 6) % 24;
    final minutes = (dayTime % 1000) * 60 ~/ 1000;

    if (animationType == 'NONE') {
      if (hours == 12 && minutes < 5) startAnimation('PIG');
      if (hours == 18 && minutes < 36 && minutes > 31)
        startAnimation('CREEPER');
    } else {
      final value = animationProgress;
      animationProgress = value + 1;
      if (value > 100) animationType = 'NONE';

      if (animationType == 'SURPRISE' &&
          (animationProgress - 50).abs() < 1e-5) {
        final center = (pos.x + .5, pos.y + .5, pos.z + .5);
        unawaited(() async {
          await w.breakBlock(pos, drop: false);
          await w.createExplosion(
            pos: center,
            power: 3,
            createFire: false,
            interaction: ExplosionInteraction.block,
          );
        }());
      }
    }
  }

  void startAnimation(String animation) {
    animationType = animation;
    if (blockState.isCreate('mysterious_cuckoo_clock'))
      animationType = 'SURPRISE';
    animationProgress = 0;
    _sendAnimationUpdate = true;
    sendData();
  }
}

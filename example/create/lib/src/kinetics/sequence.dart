// The sequenced gearshift's instruction model and `SequenceContext` (pure).
import 'settings.dart';

/// `SequencerInstructions`.
enum SequencerInstructions {
  turnAngle(hasValue: true, hasSpeed: true, maxValue: 360, shiftStep: 45, defaultValue: 90),
  turnDistance(hasValue: true, hasSpeed: true, maxValue: 128, shiftStep: 5, defaultValue: 5),
  delay(hasValue: true, hasSpeed: false, maxValue: 600, shiftStep: 20, defaultValue: 10),
  await_(hasValue: false, hasSpeed: false, maxValue: -1, shiftStep: -1, defaultValue: -1),
  end(hasValue: false, hasSpeed: false, maxValue: -1, shiftStep: -1, defaultValue: -1);

  final bool hasValue;
  final bool hasSpeed;
  final int maxValue;
  final int shiftStep;
  final int defaultValue;

  const SequencerInstructions({
    required this.hasValue,
    required this.hasSpeed,
    required this.maxValue,
    required this.shiftStep,
    required this.defaultValue,
  });

  /// The Java enum constant name (`TURN_ANGLE`), used in NBT.
  String get javaName => switch (this) {
    SequencerInstructions.turnAngle => 'TURN_ANGLE',
    SequencerInstructions.turnDistance => 'TURN_DISTANCE',
    SequencerInstructions.delay => 'DELAY',
    SequencerInstructions.await_ => 'AWAIT',
    SequencerInstructions.end => 'END',
  };

  bool get needsPropagation => this == turnAngle || this == turnDistance;

  static SequencerInstructions fromJavaName(String? name) {
    for (final v in values) {
      if (v.javaName == name) return v;
    }
    return SequencerInstructions.turnAngle;
  }
}

/// `InstructionSpeedModifiers`.
enum InstructionSpeedModifiers {
  forwardFast(2, 'FORWARD_FAST'),
  forward(1, 'FORWARD'),
  back(-1, 'BACK'),
  backFast(-2, 'BACK_FAST');

  final int value;
  final String javaName;

  const InstructionSpeedModifiers(this.value, this.javaName);

  static InstructionSpeedModifiers fromJavaName(String? name) {
    for (final v in values) {
      if (v.javaName == name) return v;
    }
    return InstructionSpeedModifiers.forwardFast;
  }

  static InstructionSpeedModifiers byModifier(int modifier) {
    for (final v in values) {
      if (v.value == modifier) return v;
    }
    return InstructionSpeedModifiers.forward;
  }
}

/// `OnIsPoweredResult`.
enum OnIsPoweredResult { nothing, continue_ }

/// One step of a sequence (`Instruction`).
final class Instruction {
  SequencerInstructions instruction;
  InstructionSpeedModifiers speedModifier;
  int value;

  Instruction(this.instruction, [this.value = 1, this.speedModifier = InstructionSpeedModifiers.forward]);

  /// `getDuration(currentProgress, speed)` in ticks (-1: wait for a pulse).
  int getDuration(double currentProgress, double speed) {
    speed *= speedModifier.value;
    speed = speed.abs();
    final target = value - currentProgress;
    switch (instruction) {
      case SequencerInstructions.turnAngle:
        final degreesPerTick = convertToAngular(speed);
        return (target / degreesPerTick).ceil() + 2;
      case SequencerInstructions.turnDistance:
        final metersPerTick = convertToLinear(speed);
        return (target / metersPerTick).ceil() + 2;
      case SequencerInstructions.delay:
        return target.toInt();
      case SequencerInstructions.await_:
        return -1;
      case SequencerInstructions.end:
        return 0;
    }
  }

  /// `getTickProgress(speed)`.
  double getTickProgress(double speed) => switch (instruction) {
    SequencerInstructions.turnAngle => convertToAngular(speed),
    SequencerInstructions.turnDistance => convertToLinear(speed),
    SequencerInstructions.delay => 1,
    _ => 0,
  };

  int get modifier => switch (instruction) {
    SequencerInstructions.turnAngle || SequencerInstructions.turnDistance => speedModifier.value,
    _ => 0,
  };

  OnIsPoweredResult onRedstonePulse() =>
      instruction == SequencerInstructions.await_ ? OnIsPoweredResult.continue_ : OnIsPoweredResult.nothing;

  /// `Instruction.createDefault()`.
  static List<Instruction> createDefault() => [
    Instruction(SequencerInstructions.turnAngle, 90),
    Instruction(SequencerInstructions.end),
  ];

  Map<String, Object> toMap() => {'Type': instruction.javaName, 'Modifier': speedModifier.javaName, 'Value': value};

  /// `Instruction.deserialize`: a missing `Modifier` reads the first enum constant.
  static Instruction fromMap(Map<String, Object?> m) {
    final i = Instruction(SequencerInstructions.fromJavaName(m['Type'] as String?));
    i.speedModifier = InstructionSpeedModifiers.fromJavaName(m['Modifier'] as String?);
    i.value = (m['Value'] as int?) ?? 0;
    return i;
  }
}

/// `SequencedGearshiftBlockEntity.SequenceContext`.
final class SequenceContext {
  final SequencerInstructions instruction;
  final double relativeValue;

  const SequenceContext(this.instruction, this.relativeValue);

  /// `fromGearshift`: `null` for instructions that need no propagation.
  static SequenceContext? fromGearshift(SequencerInstructions instruction, double kineticSpeed, int absoluteValue) =>
      instruction.needsPropagation
          ? SequenceContext(instruction, kineticSpeed == 0 ? 0 : absoluteValue / kineticSpeed)
          : null;

  double getEffectiveValue(double speedAtTarget) => (relativeValue * speedAtTarget).abs();
}

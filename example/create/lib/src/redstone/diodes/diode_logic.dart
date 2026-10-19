// Create's diodes as pure logic: the vanilla `DiodeBlock` rules the latches inherit,
// `ToggleLatchBlock`, `PoweredLatchBlock` and the three brass diode block entities
// (`PulseRepeaterBlockEntity`, `PulseExtenderBlockEntity`, `PulseTimerBlockEntity`).
// The host glue (`diode_blocks.dart`) feeds them states and applies the results.
import 'dart:math' as math;

import '../../common/common.dart';

/// What a diode can ask of the world (the vanilla `Level` calls of `DiodeBlock`).
abstract interface class DiodeEnv {
  /// `level.getSignal(pos.relative(d), d)`: the power [reader] receives from side [d].
  Future<int> signalFrom(Pos reader, Direction d);

  /// The `power` of the redstone wire at [pos], `null` if the block there is not wire.
  int? wirePowerAt(Pos pos);

  /// `FACING` of the diode (`DiodeBlock` subclass: repeater, comparator, Create diodes)
  /// at [pos], `null` if the block there is not a diode.
  Direction? diodeFacingAt(Pos pos);
}

/// The block state of a diode as far as the logic cares.
final class DiodeState {
  final Direction facing;
  final bool powered;
  final bool powering;
  final bool poweredSide;
  final bool inverted;

  const DiodeState({
    required this.facing,
    this.powered = false,
    this.powering = false,
    this.poweredSide = false,
    this.inverted = false,
  });

  DiodeState copyWith({bool? powered, bool? powering, bool? poweredSide}) => DiodeState(
    facing: facing,
    powered: powered ?? this.powered,
    powering: powering ?? this.powering,
    poweredSide: poweredSide ?? this.poweredSide,
    inverted: inverted,
  );

  @override
  bool operator ==(Object other) =>
      other is DiodeState &&
      other.facing == facing &&
      other.powered == powered &&
      other.powering == powering &&
      other.poweredSide == poweredSide &&
      other.inverted == inverted;

  @override
  int get hashCode => Object.hash(facing, powered, powering, poweredSide, inverted);

  @override
  String toString() => 'DiodeState($facing powered=$powered powering=$powering side=$poweredSide inv=$inverted)';
}

/// A scheduled block tick request.
final class TickRequest {
  final int delay;

  /// The `TickPriority` name: `extremelyHigh`, `veryHigh`, `high`.
  final String priority;

  const TickRequest(this.delay, this.priority);

  @override
  bool operator ==(Object other) => other is TickRequest && other.delay == delay && other.priority == priority;

  @override
  int get hashCode => Object.hash(delay, priority);

  @override
  String toString() => 'TickRequest($delay, $priority)';
}

/// The result of a diode `tick`: the state to write (equal to the input when unchanged)
/// and a tick to schedule afterwards, if any.
final class DiodeTickResult {
  final DiodeState state;
  final TickRequest? schedule;

  const DiodeTickResult(this.state, [this.schedule]);
}

/// The kinds of redstone latches Create has.
enum LatchKind {
  /// `ToggleLatchBlock`: a pulse flips the output.
  toggle,

  /// `PoweredLatchBlock`: a set (back) and reset (side) input.
  powered,
}

/// The shared logic of `DiodeBlock` + the Create latches. [delay] is `getDelay(state)`.
final class LatchLogic {
  final LatchKind kind;
  final DiodeEnv env;

  const LatchLogic(this.kind, this.env);

  /// `ToggleLatchBlock.getDelay` / `PoweredLatchBlock` (inherited): 1 tick.
  int get delay => 1;

  /// `DiodeBlock.getInputSignal`.
  Future<int> inputSignal(Pos pos, DiodeState state) async {
    final direction = state.facing;
    final relative = pos.relative(direction);
    final i = await env.signalFrom(pos, direction);
    if (i >= 15) return i;
    return math.max(i, env.wirePowerAt(relative) ?? 0);
  }

  /// `DiodeBlock.shouldTurnOn`.
  Future<bool> shouldTurnOn(Pos pos, DiodeState state) async => await inputSignal(pos, state) > 0;

  /// `DiodeBlock.shouldPrioritize`: a diode behind this one that faces another way.
  bool shouldPrioritize(Pos pos, DiodeState state) {
    final facing = env.diodeFacingAt(pos.relative(state.facing.opposite));
    return facing != null && facing != state.facing;
  }

  /// `PoweredLatchBlock.isPoweredOnSides`.
  Future<bool> isPoweredOnSides(Pos pos, DiodeState state) async {
    final left = state.facing.clockWise;
    final right = state.facing.counterClockWise;
    for (final d in [left, right]) {
      final i = await env.signalFrom(pos, d);
      if (i > 0) return true;
      final wire = env.wirePowerAt(pos.relative(d));
      if (wire != null && wire > 0) return true;
    }
    return false;
  }

  /// `checkTickOnNeighbor`: the tick to schedule after a neighbour update, or null.
  /// ([alreadyTicking] stands for `getBlockTicks().willTickThisTick`.)
  Future<TickRequest?> checkTickOnNeighbor(Pos pos, DiodeState state, {bool alreadyTicking = false}) async {
    final back = state.powered;
    final shouldBack = await shouldTurnOn(pos, state);
    final prioritize = shouldPrioritize(pos, state);

    if (kind == LatchKind.toggle) {
      // DiodeBlock.checkTickOnNeighbor (isLocked is false for Create's diodes).
      if (back != shouldBack && !alreadyTicking) {
        return TickRequest(delay, prioritize ? 'extremelyHigh' : (back ? 'veryHigh' : 'high'));
      }
      return null;
    }

    final side = state.poweredSide;
    final shouldSide = await isPoweredOnSides(pos, state);
    var priority = 'high';
    if (prioritize) {
      priority = 'extremelyHigh';
    } else if (side || back) {
      priority = 'veryHigh';
    }
    if (alreadyTicking) return null;
    if (back != shouldBack || side != shouldSide) return TickRequest(delay, priority);
    return null;
  }

  /// `tick`: the new state after a scheduled tick.
  Future<DiodeTickResult> tick(Pos pos, DiodeState state) async {
    if (kind == LatchKind.toggle) return _toggleTick(pos, state);
    return _poweredTick(pos, state);
  }

  Future<DiodeTickResult> _vanillaTick(Pos pos, DiodeState state) async {
    // DiodeBlock.tick (isLocked is false).
    final powered = state.powered;
    final shouldTurnOn = await this.shouldTurnOn(pos, state);
    if (powered && !shouldTurnOn) return DiodeTickResult(state.copyWith(powered: false));
    if (!powered) {
      final next = state.copyWith(powered: true);
      if (!shouldTurnOn) return DiodeTickResult(next, TickRequest(delay, 'veryHigh'));
      return DiodeTickResult(next);
    }
    return DiodeTickResult(state);
  }

  Future<DiodeTickResult> _toggleTick(Pos pos, DiodeState state) async {
    final poweredPreviously = state.powered;
    final r = await _vanillaTick(pos, state);
    var next = r.state;
    if (next.powered && !poweredPreviously) next = next.copyWith(powering: !next.powering);
    return DiodeTickResult(next, r.schedule);
  }

  Future<DiodeTickResult> _poweredTick(Pos pos, DiodeState state) async {
    final back = state.powered;
    final shouldBack = await shouldTurnOn(pos, state);
    final side = state.poweredSide;
    final shouldSide = await isPoweredOnSides(pos, state);
    var next = state;

    if (back != shouldBack) {
      next = next.copyWith(powered: shouldBack);
      if (shouldBack) {
        next = next.copyWith(powering: true);
      } else if (side) {
        next = next.copyWith(powering: false);
      }
    }

    if (side != shouldSide) {
      next = next.copyWith(poweredSide: shouldSide);
      if (shouldSide) {
        next = next.copyWith(powering: false);
      } else if (back) {
        next = next.copyWith(powering: true);
      }
    }
    return DiodeTickResult(next);
  }

  /// `ToggleLatchBlock.getOutputSignal`.
  static int outputSignal(DiodeState state) => state.powering ? 15 : 0;

  /// `ToggleLatchBlock.getSignal` / `getDirectSignal`: output towards the front only.
  /// [side] is the vanilla `side` (direction from the reader to the block).
  static int signal(DiodeState state, Direction side) => state.facing == side ? outputSignal(state) : 0;

  /// `activated` of the toggle latch (and the powered latch when [PoweredLatchBlock] allows it):
  /// whether a click flips `powering`.
  static bool canActivate(LatchKind kind, DiodeState state) {
    if (kind == LatchKind.toggle) return true;
    return state.powered == state.poweredSide;
  }

  /// `shouldRedstoneWireConnectTo` of the latches (toggle: axis of facing; powered: any horizontal side).
  static bool wireConnects(LatchKind kind, DiodeState state, Direction? side) {
    if (side == null) return false;
    if (kind == LatchKind.powered) return side.axis.isHorizontal;
    return side.axis == state.facing.axis;
  }
}

/// The pulse behaviours of the three brass diodes.
enum BrassDiodeKind { repeater, extender, timer }

/// The block entity part of the brass diodes: [state] counts ticks, [maxState] is
/// the configured interval.
final class BrassDiodeMachine {
  final BrassDiodeKind kind;
  int state;
  int maxState;

  BrassDiodeMachine(this.kind, {this.state = 0, int? maxState}) : maxState = maxState ?? defaultValue(kind);

  /// `defaultValue()`: 20 for the timer, 2 for the others.
  static int defaultValue(BrassDiodeKind kind) => kind == BrassDiodeKind.timer ? 20 : 2;

  /// `BrassDiodeBlockEntity.getProgress`.
  double get progress {
    final max = math.max(2, maxState);
    return state.clamp(0, max) / max;
  }

  bool get isIdle => state == 0;

  /// `onMaxDelayChanged`.
  void onMaxDelayChanged(int newMax) {
    maxState = newMax;
    state = state.clamp(0, newMax);
  }

  /// One `tick()` of the block entity: [powered] and [powering] are the block state values.
  /// Returns the new value for `POWERING` when the block state has to change, else null.
  bool? tick({required bool powered, required bool powering}) {
    final atMin = state <= 0;
    return switch (kind) {
      BrassDiodeKind.repeater => _repeater(powered, powering, atMin),
      BrassDiodeKind.extender => _extender(powered, powering, atMin),
      BrassDiodeKind.timer => _timer(powered, powering),
    };
  }

  /// `PulseRepeaterBlockEntity.updateState`.
  bool? _repeater(bool powered, bool powering, bool atMin) {
    if (atMin && !powered) return null;
    if (state > maxState + 1) {
      if (!powered && !powering) state = 0;
      return null;
    }

    state++;

    bool? result;
    if (state == maxState - 1 && !powering) result = true;
    if (state == maxState + 1 && powering) result = false;
    return result;
  }

  /// `PulseExtenderBlockEntity.updateState`.
  bool? _extender(bool powered, bool powering, bool atMin) {
    if (atMin && !powered) return null;
    if (atMin || powered) {
      state = maxState;
      return true;
    }

    if (state == 1) {
      bool? result;
      if (powering) result = false;
      if (!powered) state = 0;
      return result;
    }

    if (!powered) state--;
    return null;
  }

  /// `PulseTimerBlockEntity.updateState`.
  bool? _timer(bool powered, bool powering) {
    if (powered || state >= maxState - 1) {
      state = 0;
    } else {
      state++;
    }

    final shouldPower = !powered && (maxState == 2 ? state == 0 : state <= 1);
    if (powering != shouldPower) return shouldPower;
    return null;
  }

  /// `BrassDiodeBlock.getOutputSignal`: `POWERING ^ INVERTED`.
  static int outputSignal({required bool powering, required bool inverted}) => (powering != inverted) ? 15 : 0;

  /// `BrassDiodeBlockEntity.format`: the interval as `Nt`, `Ns` or `Nm`.
  static String format(int value) {
    if (value < 60) return '${value}t';
    if (value < 20 * 60) return '${value ~/ 20}s';
    return '${value ~/ 20 ~/ 60}m';
  }

  /// `getValueSettings` of `BrassDiodeScrollValueBehaviour`: the `(row, value)` of an interval
  /// in ticks (row 0 ticks, 1 seconds, 2 minutes).
  static (int row, int value) toValueSettings(int value) {
    var row = 0;
    if (value > 60 * 20) {
      value = value ~/ (60 * 20);
      row = 2;
    } else if (value > 60) {
      value = value ~/ 20;
      row = 1;
    }
    return (row, value);
  }

  /// `setValueSettings`: the interval in ticks for a `(row, value)` pick.
  static int fromValueSettings(int row, int value) {
    final multiplier = switch (row) {
      0 => 1,
      1 => 20,
      _ => 60 * 20,
    };
    return math.max(2, math.max(1, value) * multiplier);
  }

  /// `formatSettings` of the scroll behaviour.
  static String formatSettings(int row, int value) {
    final v = math.max(1, value);
    return switch (row) {
      0 => '${math.max(2, v)}t',
      1 => '0:${v < 10 ? '0' : ''}$v',
      _ => '$v:00',
    };
  }
}

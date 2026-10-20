import 'package:create/src/common/common.dart';
import 'package:create/src/redstone/diodes/diode_logic.dart';
import 'package:test/test.dart';

/// A diode environment: signals by (reader, direction).
class FakeDiodeEnv implements DiodeEnv {
  final Map<(Pos, Direction), int> signals = {};
  final Map<Pos, int> wires = {};
  final Map<Pos, Direction> diodes = {};

  @override
  Future<int> signalFrom(Pos reader, Direction d) async => signals[(reader, d)] ?? 0;

  @override
  int? wirePowerAt(Pos pos) => wires[pos];

  @override
  Direction? diodeFacingAt(Pos pos) => diodes[pos];
}

/// Runs a brass diode for [ticks] ticks with [powered] as a function of the tick and
/// returns the ticks at which `powering` was on.
List<int> simulate(BrassDiodeMachine m, int ticks, bool Function(int tick) powered, {bool powering = false}) {
  final on = <int>[];
  for (var t = 1; t <= ticks; t++) {
    final change = m.tick(powered: powered(t), powering: powering);
    if (change != null) powering = change;
    if (powering) on.add(t);
  }
  return on;
}

void main() {
  group('pulse timer', () {
    test('emits a two tick pulse every interval', () {
      final m = BrassDiodeMachine(BrassDiodeKind.timer, maxState: 20);
      final on = simulate(m, 62, (_) => false);
      // state: 1 at tick 1 (<= 1 powers), 2..19 off, 0 at tick 20 and 1 at tick 21 on, ...
      expect(on, [1, 20, 21, 40, 41, 60, 61]);
    });

    test('an interval of 2 ticks alternates every tick', () {
      final m = BrassDiodeMachine(BrassDiodeKind.timer, maxState: 2);
      final on = simulate(m, 8, (_) => false);
      expect(on, [2, 4, 6, 8]);
    });

    test('a powered timer resets and stays off', () {
      final m = BrassDiodeMachine(BrassDiodeKind.timer, maxState: 20);
      simulate(m, 5, (_) => false);
      final change = m.tick(powered: true, powering: true);
      expect(change, false);
      expect(m.state, 0);
      expect(m.tick(powered: true, powering: false), isNull);
    });

    test('default interval is 20 ticks for the timer and 2 for the others', () {
      expect(BrassDiodeMachine.defaultValue(BrassDiodeKind.timer), 20);
      expect(BrassDiodeMachine.defaultValue(BrassDiodeKind.repeater), 2);
      expect(BrassDiodeMachine.defaultValue(BrassDiodeKind.extender), 2);
    });
  });

  group('pulse repeater', () {
    test('turns a long signal into a short pulse after the delay', () {
      final m = BrassDiodeMachine(BrassDiodeKind.repeater, maxState: 2);
      final on = simulate(m, 12, (t) => t >= 1);
      // on at state max-1 (tick 1), off at state max+1 (tick 3); then waits for the input to end.
      expect(on, [1, 2]);
      expect(m.state, 4);
    });

    test('a longer delay pulses later', () {
      final m = BrassDiodeMachine(BrassDiodeKind.repeater, maxState: 10);
      final on = simulate(m, 30, (t) => t >= 1);
      // powering at state 9 (tick 9), off at state 11 (tick 11)
      expect(on, [9, 10]);
    });

    test('releasing the input rearms the repeater', () {
      final m = BrassDiodeMachine(BrassDiodeKind.repeater, maxState: 2);
      simulate(m, 6, (t) => true);
      expect(m.state, 4);
      m.tick(powered: false, powering: false);
      expect(m.state, 0);
      expect(m.tick(powered: true, powering: false), true);
    });

    test('an input that ends early does not pulse', () {
      final m = BrassDiodeMachine(BrassDiodeKind.repeater, maxState: 10);
      // powered only for 3 ticks: state counts up to 3, then the input is gone and it idles at
      // state 3... which is not idle (atMin is false) so it keeps counting like Java.
      final on = simulate(m, 40, (t) => t <= 3);
      expect(on, isNotEmpty);
    });
  });

  group('pulse extender', () {
    test('keeps the output on for the delay after the input ends', () {
      final m = BrassDiodeMachine(BrassDiodeKind.extender, maxState: 5);
      final on = simulate(m, 20, (t) => t <= 3);
      // on from tick 1; the input ends after tick 3; the counter runs 5 -> 1 over ticks 4..7 and
      // the output goes off on tick 8.
      expect(on.first, 1);
      expect(on.last, 7);
      expect(m.state, 0);
    });

    test('idle stays idle', () {
      final m = BrassDiodeMachine(BrassDiodeKind.extender);
      expect(m.tick(powered: false, powering: false), isNull);
      expect(m.isIdle, isTrue);
    });
  });

  group('brass diode helpers', () {
    test('the interval formats as ticks, seconds and minutes', () {
      expect(BrassDiodeMachine.format(20), '20t');
      expect(BrassDiodeMachine.format(59), '59t');
      expect(BrassDiodeMachine.format(60), '3s');
      expect(BrassDiodeMachine.format(20 * 59), '59s');
      expect(BrassDiodeMachine.format(20 * 60), '1m');
      expect(BrassDiodeMachine.format(20 * 60 * 5), '5m');
    });

    test('value settings round trip for the rows', () {
      expect(BrassDiodeMachine.toValueSettings(2), (0, 2));
      expect(BrassDiodeMachine.toValueSettings(60), (0, 60));
      expect(BrassDiodeMachine.toValueSettings(100), (1, 5));
      expect(BrassDiodeMachine.toValueSettings(20 * 60), (1, 60));
      expect(BrassDiodeMachine.toValueSettings(20 * 60 * 3), (2, 3));
      expect(BrassDiodeMachine.fromValueSettings(0, 1), 2);
      expect(BrassDiodeMachine.fromValueSettings(0, 30), 30);
      expect(BrassDiodeMachine.fromValueSettings(1, 5), 100);
      expect(BrassDiodeMachine.fromValueSettings(2, 3), 3600);
    });

    test('settings are formatted like the board', () {
      expect(BrassDiodeMachine.formatSettings(0, 1), '2t');
      expect(BrassDiodeMachine.formatSettings(0, 30), '30t');
      expect(BrassDiodeMachine.formatSettings(1, 5), '0:05');
      expect(BrassDiodeMachine.formatSettings(1, 30), '0:30');
      expect(BrassDiodeMachine.formatSettings(2, 4), '4:00');
    });

    test('the output is POWERING xor INVERTED', () {
      expect(BrassDiodeMachine.outputSignal(powering: true, inverted: false), 15);
      expect(BrassDiodeMachine.outputSignal(powering: false, inverted: false), 0);
      expect(BrassDiodeMachine.outputSignal(powering: false, inverted: true), 15);
      expect(BrassDiodeMachine.outputSignal(powering: true, inverted: true), 0);
    });

    test('an inverted brass diode gives 15 to weak power but 0 to strong power', () {
      // The diode holds its output while the input is gone: POWERED == false, INVERTED == true.
      expect(
        BrassDiodeMachine.signal(
          powering: false,
          inverted: true,
          facing: Direction.north,
          side: Direction.north,
        ),
        15,
        reason: 'BrassDiodeBlock.getSignal keeps the inverted output',
      );
      expect(
        BrassDiodeMachine.directSignal(
          powered: false,
          powering: false,
          inverted: true,
          facing: Direction.north,
          side: Direction.north,
        ),
        0,
        reason: 'DiodeBlock.getDirectSignal needs POWERED',
      );
      // With the input on, the strong signal is the output.
      expect(
        BrassDiodeMachine.directSignal(
          powered: true,
          powering: false,
          inverted: true,
          facing: Direction.north,
          side: Direction.north,
        ),
        15,
      );
      expect(
        BrassDiodeMachine.directSignal(
          powered: true,
          powering: false,
          inverted: true,
          facing: Direction.north,
          side: Direction.south,
        ),
        0,
        reason: 'never towards the back',
      );
    });

    test('the delay change clamps the counter', () {
      final m = BrassDiodeMachine(BrassDiodeKind.timer, state: 15, maxState: 20);
      m.onMaxDelayChanged(5);
      expect(m.state, 5);
      expect(m.progress, 1.0);
    });
  });

  group('latches', () {
    final pos = (0, 64, 0);
    final env = FakeDiodeEnv();

    setUp(() {
      env.signals.clear();
      env.wires.clear();
      env.diodes.clear();
    });

    test('the toggle latch flips its output on every rising edge', () async {
      final logic = LatchLogic(LatchKind.toggle, env);
      var state = const DiodeState(facing: Direction.north);

      // input arrives from the north (the facing side)
      env.signals[(pos, Direction.north)] = 15;
      final req = await logic.checkTickOnNeighbor(pos, state);
      expect(req, const TickRequest(1, 'high'));
      var r = await logic.tick(pos, state);
      state = r.state;
      expect(state.powered, isTrue);
      expect(state.powering, isTrue);
      expect(r.schedule, isNull);

      // input ends: powered drops, the output stays
      env.signals.clear();
      expect(await logic.checkTickOnNeighbor(pos, state), const TickRequest(1, 'veryHigh'));
      r = await logic.tick(pos, state);
      state = r.state;
      expect(state.powered, isFalse);
      expect(state.powering, isTrue);

      // next pulse toggles it off
      env.signals[(pos, Direction.north)] = 15;
      state = (await logic.tick(pos, state)).state;
      expect(state.powered, isTrue);
      expect(state.powering, isFalse);
    });

    test('redstone wire in front counts as input', () async {
      final logic = LatchLogic(LatchKind.toggle, env);
      const state = DiodeState(facing: Direction.east);
      env.wires[pos.relative(Direction.east)] = 7;
      expect(await logic.inputSignal(pos, state), 7);
    });

    test('a strong signal is not lowered by the wire', () async {
      final logic = LatchLogic(LatchKind.toggle, env);
      const state = DiodeState(facing: Direction.east);
      env.signals[(pos, Direction.east)] = 15;
      env.wires[pos.relative(Direction.east)] = 3;
      expect(await logic.inputSignal(pos, state), 15);
    });

    test('a diode behind with another facing gets the highest priority', () async {
      final logic = LatchLogic(LatchKind.toggle, env);
      const state = DiodeState(facing: Direction.north);
      env.diodes[pos.relative(Direction.south)] = Direction.east;
      env.signals[(pos, Direction.north)] = 15;
      expect(await logic.checkTickOnNeighbor(pos, state), const TickRequest(1, 'extremelyHigh'));
    });

    test('a tick with no input still powers an unpowered latch and schedules the re-check (DiodeBlock.tick)', () async {
      final logic = LatchLogic(LatchKind.toggle, env);
      const state = DiodeState(facing: Direction.north);
      final r = await logic.tick(pos, state);
      expect(r.state.powered, isTrue);
      expect(r.schedule, const TickRequest(1, 'veryHigh'));
      // the next tick lets it go
      final r2 = await logic.tick(pos, r.state);
      expect(r2.state.powered, isFalse);
    });

    test('the powered latch sets from the back and resets from the side', () async {
      final logic = LatchLogic(LatchKind.powered, env);
      var state = const DiodeState(facing: Direction.north);

      env.signals[(pos, Direction.north)] = 15;
      state = (await logic.tick(pos, state)).state;
      expect(state.powered, isTrue);
      expect(state.powering, isTrue);

      // reset from the left side (clockwise of north is east, counter clockwise west)
      env.signals[(pos, Direction.west)] = 15;
      state = (await logic.tick(pos, state)).state;
      expect(state.poweredSide, isTrue);
      expect(state.powering, isFalse);

      // back input ends while the side is on: still off
      env.signals.remove((pos, Direction.north));
      state = (await logic.tick(pos, state)).state;
      expect(state.powered, isFalse);
      expect(state.powering, isFalse);

      // the side ends: nothing powers it again
      env.signals.clear();
      state = (await logic.tick(pos, state)).state;
      expect(state.poweredSide, isFalse);
      expect(state.powering, isFalse);
    });

    test('the powered latch re-powers when the side ends while the back is on', () async {
      final logic = LatchLogic(LatchKind.powered, env);
      var state = const DiodeState(facing: Direction.north, powered: true, poweredSide: true);
      env.signals[(pos, Direction.north)] = 15;
      state = (await logic.tick(pos, state)).state;
      expect(state.poweredSide, isFalse);
      expect(state.powering, isTrue);
    });

    test('latch outputs only face forward', () {
      const on = DiodeState(facing: Direction.north, powering: true);
      expect(LatchLogic.signal(on, Direction.north), 15);
      expect(LatchLogic.signal(on, Direction.south), 0);
      expect(LatchLogic.signal(const DiodeState(facing: Direction.north), Direction.north), 0);
    });

    test('a latched toggle answers 15 to weak power but 0 to strong power', () async {
      final logic = LatchLogic(LatchKind.toggle, env);
      var state = const DiodeState(facing: Direction.north);

      // A rising edge latches the output on, then the input ends: the normal latched state,
      // POWERED == false with POWERING == true.
      env.signals[(pos, Direction.north)] = 15;
      state = (await logic.tick(pos, state)).state;
      env.signals.clear();
      state = (await logic.tick(pos, state)).state;
      expect(state.powered, isFalse);
      expect(state.powering, isTrue);

      // `ToggleLatchBlock.getSignal`: the held output still powers the block in front.
      expect(LatchLogic.signal(state, Direction.north), 15);
      // `DiodeBlock.getDirectSignal`, inherited: `POWERED && FACING == side`, so a solid block in
      // front passes nothing on to a lamp or dust behind it.
      expect(LatchLogic.directSignal(state, Direction.north), 0);
      expect(LatchLogic.directSignal(state, Direction.south), 0, reason: 'never towards the back');

      // While the input is on and the output is on, the strong signal follows the output
      // (the edge above toggled the latch off, so the state is spelled out).
      const attached = DiodeState(facing: Direction.north, powered: true, powering: true);
      expect(LatchLogic.signal(attached, Direction.north), 15);
      expect(LatchLogic.directSignal(attached, Direction.north), 15);
    });

    test('the powered latch only toggles by hand when idle', () {
      expect(LatchLogic.canActivate(LatchKind.powered, const DiodeState(facing: Direction.north)), isTrue);
      expect(LatchLogic.canActivate(LatchKind.powered, const DiodeState(facing: Direction.north, powered: true)), isFalse);
      expect(LatchLogic.canActivate(LatchKind.toggle, const DiodeState(facing: Direction.north, powered: true)), isTrue);
    });

    test('wire connection: toggle along the axis, powered latch any horizontal side', () {
      const s = DiodeState(facing: Direction.north);
      expect(LatchLogic.wireConnects(LatchKind.toggle, s, Direction.south), isTrue);
      expect(LatchLogic.wireConnects(LatchKind.toggle, s, Direction.east), isFalse);
      expect(LatchLogic.wireConnects(LatchKind.toggle, s, null), isFalse);
      expect(LatchLogic.wireConnects(LatchKind.powered, s, Direction.east), isTrue);
      expect(LatchLogic.wireConnects(LatchKind.powered, s, Direction.up), isFalse);
    });
  });
}

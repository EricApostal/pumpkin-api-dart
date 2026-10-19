import 'package:create/src/kinetics/fluid_flow.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/sequence.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

/// A tiny world of water cells for the flow maths.
class FakeFluidView implements FluidWorldView {
  final Map<(int, int, int), FluidInfo> fluids = {};
  final Set<(int, int, int)> solids = {};

  @override
  FluidInfo fluidAt(int x, int y, int z) => fluids[(x, y, z)] ?? FluidInfo.empty;

  @override
  bool blocksMotion(int x, int y, int z) => solids.contains((x, y, z));

  @override
  bool isFaceSturdy(int x, int y, int z, Dir face) => solids.contains((x, y, z));

  @override
  String blockAt(int x, int y, int z) => solids.contains((x, y, z)) ? 'minecraft:stone' : 'minecraft:air';

  @override
  bool bubbleColumnDragDown(int x, int y, int z) => false;
}

void main() {
  group('fluid flow', () {
    test('water flows towards lower neighbours', () {
      final w = FakeFluidView();
      w.fluids[(-1, 1, 0)] = const FluidInfo('minecraft:water', 5);
      w.fluids[(0, 1, 0)] = const FluidInfo('minecraft:water', 4);
      w.fluids[(1, 1, 0)] = const FluidInfo('minecraft:water', 3);
      final f = FluidFlow.flowVector(w, 0, 1, 0);
      expect(f.x, closeTo(1, 1e-9));
      expect(f.y, 0);
      expect(f.z, closeTo(0, 1e-9));
    });

    test('still water has no flow', () {
      final w = FakeFluidView();
      w.fluids[(0, 0, 0)] = const FluidInfo('minecraft:water', 8, isSource: true);
      expect(FluidFlow.flowVector(w, 0, 0, 0).lengthSqr, 0);
    });

    test('a water wheel turns one way with water running past its top', () {
      final w = FakeFluidView();
      w.fluids[(-1, 1, 0)] = const FluidInfo('minecraft:water', 5);
      w.fluids[(0, 1, 0)] = const FluidInfo('minecraft:water', 4);
      w.fluids[(1, 1, 0)] = const FluidInfo('minecraft:water', 3);
      final top = waterWheelFlowScore(w, 0, 0, 0, KAxis.z, 1);
      expect(top.score, -1);
      // water running past the bottom turns it the other way
      final w2 = FakeFluidView();
      w2.fluids[(-1, -1, 0)] = const FluidInfo('minecraft:water', 5);
      w2.fluids[(0, -1, 0)] = const FluidInfo('minecraft:water', 4);
      w2.fluids[(1, -1, 0)] = const FluidInfo('minecraft:water', 3);
      expect(waterWheelFlowScore(w2, 0, 0, 0, KAxis.z, 1).score, 1);
    });

    test('offsets: four for the small wheel, twelve for the large one', () {
      for (final a in KAxis.values) {
        expect(WaterWheelOffsets.small[a]!.length, 4);
        expect(WaterWheelOffsets.large[a]!.length, 12);
      }
    });

    test('lava is detected', () {
      final w = FakeFluidView();
      w.fluids[(0, 1, 0)] = const FluidInfo('minecraft:lava', 8, isSource: true);
      expect(waterWheelFlowScore(w, 0, 0, 0, KAxis.z, 1).lava, isTrue);
    });
  });

  group('sequencer', () {
    test('instruction durations', () {
      final turn = Instruction(SequencerInstructions.turnAngle, 90);
      expect(turn.getDuration(0, 16), 21);
      expect(Instruction(SequencerInstructions.delay, 40).getDuration(0, 16), 40);
      expect(Instruction(SequencerInstructions.await_, 1).getDuration(0, 16), -1);
      expect(Instruction(SequencerInstructions.end).getDuration(0, 16), 0);
      expect(turn.getTickProgress(60), 18);
    });

    test('sequence context scales with the speed', () {
      final c = SequenceContext.fromGearshift(SequencerInstructions.turnAngle, 16, 90)!;
      expect(c.getEffectiveValue(32), closeTo(180, 1e-9));
      expect(SequenceContext.fromGearshift(SequencerInstructions.delay, 16, 10), isNull);
    });

    test('speed modifiers', () {
      expect(Instruction(SequencerInstructions.turnAngle, 90, InstructionSpeedModifiers.backFast).modifier, -2);
      expect(Instruction(SequencerInstructions.delay, 10).modifier, 0);
      expect(InstructionSpeedModifiers.byModifier(-1), InstructionSpeedModifiers.back);
    });
  });

  group('speed controller', () {
    test('a large cog above the controller drives it at the target speed', () {
      final level = FakeLevel();
      level.motor(-2, 1, 0, 8, facing: Dir.east);
      level.shaft(-1, 1, 0);
      final cog = level.cog(0, 1, 0, axis: KAxis.x, large: true);
      level.blocks.register('create:rotation_speed_controller', level.blocks.defOf('create:shaft')!);
      final controller = FakeController(level, const KPos(0, 0, 0), const KState('create:rotation_speed_controller', {'axis': 'z'}), 32);
      level.nodes[controller.kpos] = controller;
      level.states[controller.kpos] = controller.state;
      final out = level.shaft(0, 0, 1, axis: KAxis.z);
      level.tickAll(5);
      expect(cog.theoreticalSpeed, 8);
      expect(controller.theoreticalSpeed, 32);
      expect(out.theoreticalSpeed, 32);
      expect(level.destroyed, isEmpty);
    });
  });
}

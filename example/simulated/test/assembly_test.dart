import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/contraptions/core/level.dart' show PushReaction;
import 'package:sable/sable.dart'
    show AssemblyTransform, Rotation, SableLevel, SubLevelAssemblyHelper;
import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

/// A world made of a map of states, with the rules the test sets.
final class FakeWorld implements SimAssemblyWorld {
  FakeWorld(this.states);

  final Map<(int, int, int), BState> states;
  final List<SimGlueBox> glues = [];
  final List<HoneyGlueVolume> honeyGlues = [];
  final Set<(int, int, int)> unmovable = {};
  bool sticky = true;

  @override
  BState stateAt((int, int, int) pos) => states[pos] ?? BState.air;

  @override
  bool isLoaded((int, int, int) pos) => true;

  @override
  bool isOutsideBuildHeight((int, int, int) pos) => false;

  @override
  bool movementAllowed(BState state, (int, int, int) pos) => !unmovable.contains(pos);

  @override
  bool isBrittle(BState state) => false;

  @override
  bool isBlockAttachedTowards(BState state, (int, int, int) pos, Direction direction) => false;

  @override
  bool isNotSupportive(BState state, Direction direction) => false;

  @override
  PushReaction pushReaction(BState state) => PushReaction.normal;

  @override
  bool canStickTo(BState a, BState b) => sticky;

  @override
  List<SimGlueBox> superGluesIn(Aabb area) => [
    for (final glue in glues)
      if (glue.box.intersects(area)) glue,
  ];

  @override
  List<HoneyGlueVolume> honeyGluesIn(Aabb area) => [
    for (final glue in honeyGlues)
      if (glue.box.intersects(area)) glue,
  ];

  @override
  bool isSwivelBearing(BState state) => state.key == 'simulated:swivel_bearing';

  @override
  void superGlueMoved(SimGlueBox glue, (int, int, int) offset) {}

  @override
  void honeyGlueMoved(HoneyGlueVolume glue, (int, int, int) offset) {}

  @override
  void playDisassemblySound((int, int, int) pos) {}

  @override
  List<(int, int, int)> additionalBlocks(BState state, (int, int, int) pos) => const [];

  @override
  void notifyChainConveyor((int, int, int) pos) {}
}

void main() {
  setUp(() {
    SimConfigService.instance.load(SimConfig.defaults);
    // The assembly backend normally lives in Sable's plugin component and is
    // reached over IPC; in a single-address-space test the real model is the
    // backend, so the tests keep exercising it end to end.
    SimAssemblyHelper.assembleBlocks = (world, anchor, blocks, bounds) async {
      final subLevel = SubLevelAssemblyHelper.assembleBlocks(
        FakeLevel(),
        anchor,
        blocks,
        bounds,
      );
      return SimAssembledSubLevel(subLevel.uniqueIdOrNull, subLevel.getPlot().getCenterBlock());
    };
  });
  tearDown(() => SimAssemblyHelper.assembleBlocks = null);

  group('SimAssemblyContraption', () {
    test('follows sticky neighbours', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:stone'),
        (2, 0, 0): const BState('minecraft:stone'),
        (5, 0, 0): const BState('minecraft:stone'),
      });

      final contraption = SimAssemblyContraption(null);
      contraption.searchMovedStructure(world, (0, 0, 0));

      expect(contraption.blocks, {(0, 0, 0), (1, 0, 0), (2, 0, 0)});
    });

    test('does not follow when the blocks do not stick', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:stone'),
      })..sticky = false;

      final contraption = SimAssemblyContraption(null);
      contraption.searchMovedStructure(world, (0, 0, 0));

      expect(contraption.blocks, {(0, 0, 0)});
    });

    test('glue connects blocks that do not stick', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:stone'),
      })
        ..sticky = false
        ..glues.add(const SimGlueBox(1, Aabb(0, 0, 0, 2, 1, 1)));

      final contraption = SimAssemblyContraption(null);
      contraption.searchMovedStructure(world, (0, 0, 0));

      expect(contraption.blocks, {(0, 0, 0), (1, 0, 0)});
      expect(contraption.glues, hasLength(1));
    });

    test('honey glue connects blocks that do not stick', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:stone'),
      })
        ..sticky = false
        ..honeyGlues.add(const HoneyGlueVolume(7, Aabb(0, 0, 0, 2, 1, 1)));

      final contraption = SimAssemblyContraption(null);
      contraption.searchMovedStructure(world, (0, 0, 0));

      expect(contraption.blocks, {(0, 0, 0), (1, 0, 0)});
      expect(contraption.honeyGlues, hasLength(1));
    });

    test('a swivel bearing drags the block it faces', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('simulated:swivel_bearing', {'facing': 'up'}),
        (0, 1, 0): const BState('simulated:swivel_bearing_link_block'),
      })..sticky = false;

      final contraption = SimAssemblyContraption(null);
      contraption.searchMovedStructure(world, (0, 0, 0));

      expect(contraption.blocks, {(0, 0, 0), (0, 1, 0)});
    });

    test('the anchor is never captured', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('simulated:physics_assembler'),
        (0, 1, 0): const BState('minecraft:stone'),
      });

      final contraption = SimAssemblyContraption((0, 0, 0));
      contraption.searchMovedStructure(world, (0, 1, 0));

      expect(contraption.blocks, {(0, 1, 0)});
    });

    test('an unmovable start block fails the assembly', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('minecraft:bedrock'),
      })..unmovable.add((0, 0, 0));

      final contraption = SimAssemblyContraption(null);
      expect(
        () => contraption.searchMovedStructure(world, (0, 0, 0)),
        throwsA(isA<SimAssemblyException>()),
      );
    });

    test('an unmovable neighbour is left behind, as Create does', () {
      final world = FakeWorld({
        (0, 0, 0): const BState('minecraft:stone'),
        (1, 0, 0): const BState('minecraft:bedrock'),
      })..unmovable.add((1, 0, 0));

      final contraption = SimAssemblyContraption(null);
      contraption.searchMovedStructure(world, (0, 0, 0));

      expect(contraption.blocks, {(0, 0, 0)});
    });

    test('too many blocks fails the assembly', () {
      SimConfigService.instance.loadFromMap({
        'server': {
          'assembly': {'maxBlocksMoved': 3},
        },
      });

      final world = FakeWorld({
        for (var x = 0; x < 10; x++) (x, 0, 0): const BState('minecraft:stone'),
      });

      final contraption = SimAssemblyContraption(null);
      expect(
        () => contraption.searchMovedStructure(world, (0, 0, 0)),
        throwsA(isA<SimAssemblyException>()),
      );
    });
  });

  group('SimAssemblyHelper', () {
    test('rotationFrom90DegRots wraps negative and large values', () {
      expect(SimAssemblyHelper.rotationFrom90DegRots(0).quarterTurns, 0);
      expect(SimAssemblyHelper.rotationFrom90DegRots(1).quarterTurns, 3);
      expect(SimAssemblyHelper.rotationFrom90DegRots(2).quarterTurns, 2);
      expect(SimAssemblyHelper.rotationFrom90DegRots(3).quarterTurns, 1);
      expect(SimAssemblyHelper.rotationFrom90DegRots(-1).quarterTurns, 1);
      expect(SimAssemblyHelper.rotationFrom90DegRots(7).quarterTurns, 1);
    });

    test('an air block assembles nothing', () async {
      final world = FakeWorld({});
      final level = FakeLevel();
      expect(
        await SimAssemblyHelper.assembleFromSingleBlock(world, level, (0, 0, 0), (0, 1, 0)),
        isNull,
      );
    });
  });

  group('AssemblyTransform', () {
    test('rotates a block position around the anchor', () {
      final transform = AssemblyTransform(
        (0, 0, 0),
        (0, 0, 0),
        1,
        Rotation.clockwise90,
        FakeLevel(),
      );
      final turned = transform.applyBlock((1, 0, 0));
      expect(turned, (0, 0, -1));
    });

    test('keeps y', () {
      final transform = AssemblyTransform(
        (0, 0, 0),
        (10, 0, 0),
        0,
        Rotation.none,
        FakeLevel(),
      );
      expect(transform.applyBlock((1, 2, 3)), (11, 2, 3));
    });
  });
}

/// A level with no container: the helpers that need one are not reached here.
final class FakeLevel implements SableLevel {
  @override
  String get dimensionId => 'minecraft:overworld';
  @override
  bool get isClientSide => false;
  @override
  int get minY => -64;
  @override
  int get maxY => 320;
  @override
  int get gameTime => 0;
  @override
  int get sectionsCount => 24;
  @override
  String? biomeAt(int x, int y, int z) => null;
}

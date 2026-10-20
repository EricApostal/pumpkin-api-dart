// Pure tests of the fluid transport math: the pressure a pump distributes over a pipe network,
// the flow progress and reversal of a pipe connection, the valve gate, the network reset, the
// tank capacity arithmetic and the hose pulley handler.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/bounds.dart';
import 'package:create/src/common/data.dart' show BlockFace, Couple;
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/fluids/fluid_manipulation.dart';
import 'package:create/src/fluids/fluid_network.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/fluid_storage.dart';
import 'package:create/src/fluids/fluid_world.dart';
import 'package:create/src/fluids/hose_pulley_handler.dart';
import 'package:create/src/fluids/pipe_connection.dart';
import 'package:create/src/fluids/pipe_blocks.dart';
import 'package:create/src/fluids/pipe_node.dart';
import 'package:create/src/fluids/pump_logic.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A [FluidWorld] over maps: enough for the pure fluid logic (no host).
final class _TestWorld extends BlockGetter implements FluidWorld {
  final Map<Pos, BState> blocks = {};
  final Map<Pos, FluidInfo> fluids = {};
  final Map<Pos, PipeNodeView> pipes = {};
  final Map<Pos, PumpPeer> pumps = {};
  final Map<Pos, FluidStorage> handlers = {};
  final Set<String> fluidTags = {};
  FluidsConfig configValue = const DefaultFluidsConfig();

  @override
  int get gameTime => 0;

  @override
  FluidsConfig get config => configValue;

  @override
  FluidInfo fluidAt(Pos p) => fluids[p] ?? FluidInfo.none;

  @override
  bool get waterEvaporates => false;

  @override
  void updateComparators(Pos p) {}

  @override
  bool hasShaftTowards(Pos p, Direction face) => false;

  @override
  PipeNodeView? pipeAt(Pos p) => pipes[p];

  @override
  PumpPeer? pumpAt(Pos p) => pumps[p];

  @override
  bool hasBlockEntity(Pos p) => handlers.containsKey(p) || pumps.containsKey(p);

  @override
  FluidStorage? fluidCapability(Pos p, Direction? side) => handlers[p];

  @override
  bool hasBracket(Pos p) => false;

  @override
  bool isUnbreakable(Pos p) => false;

  @override
  void setBlock(Pos p, BState state, {bool quiet = false}) => blocks[p] = state;

  @override
  void neighboursChanged(Pos p) {}

  @override
  bool fluidHasTag(String fluid, String tag) => fluidTags.contains(tag);

  @override
  void dropResources(Pos p) {}

  @override
  bool canSurvive(Pos p) => true;

  @override
  void scheduleFluidTick(Pos p, String fluid, int delay) {}

  @override
  void placeFluidSource(Pos p, String fluid) => blocks[p] = BState(fluid);

  @override
  FStack pickupFluidSource(Pos p) => FStack.empty;

  @override
  void playSound(Pos p, String sound, {double volume = 1, double pitch = 1}) {}

  @override
  void destroyBlock(Pos p, double effectChance) {}

  @override
  void applyOpenPipeEffect(FStack fluid, Aabb area) {}

  @override
  void splash(Pos p, FStack fluid) {}

  @override
  void award(Pos p, String advancement) {}

  @override
  double nextDouble() => .5;

  @override
  int nextInt(int bound) => 0;

  @override
  BState stateAt(Pos p) => blocks[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) => false;

  /// The blocks listed here are solid cubes (`collisionBoxes`), so the filling search treats them
  /// as obstacles rather than as replaceable space.
  final Set<Pos> solid = {};

  @override
  List<BlockBox> collisionBoxes(Pos p) =>
      solid.contains(p) ? const [BlockBox.unit] : const [];

  @override
  bool supportShapeEmpty(Pos p) => true;

  @override
  bool canBeReplaced(Pos p) => stateAt(p).isAir;

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;
}

/// A plain pipe node: the connections come from the state's per-direction flags.
final class _TestPipe with PipeNodeMixin implements PipeNodeView {
  _TestPipe(this.pos, this.world, this.state);

  final Pos pos;
  final _TestWorld world;
  final BState state;

  int sends = 0;

  @override
  Pos get nodePos => pos;

  @override
  FluidWorld? get nodeWorld => world;

  @override
  BState get nodeState => state;

  @override
  void nodeSendData() => sends++;

  bool removed = false;

  @override
  bool get isRemoved => removed;

  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      state.flag(direction.serializedName);
}

/// The fluid config of the tests: the defaults with an overridable bottomless mode and block
/// threshold.
final class _TestConfig implements FluidsConfig {
  const _TestConfig({
    this.bottomlessFluidMode = BottomlessFluidMode.allowByTag,
    this.hosePulleyBlockThreshold = 10000,
  });

  @override
  final BottomlessFluidMode bottomlessFluidMode;

  @override
  final int hosePulleyBlockThreshold;

  @override
  int get fluidTankCapacity => 8;
  @override
  int get fluidTankMaxHeight => 32;
  @override
  int get mechanicalPumpRange => 16;
  @override
  int get hosePulleyRange => 128;
  @override
  bool get fillInfinite => false;
  @override
  bool get fluidFillPlaceFluidSourceBlocks => true;
  @override
  bool get pipesPlaceFluidSourceBlocks => true;
}

final class _TestPump implements PumpPeer {
  const _TestPump(this.facing);

  final Direction facing;

  @override
  bool isFront(Direction side) => side == facing;

  @override
  bool isPullingOnSide(bool front) => !front;

  @override
  void updatePipesOnSide(Direction side) {}
}

final class _TestHost implements ManipulationHost {
  _TestHost(this.world, this.pos);

  final _TestWorld world;
  final Pos pos;

  @override
  FluidWorld? get fluidWorld => world;

  @override
  Pos get hostPos => pos;

  @override
  void sendData() {}

  @override
  void award(String advancement) {}
}

BState _pipeState(Set<Direction> open) => BState('create:fluid_pipe', {
  for (final d in Direction.values)
    d.serializedName: open.contains(d) ? 'true' : 'false',
  'waterlogged': 'false',
});

BState _pumpState(Direction facing) => BState('create:mechanical_pump', {
  'facing': facing.serializedName,
  'waterlogged': 'false',
});

/// A world with a pump at the origin facing [facing] and a pipe at [pipePos] open to [open].
(_TestWorld, _TestPipe) _pumpSetup({
  required Direction facing,
  required Pos pipePos,
  required Set<Direction> open,
}) {
  final world = _TestWorld();
  world.blocks[(0, 0, 0)] = _pumpState(facing);
  world.pumps[(0, 0, 0)] = _TestPump(facing);
  final state = _pipeState(open);
  world.blocks[pipePos] = state;
  final pipe = _TestPipe(pipePos, world, state);
  world.pipes[pipePos] = pipe;
  return (world, pipe);
}

void main() {
  group('pump pressure', () {
    test('a pushing pump puts its speed on the outward pressure', () {
      final (world, pipe) = _pumpSetup(
        facing: Direction.east,
        pipePos: (1, 0, 0),
        open: {Direction.west, Direction.east},
      );

      // Front side of a pump does not pull (`isPullingOnSide(front) == false`).
      PumpLogic.distributePressureTo(
        world,
        (0, 0, 0),
        64,
        Direction.east,
        pull: false,
      );

      expect(pipe.getConnection(Direction.east)!.outwardPressure, 64);
      expect(pipe.getConnection(Direction.east)!.inboundPressure, 0);
      // The face towards the pump gets the inbound half of the same pressure.
      expect(pipe.getConnection(Direction.west)!.inboundPressure, 64);
      expect(pipe.getConnection(Direction.west)!.outwardPressure, 0);
      expect(pipe.sends, greaterThan(0));
    });

    test('a pump turning backwards pushes just as hard', () {
      final (world, pipe) = _pumpSetup(
        facing: Direction.east,
        pipePos: (1, 0, 0),
        open: {Direction.west, Direction.east},
      );

      PumpLogic.distributePressureTo(
        world,
        (0, 0, 0),
        -64,
        Direction.east,
        pull: false,
      );

      // `Math.abs(getSpeed())`: the pressure is never negative.
      expect(pipe.getConnection(Direction.east)!.outwardPressure, 64);
      expect(pipe.getConnection(Direction.west)!.inboundPressure, 64);
    });

    test('the back side pulls', () {
      final (world, pipe) = _pumpSetup(
        facing: Direction.east,
        pipePos: (1, 0, 0),
        open: {Direction.west, Direction.east},
      );

      PumpLogic.distributePressureTo(
        world,
        (0, 0, 0),
        32,
        Direction.east,
        pull: true,
      );

      expect(pipe.getConnection(Direction.east)!.inboundPressure, 32);
      expect(pipe.getConnection(Direction.west)!.outwardPressure, 32);
    });

    test('a stopped pump distributes nothing', () {
      final (world, pipe) = _pumpSetup(
        facing: Direction.east,
        pipePos: (1, 0, 0),
        open: {Direction.west, Direction.east},
      );

      PumpLogic.distributePressureTo(
        world,
        (0, 0, 0),
        0,
        Direction.east,
        pull: false,
      );

      expect(pipe.hasAnyPressure, isFalse);
      expect(pipe.sends, 0);
    });

    test('parallel branches at one distance share the pressure', () {
      final (world, pipe) = _pumpSetup(
        facing: Direction.east,
        pipePos: (1, 0, 0),
        open: {Direction.west, Direction.east, Direction.up},
      );
      final secondState = _pipeState({Direction.down, Direction.up});
      final second = _TestPipe((1, 1, 0), world, secondState);
      world.blocks[(1, 1, 0)] = secondState;
      world.pipes[(1, 1, 0)] = second;

      PumpLogic.distributePressureTo(
        world,
        (0, 0, 0),
        64,
        Direction.east,
        pull: true,
      );

      // Distance 1 has three valid faces (east, up, west), so 64 / (3 - 1) = 32.
      expect(pipe.getConnection(Direction.east)!.inboundPressure, 32);
      expect(pipe.getConnection(Direction.up)!.inboundPressure, 32);
      expect(pipe.getConnection(Direction.west)!.outwardPressure, 32);
      // Distance 2 has two faces (up and down of the second pipe), so the full 64.
      expect(second.getConnection(Direction.up)!.inboundPressure, 64);
      expect(second.getConnection(Direction.down)!.outwardPressure, 64);
    });
  });

  group('pipe connection', () {
    test('a flow starts slowly without pressure and saturates at 128', () {
      final connection = PipeConnection(Direction.east);
      connection.flow = Flow(true, const FStack(FluidKeys.water, 1000));

      connection.tickFlowProgress(_TestWorld(), (0, 0, 0));
      // `1 / 32 + clamp(0 / 128) * 31 / 32`.
      expect(connection.flow!.progress, closeTo(1 / 32, 1e-9));
      expect(connection.flow!.complete, isFalse);

      connection.pressure = Couple<double>(64, 0);
      connection.tickFlowProgress(_TestWorld(), (0, 0, 0));
      expect(
        connection.flow!.progress,
        closeTo(1 / 32 + (1 / 32 + .5 * 31 / 32), 1e-9),
      );

      connection.pressure = Couple<double>(128, 0);
      connection.tickFlowProgress(_TestWorld(), (0, 0, 0));
      // 1/32 + 0.515625 < 1; one more tick completes it.
      connection.tickFlowProgress(_TestWorld(), (0, 0, 0));
      expect(connection.flow!.progress, 1);
      expect(connection.flow!.complete, isTrue);
    });

    test('a complete inbound flow provides its fluid', () {
      final connection = PipeConnection(Direction.east);
      expect(connection.providedFluid.isEmpty, isTrue);
      connection.flow = Flow(true, const FStack(FluidKeys.water, 500));
      expect(connection.providedFluid.isEmpty, isTrue);
      connection.flow!.complete = true;
      expect(connection.providedFluid.amount, 500);
      // An outward flow provides nothing to the pipe.
      connection.flow!.inbound = false;
      expect(connection.providedFluid.isEmpty, isTrue);
    });

    test('a reversed pressure flips a flow and drops an unfinished one', () {
      final connection = PipeConnection(Direction.east);
      connection.flow = Flow(true, const FStack(FluidKeys.water, 1000));
      connection.pressure = Couple<double>(0, 40);

      expect(connection.comparePressure(), 40);
      expect(connection.flipFlowsIfPressureReversed(), isTrue);
      expect(connection.flow, isNull, reason: 'the flow was not complete');

      final complete = PipeConnection(Direction.east);
      complete.flow = Flow(true, const FStack(FluidKeys.water, 1000));
      complete.flow!.complete = true;
      complete.pressure = Couple<double>(0, 40);
      expect(complete.flipFlowsIfPressureReversed(), isTrue);
      expect(complete.flow!.inbound, isFalse);
    });

    test('a balanced pressure never flips a flow', () {
      final connection = PipeConnection(Direction.east);
      connection.flow = Flow(true, const FStack(FluidKeys.water, 1000));
      connection.flow!.complete = true;
      connection.pressure = Couple<double>(20, 20);
      expect(connection.flipFlowsIfPressureReversed(), isFalse);
      expect(connection.flow!.inbound, isTrue);
    });

    test('adding pressure accumulates per direction', () {
      final connection = PipeConnection(Direction.east);
      connection.addPressure(true, 10);
      connection.addPressure(true, 5);
      connection.addPressure(false, 3);
      expect(connection.inboundPressure, 15);
      expect(connection.outwardPressure, 3);
      expect(connection.comparePressure(), -12);
      expect(connection.hasPressure, isTrue);

      connection.wipePressure();
      expect(connection.hasPressure, isFalse);
      expect(connection.hasFlow, isFalse);
    });
  });

  group('valve', () {
    test('a closed valve gates the flow and an open one lets it through', () {
      final closed = const BState('create:fluid_valve', {'enabled': 'false'});
      final open = const BState('create:fluid_valve', {'enabled': 'true'});

      expect(PipeBlocks.valveAllowsPull(closed), isFalse);
      expect(PipeBlocks.valveAllowsPull(open), isTrue);
    });

    test('the valve only has connections along its pipe axis', () {
      final state = const BState('create:fluid_valve', {
        'facing': 'north',
        'axis_along_first': 'true',
      });
      final axis = PipeBlocks.valvePipeAxis(state);
      for (final d in Direction.values) {
        expect(
          PipeBlocks.isOpenAt(state, d),
          d.axis == axis,
          reason: 'the $d side of a valve on the $axis axis',
        );
      }
    });
  });

  group('fluid network', () {
    test('a fresh network queues its start and waits two ticks', () {
      final world = _TestWorld();
      final network = FluidNetwork(
        world,
        BlockFace((0, 0, 0), Direction.east),
        (_) => null,
      );

      expect(network.pauseBeforePropagation, 2);
      expect(network.queued, [BlockFace((0, 0, 0), Direction.east)]);
      expect(network.targets, isEmpty);
      expect(network.fluid.isEmpty, isTrue);

      // The pause is counted down before anything is propagated.
      network.tick();
      expect(network.pauseBeforePropagation, 1);
      expect(network.targets, isEmpty);
    });
  });

  group('tank math', () {
    test('a tank fills to its capacity and no further', () {
      final tank = FluidTank(1500);
      expect(tank.fill(const FStack(FluidKeys.water, 1000), simulate: true), 1000);
      expect(tank.isEmpty, isTrue, reason: 'a simulation does not change the tank');

      expect(tank.fill(const FStack(FluidKeys.water, 1000), simulate: false), 1000);
      expect(tank.fluidAmount, 1000);
      expect(tank.space, 500);

      expect(tank.fill(const FStack(FluidKeys.water, 800), simulate: false), 500);
      expect(tank.fluidAmount, 1500);
      expect(tank.space, 0);
      expect(tank.fill(const FStack(FluidKeys.water, 1), simulate: false), 0);
    });

    test('a tank refuses a second fluid', () {
      final tank = FluidTank(1500)
        ..fill(const FStack(FluidKeys.water, 1000), simulate: false);

      expect(tank.fill(const FStack(FluidKeys.lava, 100), simulate: false), 0);
      expect(tank.fluidInTank(0).fluid, FluidKeys.water);
      expect(
        tank.drainFluid(const FStack(FluidKeys.lava, 100), simulate: false).isEmpty,
        isTrue,
      );
    });

    test('draining is capped by the contents and keeps the rest', () {
      final tank = FluidTank(1500)
        ..fill(const FStack(FluidKeys.water, 1200), simulate: false);

      expect(tank.drain(1000, simulate: true).amount, 1000);
      expect(tank.fluidAmount, 1200);
      expect(tank.drain(1000, simulate: false).amount, 1000);
      expect(tank.fluidAmount, 200);
      expect(tank.drain(1000, simulate: false).amount, 200);
      expect(tank.isEmpty, isTrue);
      expect(tank.drain(1000, simulate: false).isEmpty, isTrue);
    });

    test('a combined wrapper fills across its handlers', () {
      final first = FluidTank(1000);
      final second = FluidTank(1000);
      final combined = CombinedTankWrapper([first, second]);

      expect(combined.tanks, 2);
      expect(combined.fill(const FStack(FluidKeys.water, 1500), simulate: false), 1500);
      expect(first.fluidAmount, 1000);
      expect(second.fluidAmount, 500);

      final drained = combined.drain(1200, simulate: false);
      expect(drained.amount, 1200);
      expect(drained.fluid, FluidKeys.water);
      expect(first.fluidAmount + second.fluidAmount, 300);
    });

    test('the creative tank never runs out and voids what it is given', () {
      final tank = CreativeSmartFluidTank(8000, (_) {});
      tank.setContainedFluid(const FStack(FluidKeys.water, 1));

      expect(tank.fluidAmount, 8000);
      expect(tank.fill(const FStack(FluidKeys.lava, 500), simulate: false), 500);
      expect(tank.fluidInTank(0).fluid, FluidKeys.water);
      expect(tank.drain(1000, simulate: false).amount, 1000);
      expect(tank.fluidAmount, 8000);
      expect(
        tank.drainFluid(const FStack(FluidKeys.lava, 100), simulate: false).isEmpty,
        isTrue,
      );
    });

    test('the smart tank reports every change', () {
      final seen = <int>[];
      final tank = SmartFluidTank(1000, (fluid) => seen.add(fluid.amount));
      tank.fill(const FStack(FluidKeys.water, 400), simulate: false);
      tank.drain(100, simulate: false);
      expect(seen, [400, 300]);
    });
  });

  group('hose pulley world search', () {
    _TestWorld worldWith(FluidsConfig config) => _TestWorld()..configValue = config;

    test('the bottomless mode decides what drains forever', () {
      bool drainable(BottomlessFluidMode mode, {bool tagged = false}) {
        final world = worldWith(_TestConfig(bottomlessFluidMode: mode));
        if (tagged) world.fluidTags.add('create:bottomless/allow');
        return FluidDraining(_TestHost(world, (0, 5, 0)))
            .canDrainInfinitely(FluidKeys.water);
      }

      expect(drainable(BottomlessFluidMode.allowAll), isTrue);
      expect(drainable(BottomlessFluidMode.denyAll), isFalse);
      // `ALLOW_BY_TAG` needs the allow tag, `DENY_BY_TAG` only the absence of the deny tag.
      expect(drainable(BottomlessFluidMode.allowByTag), isFalse);
      expect(drainable(BottomlessFluidMode.allowByTag, tagged: true), isTrue);
      expect(drainable(BottomlessFluidMode.denyByTag), isTrue);
      expect(
        FluidDraining(_TestHost(worldWith(const _TestConfig()), (0, 5, 0)))
            .canDrainInfinitely(null),
        isFalse,
      );
    });

    test('a disabled threshold never drains forever', () {
      final world = worldWith(
        const _TestConfig(
          bottomlessFluidMode: BottomlessFluidMode.allowAll,
          hosePulleyBlockThreshold: -1,
        ),
      );
      expect(
        FluidDraining(_TestHost(world, (0, 5, 0)))
            .canDrainInfinitely(FluidKeys.water),
        isFalse,
      );
    });

    test('the filling search tells free space, fluid and obstacles apart', () {
      final world = _TestWorld();
      final filling = FluidFilling(_TestHost(world, (0, 5, 0)));

      // Air is fillable.
      expect(
        filling.getAtPos(world, (0, 0, 0), FluidKeys.water),
        SpaceType.fillable,
      );
      // A water source of the same fluid is already filled.
      world.fluids[(1, 0, 0)] = const FluidInfo(
        FluidKeys.water,
        8,
        isSource: true,
      );
      expect(
        filling.getAtPos(world, (1, 0, 0), FluidKeys.water),
        SpaceType.filled,
      );
      // Lava in the way blocks water.
      world.fluids[(2, 0, 0)] = const FluidInfo(FluidKeys.lava, 8, isSource: true);
      expect(
        filling.getAtPos(world, (2, 0, 0), FluidKeys.water),
        SpaceType.blocking,
      );
      // A stone block is not replaced.
      world.blocks[(3, 0, 0)] = const BState('minecraft:stone');
      world.solid.add((3, 0, 0));
      expect(
        filling.getAtPos(world, (3, 0, 0), FluidKeys.water),
        SpaceType.blocking,
      );
      // An empty waterlogged block can take the water.
      world.blocks[(4, 0, 0)] = const BState('minecraft:oak_stairs', {
        'waterlogged': 'false',
      });
      expect(
        filling.getAtPos(world, (4, 0, 0), FluidKeys.water),
        SpaceType.fillable,
      );
      world.blocks[(5, 0, 0)] = const BState('minecraft:oak_stairs', {
        'waterlogged': 'true',
      });
      expect(
        filling.getAtPos(world, (5, 0, 0), FluidKeys.water),
        SpaceType.filled,
      );
    });

    test('the draining search classifies sources and flowing fluid', () {
      final world = _TestWorld();
      final draining = FluidDraining(_TestHost(world, (0, 5, 0)));

      world.blocks[(0, 0, 0)] = const BState('minecraft:water', {'level': '0'});
      expect(
        draining.fluidBlockTypeAt(world, (0, 0, 0)),
        FluidBlockType.source,
      );
      world.blocks[(1, 0, 0)] = const BState('minecraft:water', {'level': '3'});
      expect(
        draining.fluidBlockTypeAt(world, (1, 0, 0)),
        FluidBlockType.flowing,
      );
      world.blocks[(2, 0, 0)] = const BState('minecraft:oak_stairs', {
        'waterlogged': 'true',
      });
      expect(
        draining.fluidBlockTypeAt(world, (2, 0, 0)),
        FluidBlockType.source,
      );
      expect(
        draining.fluidBlockTypeAt(world, (3, 0, 0)),
        FluidBlockType.none,
      );
    });
  });

  group('pipe node lookup', () {
    // `FluidPropagator.getPipe` (`BlockEntityBehaviour.get(reader, pos,
    // FluidTransportBehaviour.TYPE)`): the host resolves a pipe from the behaviours of
    // the block entity at the position.
    test('the node of a pipe is its transport behaviour, not the block entity', () {
      final world = _TestWorld();
      final pipe = _TestPipe(
        (0, 0, 0),
        world,
        _pipeState({Direction.west, Direction.east}),
      );
      // A pipe block entity also owns a bracket behaviour; the node is found after it.
      expect(pipeNodeIn([Object(), pipe]), same(pipe));
    });

    test('a block entity that only owns the behaviour is not a node', () {
      // The regression: `pipeAt` used to test `blockEntity is PipeNodeView`. A pipe
      // block entity is not one (it only owns the behaviour), so every pipe resolved
      // to null and no network was ever formed.
      final owner = Object();
      expect(owner, isNot(isA<PipeNodeView>()));
      expect(pipeNodeIn([owner]), isNull);
      expect(pipeNodeIn(const []), isNull);
    });

    test('a removed pipe resolves to no node', () {
      final world = _TestWorld();
      final pipe = _TestPipe((0, 0, 0), world, _pipeState(const {}))
        ..removed = true;
      expect(pipeNodeIn([pipe]), isNull);
    });
  });

  group('hose pulley handler', () {
    late _TestWorld world;
    late SmartFluidTank tank;
    late HosePulleyFluidHandler handler;

    setUp(() {
      world = _TestWorld();
      tank = SmartFluidTank(1500, (_) {});
      final host = _TestHost(world, (0, 5, 0));
      handler = HosePulleyFluidHandler(
        tank,
        FluidFilling(host),
        FluidDraining(host),
        () => (0, 0, 0),
        () => false,
      );
    });

    test('it fills its internal tank up to 1500 mB', () {
      expect(handler.fill(const FStack(FluidKeys.water, 500), simulate: true), 500);
      expect(tank.isEmpty, isTrue);
      expect(handler.fill(const FStack(FluidKeys.water, 500), simulate: false), 500);
      expect(tank.fluidAmount, 500);
      expect(handler.fill(const FStack(FluidKeys.water, 2000), simulate: false), 1000);
      expect(tank.fluidAmount, 1500);
    });

    test('it refuses a fluid without a block state', () {
      // `FluidHelper.hasBlockState`: a potion cannot be placed into the world.
      expect(handler.fill(const FStack(FluidKeys.potion, 1000), simulate: false), 0);
      expect(tank.isEmpty, isTrue);
    });

    test('it refuses a different fluid than the one it holds', () {
      handler.fill(const FStack(FluidKeys.water, 500), simulate: false);
      expect(handler.fill(const FStack(FluidKeys.lava, 500), simulate: false), 0);
      expect(tank.fluidInTank(0).fluid, FluidKeys.water);
    });

    test('it drains from its internal tank', () {
      handler.fill(const FStack(FluidKeys.water, 1200), simulate: false);
      final drained = handler.drain(1000, simulate: false);
      expect(drained.amount, 1000);
      expect(drained.fluid, FluidKeys.water);
      expect(tank.fluidAmount, 200);
      expect(handler.drain(1000, simulate: false).amount, 200);
      expect(tank.isEmpty, isTrue);
    });

    test('it reports the drainable fluid when its tank is empty', () {
      expect(handler.fluidInTank(0).isEmpty, isTrue);
    });
  });
}

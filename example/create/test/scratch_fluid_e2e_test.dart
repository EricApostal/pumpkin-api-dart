// SCRATCH: pure end-to-end reproduction of the live rig
// water(0) -> pipe(1) -> pump(2, facing=east) -> pipe(3) -> tank(4)
import 'package:create/src/api/block_state.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:create/src/common/bounds.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/data.dart' show Couple;
import 'package:create/src/common/pos.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/fluid_storage.dart';
import 'package:create/src/fluids/fluid_world.dart';
import 'package:create/src/fluids/pipe_connection.dart';
import 'package:create/src/fluids/pipe_node.dart';
import 'package:create/src/fluids/pump_logic.dart';
import 'package:test/test.dart';

final class W extends BlockGetter implements FluidWorld {
  final Map<Pos, BState> blocks = {};
  final Map<Pos, FluidInfo> fluids = {};
  final Map<Pos, PipeNodeView> pipes = {};
  final Map<Pos, PumpPeer> pumps = {};
  final Map<Pos, FluidStorage> handlers = {};
  int tick = 0;

  @override
  int get gameTime => tick;
  @override
  FluidsConfig get config => const DefaultFluidsConfig();
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
  bool fluidHasTag(String fluid, String tag) => false;
  @override
  void dropResources(Pos p) {}
  @override
  bool canSurvive(Pos p) => true;
  @override
  void scheduleFluidTick(Pos p, String fluid, int delay) {}
  @override
  void placeFluidSource(Pos p, String fluid) {}
  @override
  FStack pickupFluidSource(Pos p) {
    final f = fluids.remove(p);
    if (f == null) return FStack.empty;
    blocks[p] = BState.air;
    return FStack(f.fluid, 1000);
  }

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
  @override
  List<BlockBox> collisionBoxes(Pos p) => const [];
  @override
  bool supportShapeEmpty(Pos p) => true;
  @override
  bool canBeReplaced(Pos p) {
    final s = stateAt(p);
    return s.isAir || s.key == 'minecraft:water';
  }

  @override
  bool hasTag(Pos p, String tag) => false;
  @override
  bool isWater(Pos p) => fluids[p]?.fluid == 'minecraft:water';
}

final class P with PipeNodeMixin implements PipeNodeView {
  P(this.pos, this.world, this.state);
  final Pos pos;
  final W world;
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
  @override
  bool get isRemoved => false;
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      state.flag(direction.serializedName);
}

final class Pmp implements PumpPeer {
  const Pmp(this.facing);
  final Direction facing;
  @override
  bool isFront(Direction side) => side == facing;
  @override
  bool isPullingOnSide(bool front) => !front;
  @override
  void updatePipesOnSide(Direction side) {}
}

/// `PumpBlockEntity.PumpFluidTransferBehaviour`.
final class PumpNode with PipeNodeMixin implements PipeNodeView {
  PumpNode(this.pos, this.world, this.state, this.facing);
  final Pos pos;
  final W world;
  final BState state;
  final Direction facing;
  double speed = 16;
  @override
  Pos get nodePos => pos;
  @override
  FluidWorld? get nodeWorld => world;
  @override
  BState get nodeState => state;
  @override
  void nodeSendData() {}
  @override
  bool get isRemoved => false;
  @override
  bool get isPumpNode => true;
  @override
  bool canHaveFlowToward(BState state, Direction direction) =>
      direction.axis == facing.axis;
  void tick() {
    pipeTick();
    final map = interfaces;
    if (map == null) return;
    for (final entry in map.entries) {
      final pull = !(entry.key == facing);
      entry.value.pressure =
          pull ? Couple<double>(speed.abs(), 0) : Couple<double>(0, speed.abs());
    }
  }
}

BState pipeState(Set<Direction> open) => BState('create:fluid_pipe', {
  for (final d in Direction.values)
    d.serializedName: open.contains(d) ? 'true' : 'false',
  'waterlogged': 'false',
});

void main() {
  test('rig: water -> pipe -> pump(east) -> pipe -> tank', () {
    final w = W();
    const waterPos = (0, 0, 0);
    const p1Pos = (1, 0, 0);
    const pumpPos = (2, 0, 0);
    const p3Pos = (3, 0, 0);
    const tankPos = (4, 0, 0);

    w.blocks[waterPos] = const BState('minecraft:water');
    w.fluids[waterPos] =
        const FluidInfo('minecraft:water', 8, isSource: true);

    final s1 = pipeState({Direction.west, Direction.east});
    final s3 = pipeState({Direction.west, Direction.east});
    w.blocks[p1Pos] = s1;
    w.blocks[p3Pos] = s3;
    final pipe1 = P(p1Pos, w, s1);
    final pipe3 = P(p3Pos, w, s3);
    w.pipes[p1Pos] = pipe1;
    w.pipes[p3Pos] = pipe3;
    w.pumps[pumpPos] = const Pmp(Direction.east);
    w.blocks[pumpPos] = const BState('create:mechanical_pump', {
      'facing': 'east',
      'waterlogged': 'false',
    });

    final pumpState = w.blocks[pumpPos]!;
    final pumpNode = PumpNode(pumpPos, w, pumpState, Direction.east);
    w.pipes[pumpPos] = pumpNode;

    final tank = FluidTank(8000);
    w.handlers[tankPos] = tank;

    // The pump distributes its pressure on both sides.
    PumpLogic.distributePressureTo(
      w,
      pumpPos,
      16,
      Direction.west,
      pull: true,
    );
    PumpLogic.distributePressureTo(
      w,
      pumpPos,
      16,
      Direction.east,
      pull: false,
    );

    for (var i = 0; i < 120; i++) {
      w.tick = i;
      pipe1.pipeTick();
      pumpNode.tick();
      pipe3.pipeTick();
      if (i % 10 == 0) {
        // ignore: avoid_print
        print(
          't$i tank=${tank.fluid.amount} '
          'p1.w=${pipe1.getConnection(Direction.west)!.flow?.progress.toStringAsFixed(3)} '
          'p1.e=${pipe1.getConnection(Direction.east)!.flow?.progress.toStringAsFixed(3)} '
          'pump.w=${pumpNode.getConnection(Direction.west)?.flow?.progress.toStringAsFixed(3)} '
          'pump.e=${pumpNode.getConnection(Direction.east)?.flow?.progress.toStringAsFixed(3)} '
          'p3.w=${pipe3.getConnection(Direction.west)?.flow?.progress.toStringAsFixed(3)} '
          'p3.e=${pipe3.getConnection(Direction.east)?.flow?.progress.toStringAsFixed(3)}',
        );
      }
    }
    expect(tank.fluid.amount, greaterThan(0));
  });
}

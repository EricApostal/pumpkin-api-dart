// The flow physics of the placeable fluids (`create:honey`, `create:chocolate`): the parameters
// come from the manifest (`AllFluids.java:61-105`: `levelDecreasePerBlock(2) tickRate(25)
// slopeFindDistance(3)`) and the level drops by `levelDecreasePerBlock` per block of flow. The
// checks on the spread distance fail on the pre-fix code, which used the vanilla defaults
// (`levelDecreasePerBlock: 1`, `tickRate: 5`) and never ran the logic at all.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/bounds.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/fluid_storage.dart';
import 'package:create/src/fluids/fluid_world.dart';
import 'package:create/src/fluids/flowing_fluid.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A [FluidWorld] over maps for the flow logic. A scheduled flow step is a queued tick, like the
/// block tick the host delivers to the fluid block (`HostFluidWorld.scheduleFlowTick`).
final class _FlowWorld extends BlockGetter implements FluidWorld {
  final Map<Pos, BState> blocks = {};
  final Map<Pos, FluidInfo> fluids = {};
  final List<(Pos, String, int)> flowTicks = [];
  final List<(Pos, BState)> writes = [];
  final List<Pos> dropped = [];

  /// Called for a write of a liquid block, like the host's `placed` hook
  /// (`LiquidBlock.onPlace`) scheduling the fluid.
  void Function(Pos pos, BState state)? onLiquidWrite;

  /// Called by [scheduleFlowTick] with the position of the queued step.
  void Function(Pos pos)? onFlowTick;

  @override
  int get gameTime => 0;

  @override
  FluidsConfig get config => const DefaultFluidsConfig();

  @override
  FluidInfo fluidAt(Pos p) => fluids[p] ?? FluidInfo.none;

  @override
  bool get waterEvaporates => false;

  /// The host has no fluid ticks for a plugin fluid, so the flow logic must not ask for one.
  @override
  void scheduleFluidTick(Pos p, String fluid, int delay) =>
      throw StateError('a plugin fluid has no fluid ticks in the host');

  @override
  void scheduleFlowTick(Pos p, String fluid, int delay) {
    flowTicks.add((p, fluid, delay));
    onFlowTick?.call(p);
  }

  @override
  void setBlock(Pos p, BState state, {bool quiet = false}) {
    writes.add((p, state));
    blocks[p] = state;
    onLiquidWrite?.call(p, state);
  }

  @override
  void neighboursChanged(Pos p) {}

  @override
  void updateComparators(Pos p) {}

  @override
  bool hasShaftTowards(Pos p, Direction face) => false;

  @override
  bool fluidHasTag(String fluid, String tag) => false;

  @override
  void dropResources(Pos p) => dropped.add(p);

  @override
  bool canSurvive(Pos p) => true;

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
  PipeNodeView? pipeAt(Pos p) => null;

  @override
  PumpPeer? pumpAt(Pos p) => null;

  @override
  bool hasBlockEntity(Pos p) => false;

  @override
  FluidStorage? fluidCapability(Pos p, Direction? side) => null;

  @override
  bool hasBracket(Pos p) => false;

  @override
  bool isUnbreakable(Pos p) => false;

  @override
  BState stateAt(Pos p) => blocks[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  /// Only the stone of the floor closes a face; a fluid block has no collision shape.
  @override
  bool isFaceSturdy(Pos p, Direction face) => stateAt(p).key == 'minecraft:stone';

  @override
  List<BlockBox> collisionBoxes(Pos p) => stateAt(p).isAir ? const [] : const [BlockBox.unit];

  @override
  bool supportShapeEmpty(Pos p) => true;

  @override
  bool canBeReplaced(Pos p) => stateAt(p).isAir;

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;
}

/// Lays a stone floor at `y == -1` (so the fluid cannot fall out of the row), places a source at
/// the origin and runs the flow steps until none is left. Returns the world.
///
/// Every liquid block the logic writes is scheduled for its own step, and so is every step the
/// logic re-schedules itself (`FlowingFluid.tick`): that is what the host does for a plugin
/// block, whose `placed` hook runs `liquidBlockBehavior`'s `LiquidBlock.onPlace` schedule.
_FlowWorld _spread(FlowingFluidDef def, {int maxSteps = 512}) {
  final world = _FlowWorld();
  for (var x = -12; x <= 12; x++) {
    for (var z = -12; z <= 12; z++) {
      world.blocks[(x, -1, z)] = const BState('minecraft:stone');
    }
  }
  final pending = <Pos>{};
  void schedule(Pos pos) {
    if (!pending.add(pos)) return;
    world.scheduleFlowTick(pos, def.still, def.tickRate);
  }

  world
    ..onFlowTick = schedule
    ..onLiquidWrite = (pos, state) {
      if (state.key == def.blockKey) schedule(pos);
    };
  world.blocks[(0, 0, 0)] = BState(def.blockKey, const {'level': '0'});
  schedule((0, 0, 0));

  final logic = FlowingFluidLogic(def, world);
  var steps = 0;
  while (pending.isNotEmpty && steps++ < maxSteps) {
    final pos = pending.first;
    pending.remove(pos);
    logic.tick(pos);
  }
  expect(steps, lessThan(maxSteps), reason: 'the flow must settle');
  return world;
}

void main() {
  group('manifest flow parameters', () {
    test('honey and chocolate spread at 2 levels per block, 25 ticks apart, slope 3', () {
      final honey = placeableFluidDefs['create:honey']!;
      expect(honey.still, FluidKeys.honey);
      expect(honey.flowing, FluidKeys.flowingHoney);
      expect(honey.blockKey, 'create:honey');
      expect(honey.tickRate, 25);
      expect(honey.levelDecreasePerBlock, 2);
      expect(honey.slopeFindDistance, 3);
      final chocolate = placeableFluidDefs['create:chocolate']!;
      expect(chocolate.blockKey, 'create:chocolate');
      expect(chocolate.tickRate, 25);
      expect(chocolate.levelDecreasePerBlock, 2);
      expect(chocolate.slopeFindDistance, 3);
    });

    test('a fluid without explicit flow properties keeps the vanilla defaults', () {
      final def = FlowingFluidDef.fromAttributes(
        still: 'test:fluid',
        flowing: 'test:flowing_fluid',
        blockKey: 'test:fluid',
        attributes: const {'density': '1000'},
      );
      expect(def.tickRate, 5);
      expect(def.levelDecreasePerBlock, 1);
      expect(def.slopeFindDistance, 4);
    });
  });

  group('honey spreads over the level property', () {
    test('the source stays a source and the level drops 2 per block, 3 blocks far', () {
      final world = _spread(placeableFluidDefs['create:honey']!);
      // `legacyLevel`: 0 is the source, then `8 - level` for the flowing blocks.
      expect(world.stateAt((0, 0, 0)), const BState('create:honey', {'level': '0'}));
      // amount 8 - 2 = 6 one block away, 4 two blocks away, 2 three blocks away; 8 - 8 = 0 is
      // nothing, so the flow stops there.
      expect(world.stateAt((1, 0, 0)), const BState('create:honey', {'level': '2'}));
      expect(world.stateAt((2, 0, 0)), const BState('create:honey', {'level': '4'}));
      expect(world.stateAt((3, 0, 0)), const BState('create:honey', {'level': '6'}));
      expect(world.stateAt((4, 0, 0)).isAir, isTrue, reason: 'level 0 is not written');
      expect(world.stateAt((0, 0, 1)), const BState('create:honey', {'level': '2'}));
      expect(world.stateAt((0, 0, -1)), const BState('create:honey', {'level': '2'}));
      expect(world.stateAt((-1, 0, 0)), const BState('create:honey', {'level': '2'}));
      // A diamond of `|x| + |z| <= 3`, and the level property is `2 * distance`: level 2 one
      // block from the source, 4 two blocks, 6 three. Anything past distance 3 (amount 0) is
      // air, and every block of the diamond is honey.
      var honeyBlocks = 0;
      for (var x = -5; x <= 5; x++) {
        for (var z = -5; z <= 5; z++) {
          final distance = x.abs() + z.abs();
          final state = world.stateAt((x, 0, z));
          if (distance == 0) continue;
          if (distance <= 3) {
            expect(
              state,
              BState('create:honey', {'level': '${2 * distance}'}),
              reason: 'distance $distance',
            );
            honeyBlocks++;
          } else {
            expect(state.isAir, isTrue, reason: 'distance $distance');
          }
        }
      }
      expect(honeyBlocks, 24);
    });

    test('every step is scheduled tickRate ticks later', () {
      final world = _FlowWorld();
      final honey = placeableFluidDefs['create:honey']!;
      world.blocks[(0, -1, 0)] = const BState('minecraft:stone');
      world.blocks[(0, 0, 0)] = BState(honey.blockKey, const {'level': '0'});
      FlowingFluidLogic(honey, world).tick((0, 0, 0));
      expect(world.flowTicks, isEmpty, reason: 'a source that only spreads re-schedules nothing');
      world.flowTicks.clear();
      // A flowing block whose state changes re-schedules itself (`FlowingFluid.tick`).
      world.blocks[(0, 0, 0)] = BState(honey.blockKey, const {'level': '8'});
      world.blocks[(0, 0, 1)] = BState(honey.blockKey, const {'level': '0'});
      FlowingFluidLogic(honey, world).tick((0, 0, 0));
      expect(world.flowTicks, [((0, 0, 0), FluidKeys.honey, 25)]);
    });

    test('a water-like level decrease would reach twice as far (the value is really read)', () {
      final waterLike = FlowingFluidDef(
        still: FluidKeys.honey,
        flowing: FluidKeys.flowingHoney,
        blockKey: 'create:honey',
        tickRate: 5,
        levelDecreasePerBlock: 1,
        slopeFindDistance: 4,
      );
      final world = _spread(waterLike);
      expect(world.stateAt((7, 0, 0)), const BState('create:honey', {'level': '7'}));
      expect(world.stateAt((8, 0, 0)).isAir, isTrue);
    });

    test('chocolate behaves like honey', () {
      final world = _spread(placeableFluidDefs['create:chocolate']!);
      expect(world.stateAt((0, 0, 0)), const BState('create:chocolate', {'level': '0'}));
      expect(world.stateAt((3, 0, 0)), const BState('create:chocolate', {'level': '6'}));
      expect(world.stateAt((4, 0, 0)).isAir, isTrue);
    });
  });
}
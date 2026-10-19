import 'package:create/src/api/behaviour/spouting/spouting.dart';
import 'package:create/src/api/block_state.dart';
import 'package:create/src/api/boiler/blaze_burner.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/fluid_storage.dart';
import 'package:create/src/fluids/fluid_world.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A [FluidWorld] over a state map; only the block reads and writes the spout behaviours use
/// do anything.
final class _FakeFluidWorld extends FluidWorld {
  final Map<Pos, BState> states;

  _FakeFluidWorld(this.states);

  @override
  BState stateAt(Pos p) => states[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) => false;

  @override
  List<BlockBox> collisionBoxes(Pos p) => const [];

  @override
  bool supportShapeEmpty(Pos p) => true;

  @override
  bool canBeReplaced(Pos p) => stateAt(p).isAir;

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;

  @override
  int get gameTime => 0;

  @override
  FluidsConfig get config => const DefaultFluidsConfig();

  @override
  FluidInfo fluidAt(Pos p) => FluidInfo.none;

  @override
  bool get waterEvaporates => false;

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
  void setBlock(Pos p, BState state, {bool quiet = false}) => states[p] = state;

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
  double nextDouble() => 0;

  @override
  int nextInt(int bound) => 0;
}

void main() {
  const pos = (0, 0, 0);

  group('CauldronSpoutingBehavior', () {
    test('fills an empty cauldron with water and lava', () {
      final world = _FakeFluidWorld({pos: const BState('minecraft:cauldron')});
      final behavior = CauldronSpoutingBehavior.instance;

      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:water', 249),
          simulate: false,
        ),
        0,
        reason: 'not enough fluid',
      );
      expect(world.stateAt(pos).key, 'minecraft:cauldron');

      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:water', 250),
          simulate: true,
        ),
        250,
      );
      expect(
        world.stateAt(pos).key,
        'minecraft:cauldron',
        reason: 'simulate does not write',
      );

      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:water', 250),
          simulate: false,
        ),
        250,
      );
      // `Blocks.WATER_CAULDRON.defaultBlockState()` is one level.
      expect(
        world.stateAt(pos),
        const BState('minecraft:water_cauldron', {'level': '1'}),
      );

      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:lava', 1000),
          simulate: false,
        ),
        1000,
      );
      expect(world.stateAt(pos).key, 'minecraft:lava_cauldron');
    });

    test('an unregistered fluid does nothing', () {
      final world = _FakeFluidWorld({pos: const BState('minecraft:cauldron')});
      expect(
        CauldronSpoutingBehavior.instance.fillBlock(
          world,
          pos,
          null,
          const FStack('create:honey', 1000),
          simulate: false,
        ),
        0,
      );
    });
  });

  group('StateChangingBehavior', () {
    test('setTo replaces the state', () {
      final world = _FakeFluidWorld({pos: const BState('minecraft:dirt')});
      final behavior = StateChangingBehavior.setTo(
        250,
        AllBlockSpoutingBehaviours.isWater,
        const BState('minecraft:mud'),
      );
      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:lava', 250),
          simulate: false,
        ),
        0,
      );
      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:water', 250),
          simulate: false,
        ),
        250,
      );
      expect(world.stateAt(pos).key, 'minecraft:mud');
    });

    test('incrementingState stops at the maximum', () {
      final world = _FakeFluidWorld({
        pos: const BState('minecraft:farmland', {'moisture': '0'}),
      });
      final behavior = StateChangingBehavior.incrementingState(
        100,
        AllBlockSpoutingBehaviours.isWater,
        'moisture',
        max: 7,
      );
      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:water', 100),
          simulate: false,
        ),
        100,
      );
      expect(world.stateAt(pos).intValue('moisture'), 1);

      world.states[pos] = const BState('minecraft:farmland', {'moisture': '7'});
      expect(
        behavior.fillBlock(
          world,
          pos,
          null,
          const FStack('minecraft:water', 100),
          simulate: false,
        ),
        0,
      );
    });
  });

  group('AllBlockSpoutingBehaviours', () {
    test('registers the defaults', () {
      final savedByBlock = Map.of(BlockSpoutingBehaviour.byBlock);
      final savedByBlockEntity = Map.of(BlockSpoutingBehaviour.byBlockEntity);
      addTearDown(() {
        BlockSpoutingBehaviour.byBlock
          ..clear()
          ..addAll(savedByBlock);
        BlockSpoutingBehaviour.byBlockEntity
          ..clear()
          ..addAll(savedByBlockEntity);
      });

      BlockSpoutingBehaviour.clear();
      AllBlockSpoutingBehaviours.registerDefaults();

      expect(
        BlockSpoutingBehaviour.get('minecraft:cauldron'),
        same(CauldronSpoutingBehavior.instance),
      );
      expect(BlockSpoutingBehaviour.get('minecraft:dirt'), isNotNull);
      expect(BlockSpoutingBehaviour.get('minecraft:coarse_dirt'), isNotNull);
      expect(BlockSpoutingBehaviour.get('minecraft:rooted_dirt'), isNotNull);
      expect(BlockSpoutingBehaviour.get('minecraft:farmland'), isNotNull);
      expect(BlockSpoutingBehaviour.get('minecraft:water_cauldron'), isNotNull);
      expect(BlockSpoutingBehaviour.get('minecraft:stone'), isNull);
    });
  });

  group('BlazeBurner', () {
    test('heat levels', () {
      const burner = 'create:blaze_burner';
      expect(
        BlazeBurner.heatOf(const BState(burner, {'blaze': 'none'})),
        BlazeBurner.noHeat,
      );
      expect(
        BlazeBurner.heatOf(const BState(burner, {'blaze': 'smouldering'})),
        BlazeBurner.passiveHeat,
      );
      expect(BlazeBurner.heatOf(const BState(burner, {'blaze': 'fading'})), 1);
      expect(BlazeBurner.heatOf(const BState(burner, {'blaze': 'kindled'})), 1);
      expect(
        BlazeBurner.heatOf(const BState(burner, {'blaze': 'seething'})),
        2,
      );
      expect(
        BlazeBurner.isLit(const BState(burner, {'blaze': 'none'})),
        isFalse,
      );
      expect(
        BlazeBurner.isLit(const BState(burner, {'blaze': 'seething'})),
        isTrue,
      );
    });

    test('fuel data maps', () {
      final savedRegular = Map.of(BlazeBurnerFuels.regular);
      final savedSuperheated = Map.of(BlazeBurnerFuels.superheated);
      addTearDown(() {
        BlazeBurnerFuels.regular
          ..clear()
          ..addAll(savedRegular);
        BlazeBurnerFuels.superheated
          ..clear()
          ..addAll(savedSuperheated);
      });

      expect(BlazeBurnerFuels.superheatedBurnTime('create:blaze_cake'), 3200);
      BlazeBurnerFuels.registerRegular('minecraft:coal', 1600);
      expect(BlazeBurnerFuels.regularBurnTime('minecraft:coal'), 1600);
      expect(
        () => BlazeBurnerFuels.registerRegular('minecraft:coal', 0),
        throwsArgumentError,
      );

      BlazeBurnerFuels.applyDataMap(BlazeBurnerFuels.regularId, {
        'minecraft:coal': 2000,
        'minecraft:stick': {'burn_time': 100},
        'minecraft:bad': -1,
      });
      expect(BlazeBurnerFuels.regularBurnTime('minecraft:coal'), 2000);
      expect(BlazeBurnerFuels.regularBurnTime('minecraft:stick'), 100);
      expect(BlazeBurnerFuels.regularBurnTime('minecraft:bad'), isNull);
      expect(
        () => BlazeBurnerFuels.applyDataMap('create:not_a_fuel_map', const {}),
        throwsArgumentError,
      );
    });
  });
}

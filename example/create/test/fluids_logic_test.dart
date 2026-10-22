import 'package:create/src/api/behaviour/spouting/spouting.dart';
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/bounds.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/fluids/boiler.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/fluid_storage.dart';
import 'package:create/src/fluids/fluid_world.dart';
import 'package:create/src/fluids/open_pipe_effects.dart';
import 'package:create/src/fluids/pipe_blocks.dart';
import 'package:create/src/fluids/pipe_state_logic.dart';
import 'package:create/src/fluids/potion_data.dart';
import 'package:create/src/fluids/potion_fluid.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A [FluidWorld] over maps: enough for the pure fluid logic (no pipes, no host).
final class _TestWorld extends BlockGetter implements FluidWorld {
  final Map<Pos, BState> blocks = {};
  final Map<Pos, FluidInfo> fluids = {};
  final Map<Pos, Set<String>> tags = {};
  final List<(Pos, BState)> set = [];
  final List<String> sounds = [];

  @override
  int get gameTime => 0;

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
  void setBlock(Pos p, BState state, {bool quiet = false}) {
    set.add((p, state));
    blocks[p] = state;
  }

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

  void scheduleFlowTick(Pos p, String fluid, int delay) =>
      scheduleFluidTick(p, fluid, delay);

  @override
  void placeFluidSource(Pos p, String fluid) => blocks[p] = BState(fluid);

  @override
  FStack pickupFluidSource(Pos p) => FStack.empty;

  @override
  void playSound(Pos p, String sound, {double volume = 1, double pitch = 1}) =>
      sounds.add(sound);

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
  bool canBeReplaced(Pos p) => stateAt(p).isAir;

  @override
  bool hasTag(Pos p, String tag) => tags[p]?.contains(tag) ?? false;

  @override
  bool isWater(Pos p) => false;
}

BState _pipe(Map<String, String> open) => BState('create:fluid_pipe', {
  for (final d in Direction.values)
    d.serializedName: open[d.serializedName] ?? 'false',
  'waterlogged': 'false',
});

void main() {
  group('open pipe effects', () {
    setUp(OpenPipeEffects.registerDefaults);

    test('the default handlers are registered', () {
      expect(
        OpenPipeEffects.of(
          'minecraft:water',
          (tag) => tag == 'minecraft:water',
        ),
        OpenPipeEffect.water,
      );
      expect(
        OpenPipeEffects.of(
          'minecraft:flowing_lava',
          (tag) => tag == 'minecraft:lava',
        ),
        OpenPipeEffect.lava,
      );
      expect(
        OpenPipeEffects.of('create:potion', (_) => false),
        OpenPipeEffect.potion,
      );
      expect(
        OpenPipeEffects.of('create:tea', (_) => false),
        OpenPipeEffect.tea,
      );
      expect(
        OpenPipeEffects.of('minecraft:milk', (tag) => tag == 'c:milk'),
        OpenPipeEffect.milk,
      );
      expect(OpenPipeEffects.of('minecraft:stone', (_) => false), isNull);
    });

    test('the game time gate skips four of five ticks', () {
      expect(OpenPipeEffects.shouldApply(5, OpenPipeEffect.water), isTrue);
      expect(OpenPipeEffects.shouldApply(4, OpenPipeEffect.water), isFalse);
      expect(OpenPipeEffects.shouldApply(4, OpenPipeEffect.potion), isTrue);
    });

    test('water douses fire, candles and campfires', () {
      final world = _TestWorld();
      world.blocks[(0, 0, 0)] = const BState('minecraft:fire');
      world.tags[(0, 0, 0)] = {'minecraft:fire'};
      expect(OpenPipeEffects.dousedState(world, (0, 0, 0)), BState.air);

      world.blocks[(1, 0, 0)] = const BState('minecraft:candle', {
        'lit': 'true',
      });
      expect(
        OpenPipeEffects.dousedState(world, (1, 0, 0))?.flag('lit'),
        isFalse,
      );

      world.blocks[(2, 0, 0)] = const BState('minecraft:campfire', {
        'lit': 'true',
      });
      expect(
        OpenPipeEffects.dousedState(world, (2, 0, 0))?.flag('lit'),
        isFalse,
      );

      world.blocks[(3, 0, 0)] = const BState('minecraft:stone');
      expect(OpenPipeEffects.dousedState(world, (3, 0, 0)), isNull);
    });

    test('an area covers the blocks between its corners', () {
      final positions = OpenPipeEffects.positionsIn(Aabb(0, 0, 0, 2, 1, 3))
          .toList();
      expect(positions, hasLength(6));
      expect(positions, contains((0, 0, 0)));
      expect(positions, contains((1, 0, 2)));
    });
  });

  group('spout targets', () {
    setUp(AllBlockSpoutingBehaviours.registerDefaults);

    test('dirt turns into mud for 250 mB of water', () {
      final world = _TestWorld();
      world.blocks[(0, 0, 0)] = const BState('minecraft:dirt');
      final fill = BlockSpoutingBehaviour.get(world.stateAt((0, 0, 0)).key)!;

      expect(
        fill.fillBlock(
          world,
          (0, 0, 0),
          null,
          const FStack(FluidKeys.water, 250),
          simulate: true,
        ),
        250,
      );
      expect(world.set, isEmpty);

      expect(
        fill.fillBlock(
          world,
          (0, 0, 0),
          null,
          const FStack(FluidKeys.water, 250),
          simulate: false,
        ),
        250,
      );
      expect(world.stateAt((0, 0, 0)).key, 'minecraft:mud');
    });

    test('farmland moisture increases up to 7', () {
      final world = _TestWorld();
      world.blocks[(0, 0, 0)] = const BState('minecraft:farmland', {
        'moisture': '6',
      });
      final fill = BlockSpoutingBehaviour.get(world.stateAt((0, 0, 0)).key)!;

      expect(
        fill.fillBlock(
          world,
          (0, 0, 0),
          null,
          const FStack(FluidKeys.water, 100),
          simulate: false,
        ),
        100,
      );
      expect(world.stateAt((0, 0, 0)).intValue('moisture'), 7);

      expect(
        fill.fillBlock(
          world,
          (0, 0, 0),
          null,
          const FStack(FluidKeys.water, 100),
          simulate: false,
        ),
        0,
      );
    });

    test('an empty cauldron takes water or lava', () {
      final world = _TestWorld();
      world.blocks[(0, 0, 0)] = const BState('minecraft:cauldron');
      final fill = BlockSpoutingBehaviour.get(world.stateAt((0, 0, 0)).key)!;

      expect(
        fill.fillBlock(
          world,
          (0, 0, 0),
          null,
          const FStack(FluidKeys.water, 250),
          simulate: false,
        ),
        250,
      );
      expect(world.stateAt((0, 0, 0)).key, 'minecraft:water_cauldron');

      world.blocks[(1, 0, 0)] = const BState('minecraft:cauldron');
      expect(
        fill.fillBlock(
          world,
          (1, 0, 0),
          null,
          const FStack(FluidKeys.lava, 1000),
          simulate: false,
        ),
        1000,
      );
      expect(world.stateAt((1, 0, 0)).key, 'minecraft:lava_cauldron');
    });

    test('a full water cauldron does not overflow', () {
      final world = _TestWorld();
      world.blocks[(0, 0, 0)] = const BState('minecraft:water_cauldron', {
        'level': '3',
      });
      final fill = BlockSpoutingBehaviour.get(world.stateAt((0, 0, 0)).key)!;
      expect(
        fill.fillBlock(
          world,
          (0, 0, 0),
          null,
          const FStack(FluidKeys.water, 250),
          simulate: false,
        ),
        0,
      );
    });
  });

  group('potion fluids', () {
    test('a vanilla potion resolves to its effects', () {
      expect(
        PotionEffects.of(const PotionFluidData('minecraft:healing'))
            .single
            .effect,
        'minecraft:instant_health',
      );
      expect(
        PotionEffects.of(const PotionFluidData('minecraft:strong_swiftness'))
            .single
            .amplifier,
        1,
      );
      expect(
        PotionEffects.of(const PotionFluidData('minecraft:water')),
        isEmpty,
      );
    });

    test('custom effects are appended', () {
      const data = PotionFluidData(
        'minecraft:water',
        customEffects: [PotionEffectData('minecraft:speed', duration: 20)],
      );
      final effects = PotionEffects.of(data);
      expect(effects, hasLength(1));
      expect(effects.single.effect, 'minecraft:speed');
      expect(effects.single.duration, 20);
    });

    test('the potion data survives the fluid data round trip', () {
      final stack = const PotionFluidData(
        'minecraft:strength',
        bottle: BottleType.splash,
      ).toStack(250);
      final decoded = PotionFluidData.decode(stack.data);
      expect(decoded?.potion, 'minecraft:strength');
      expect(decoded?.bottle, BottleType.splash);
    });

    test('the type carries the tint and the description id', () {
      const type = PotionFluidType();
      final stack = const PotionFluidData('minecraft:strength').toStack(250);
      expect(type.tintColor(stack), 0xFF932423);
      expect(type.descriptionId(stack), contains('minecraft.strength'));
      expect(PotionFluidType.info.luminance, 0);
    });
  });

  group('pipe state', () {
    test('a lone pipe gets the preferred axis', () {
      final world = _TestWorld();
      final state = PipeStateLogic.updateBlockState(
        _pipe(const {}),
        Direction.north,
        null,
        world,
        (0, 0, 0),
      );
      expect(state.flag('north'), isTrue);
      expect(state.flag('south'), isTrue);
      expect(PipeBlocks.straightPipeAxis(state), Axis.z);
    });

    test('a neighbouring pipe is a connection', () {
      final world = _TestWorld();
      world.blocks[(0, 0, 1)] = _pipe(const {});
      expect(
        PipeStateLogic.canConnectTo(
          world,
          (0, 0, 1),
          world.stateAt((0, 0, 1)),
          Direction.south,
        ),
        isTrue,
      );
    });

    test('the valve axis follows facing and axis_along_first', () {
      const northFirst = BState('create:fluid_valve', {
        'facing': 'north',
        'axis_along_first': 'true',
      });
      expect(PipeBlocks.valvePipeAxis(northFirst), Axis.y);
      const northSecond = BState('create:fluid_valve', {
        'facing': 'north',
        'axis_along_first': 'false',
      });
      expect(PipeBlocks.valvePipeAxis(northSecond), Axis.x);
    });
  });

  group('boiler', () {
    test('the heat level is limited by the boiler size', () {
      final boiler = BoilerData();
      expect(boiler.getMaxHeatLevelForBoilerSize(3), 0);
      expect(boiler.getMaxHeatLevelForBoilerSize(4), 1);
      expect(boiler.getMaxHeatLevelForBoilerSize(72), 18);
    });

    test('the water supply limits the actual heat', () {
      final boiler = BoilerData()
        ..activeHeat = 5
        ..waterSupply = 100;
      expect(boiler.getMaxHeatLevelForWaterSupply(), 10);
      expect(boiler.getActualHeat(72), 5);
    });

    test('the boiler handler takes water and nothing else', () {
      final boiler = BoilerData();
      final handler = boiler.createHandler();
      expect(
        handler.fill(const FStack(FluidKeys.water, 100), simulate: false),
        100,
      );
      expect(boiler.gatheredSupply, 100);
      expect(
        handler.fill(const FStack(FluidKeys.lava, 100), simulate: false),
        0,
      );
      expect(handler.drain(100, simulate: false), FStack.empty);
    });
  });
}

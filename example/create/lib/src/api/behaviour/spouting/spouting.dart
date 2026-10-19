// `BlockSpoutingBehaviour`, `StateChangingBehavior` and `CauldronSpoutingBehavior` (pure): what a
// spout does when it is not filling an item, e.g. filling a cauldron two blocks below.
//
// The behaviour is queried by block first and then by block entity type, like Java. `fillBlock`
// returns the amount of fluid consumed (0 to idle); with `simulate` it only reports whether it
// would work. The target world is a [FluidWorld], so the same logic runs in tests.
import '../../../common/pos.dart';
import '../../../fluids/fluid_stack.dart';
import '../../../fluids/fluid_world.dart';
import '../../block_state.dart';

/// `BlockSpoutingBehaviour`.
abstract interface class BlockSpoutingBehaviour {
  /// `BY_BLOCK`.
  static final Map<String, BlockSpoutingBehaviour> byBlock = {};

  /// `BY_BLOCK_ENTITY`.
  static final Map<String, BlockSpoutingBehaviour> byBlockEntity = {};

  /// `BY_BLOCK.register(block, behaviour)`.
  static void registerForBlock(
    String blockKey,
    BlockSpoutingBehaviour behaviour,
  ) => byBlock[blockKey] = behaviour;

  /// `BY_BLOCK_ENTITY.register(type, behaviour)`.
  static void registerForBlockEntity(
    String blockEntityTypeKey,
    BlockSpoutingBehaviour behaviour,
  ) => byBlockEntity[blockEntityTypeKey] = behaviour;

  /// `BlockSpoutingBehaviour.get(level, pos)`: the block's behaviour, then the block entity's.
  static BlockSpoutingBehaviour? get(
    String blockKey, [
    String? blockEntityTypeKey,
  ]) =>
      byBlock[blockKey] ??
      (blockEntityTypeKey == null ? null : byBlockEntity[blockEntityTypeKey]);

  /// Removes every registration (tests and reloads).
  static void clear() {
    byBlock.clear();
    byBlockEntity.clear();
  }

  /// `fillBlock(level, pos, spout, availableFluid, simulate)`: the amount of fluid used, 0 to
  /// idle. [spout] is the calling block entity, passed through for behaviours that need it.
  int fillBlock(
    FluidWorld level,
    Pos pos,
    Object? spout,
    FStack availableFluid, {
    required bool simulate,
  });
}

/// `CauldronSpoutingBehavior.CauldronInfo`: the amount needed to fill an empty cauldron and the
/// state it becomes.
final class CauldronInfo {
  /// `amount`.
  final int amount;

  /// `cauldron`: the block state set after filling.
  final BState cauldron;

  const CauldronInfo(this.amount, this.cauldron);
}

/// `CauldronSpoutingBehavior`: fills empty cauldrons with registered fluids. Create registers
/// water (250 mB, the default water cauldron state) and lava (1000 mB, a lava cauldron).
final class CauldronSpoutingBehavior implements BlockSpoutingBehaviour {
  const CauldronSpoutingBehavior._();

  /// `INSTANCE`.
  static const CauldronSpoutingBehavior instance = CauldronSpoutingBehavior._();

  /// `CAULDRON_INFO`: fluid key to its cauldron. Mods add their own fluids here.
  ///
  /// Water uses `Blocks.WATER_CAULDRON.defaultBlockState()`, whose level is 1 (one bottle).
  static final Map<String, CauldronInfo> cauldronInfo = {
    'minecraft:water': const CauldronInfo(
      250,
      BState('minecraft:water_cauldron', {'level': '1'}),
    ),
    'minecraft:lava': const CauldronInfo(
      1000,
      BState('minecraft:lava_cauldron'),
    ),
  };

  @override
  int fillBlock(
    FluidWorld level,
    Pos pos,
    Object? spout,
    FStack availableFluid, {
    required bool simulate,
  }) {
    final info = cauldronInfo[availableFluid.fluid];
    if (info == null) return 0;
    if (availableFluid.amount < info.amount) return 0;
    if (!simulate) level.setBlock(pos, info.cauldron);
    return info.amount;
  }
}

/// `StateChangingBehavior`: a spout behaviour that changes the target block's state.
final class StateChangingBehavior implements BlockSpoutingBehaviour {
  /// `amount`: the fluid consumed per fill.
  final int amount;

  /// `fluidTest`: fluids that may fill the target.
  final bool Function(String fluidKey) fluidTest;

  /// `canFill`: whether the current state may be filled.
  final bool Function(BState state) canFill;

  /// `fillFunction`: the state after filling.
  final BState Function(BState state) fillFunction;

  const StateChangingBehavior(
    this.amount,
    this.fluidTest,
    this.canFill,
    this.fillFunction,
  );

  @override
  int fillBlock(
    FluidWorld level,
    Pos pos,
    Object? spout,
    FStack availableFluid, {
    required bool simulate,
  }) {
    if (availableFluid.amount < amount || !fluidTest(availableFluid.fluid))
      return 0;
    final state = level.stateAt(pos);
    if (!canFill(state)) return 0;
    if (!simulate) level.setBlock(pos, fillFunction(state));
    return amount;
  }

  /// `StateChangingBehavior.setTo(amount, fluidTest, block)`: always replaces the state.
  static StateChangingBehavior setTo(
    int amount,
    bool Function(String fluidKey) fluidTest,
    BState newState,
  ) => StateChangingBehavior(amount, fluidTest, (_) => true, (_) => newState);

  /// `StateChangingBehavior.incrementingState(amount, fluidTest, property)`: increments an integer
  /// property until [max]. Java reads the maximum from the property's possible values; Dart has
  /// no block state registry in the pure API, so the caller passes it.
  static StateChangingBehavior incrementingState(
    int amount,
    bool Function(String fluidKey) fluidTest,
    String property, {
    required int max,
  }) {
    bool canFill(BState state) =>
        state.has(property) && state.intValue(property) < max;
    BState fill(BState state) =>
        state.setInt(property, state.intValue(property) + 1);
    return StateChangingBehavior(amount, fluidTest, canFill, fill);
  }
}

/// `AllBlockSpoutingBehaviours.registerDefaults()`: the spout targets Create itself registers
/// (dirt to mud, farmland moisture, cauldrons). The fluids module calls this in `onLoad`; the
/// Tinkers' Construct compat is not ported.
abstract final class AllBlockSpoutingBehaviours {
  /// `fluid.isSame(Fluids.WATER)`.
  static bool isWater(String fluidKey) => fluidKey == 'minecraft:water';

  /// Registers the defaults. Calling it twice re-registers the same keys with the same values.
  static void registerDefaults() {
    final toMud = StateChangingBehavior.setTo(
      250,
      isWater,
      const BState('minecraft:mud'),
    );
    for (final dirt in const [
      'minecraft:dirt',
      'minecraft:coarse_dirt',
      'minecraft:rooted_dirt',
    ]) {
      BlockSpoutingBehaviour.registerForBlock(dirt, toMud);
    }

    // `FarmlandBlock.MOISTURE` is 0..7.
    BlockSpoutingBehaviour.registerForBlock(
      'minecraft:farmland',
      StateChangingBehavior.incrementingState(100, isWater, 'moisture', max: 7),
    );
    // `LayeredCauldronBlock.LEVEL` is 1..3.
    BlockSpoutingBehaviour.registerForBlock(
      'minecraft:water_cauldron',
      StateChangingBehavior.incrementingState(250, isWater, 'level', max: 3),
    );
    BlockSpoutingBehaviour.registerForBlock(
      'minecraft:cauldron',
      CauldronSpoutingBehavior.instance,
    );
  }
}

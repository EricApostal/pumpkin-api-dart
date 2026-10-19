// `OpenPipeEffectHandler` and `AllOpenPipeEffectHandlers` (pure): which effect a fluid
// applies when an open pipe spills it, and the block changes water makes. The entity
// effects themselves are applied by the host (`HostFluidWorld.applyOpenPipeEffect`), which
// owns the entity API; the decisions live here so they run on the plain VM in tests.
import '../api/block_state.dart';
import '../common/bounds.dart';
import '../common/pos.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';

/// The handler kinds `AllOpenPipeEffectHandlers` registers.
enum OpenPipeEffect { water, lava, milk, potion, tea }

/// `OpenPipeEffectHandler.REGISTRY` with the defaults of `AllOpenPipeEffectHandlers`.
abstract final class OpenPipeEffects {
  static final Map<String, OpenPipeEffect> _byFluid = {};
  static final Map<String, OpenPipeEffect> _byTag = {};

  /// `REGISTRY.register(fluid, handler)`.
  static void register(String fluid, OpenPipeEffect effect) =>
      _byFluid[FluidKeys.still(fluid)] = effect;

  /// `registerProvider(forFluidTag(tag, handler))`.
  static void registerTag(String tag, OpenPipeEffect effect) =>
      _byTag[tag] = effect;

  /// `AllOpenPipeEffectHandlers.registerDefaults`.
  static void registerDefaults() {
    registerTag('minecraft:water', OpenPipeEffect.water);
    registerTag('minecraft:lava', OpenPipeEffect.lava);
    registerTag('c:milk', OpenPipeEffect.milk);
    register(FluidKeys.potion, OpenPipeEffect.potion);
    register(FluidKeys.tea, OpenPipeEffect.tea);
  }

  /// The handler of [fluid], `null` when it has none. [hasTag] answers `Fluid.is(tag)`
  /// (`FluidWorld.fluidHasTag` on the host).
  static OpenPipeEffect? of(String fluid, bool Function(String tag) hasTag) {
    final still = FluidKeys.still(fluid);
    final direct = _byFluid[still];
    if (direct != null) return direct;
    for (final entry in _byTag.entries) {
      if (hasTag(entry.key)) return entry.value;
    }
    return null;
  }

  /// The handler of [fluid] in [world] (the fluid tags come from the host).
  static OpenPipeEffect? ofWorld(FluidWorld world, String fluid) =>
      of(fluid, (tag) => world.fluidHasTag(FluidKeys.still(fluid), tag));

  /// `level.getGameTime() % 5 != 0` gates every default handler except the potion one.
  static bool shouldApply(int gameTime, OpenPipeEffect effect) =>
      effect == OpenPipeEffect.potion || gameTime % 5 == 0;

  /// The blocks a water spill changes (`WaterEffectHandler.dowseFire`), as the positions
  /// in [area] that become [BState.air], an unlit candle or an unlit campfire.
  static Iterable<Pos> dousedPositions(FluidWorld world, Aabb area) sync* {
    for (final pos in positionsIn(area)) {
      final state = world.stateAt(pos);
      if (state.isAir) continue;
      if (world.hasTag(pos, 'minecraft:fire') ||
          _isLitCandle(state) ||
          _isLitCampfire(state)) {
        yield pos;
      }
    }
  }

  /// The state water leaves at [pos] (`WaterEffectHandler.dowseFire`), or `null` when the
  /// block is not affected.
  static BState? dousedState(FluidWorld world, Pos pos) {
    final state = world.stateAt(pos);
    if (state.isAir) return null;
    if (world.hasTag(pos, 'minecraft:fire')) return BState.air;
    if (_isLitCandle(state) || _isLitCampfire(state)) {
      return state.setFlag('lit', false);
    }
    return null;
  }

  /// `AbstractCandleBlock.isLit` for the candle blocks (`minecraft:candle`, the dyed ones).
  static bool _isLitCandle(BState state) =>
      state.has('lit') &&
      state.flag('lit') &&
      (state.key == 'minecraft:candle' || state.key.endsWith('_candle'));

  /// `CampfireBlock.isLitCampfire`.
  static bool _isLitCampfire(BState state) =>
      (state.key == 'minecraft:campfire' ||
          state.key == 'minecraft:soul_campfire') &&
      state.flag('lit');

  /// `BlockPos.betweenClosed(AABB)`: the blocks covered by [area] (the max corner is
  /// exclusive).
  static Iterable<Pos> positionsIn(Aabb area) sync* {
    final x0 = area.minX.floor();
    final x1 = (area.maxX - 1.0e-7).floor();
    final y0 = area.minY.floor();
    final y1 = (area.maxY - 1.0e-7).floor();
    final z0 = area.minZ.floor();
    final z1 = (area.maxZ - 1.0e-7).floor();
    for (var y = y0; y <= y1; y++) {
      for (var z = z0; z <= z1; z++) {
        for (var x = x0; x <= x1; x++) {
          yield (x, y, z);
        }
      }
    }
  }
}

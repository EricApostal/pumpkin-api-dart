// `BlazeBurnerBlockEntity`: the burner's fuel (none / normal / superheated), the burn timer,
// the heat level it shows on the block (`none` .. `seething`), the stock keeper flag and the
// creative fuel. The block state's `blaze` property is what the basin (heat) and the steam
// boiler (`create:passive_boiler_heaters` / `BoilerHeaters.blazeBurner`) read.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../core/block_entity.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../processing_runtime.dart';
import '../recipe/heat.dart';
import 'blaze_burner_block.dart';

/// `BlazeBurnerBlockEntity.FuelType`.
enum FuelType { none, normal, special }

/// `BlazeBurnerBlockEntity`.
class BlazeBurnerBlockEntity extends CreateBlockEntity implements FuelAcceptor {
  static const String type = 'create:blaze_heater';

  /// `MAX_HEAT_CAPACITY`.
  static const int maxHeatCapacity = 10000;

  /// `INSERTION_THRESHOLD`.
  static const int insertionThreshold = 500;

  /// `goggles`: the goggles are shown on the burner.
  bool goggles = false;

  /// `stockKeeper`: a stock ticker is next to the burner.
  bool stockKeeper = false;

  /// `hat`: the conductor hat of trains (rendering only, kept for the client data).
  bool hat = false;

  bool isCreative = false;

  FuelType activeFuel = FuelType.none;
  int remainingBurnTime = 0;

  BlazeBurnerBlockEntity(super.worldId, super.pos);

  ProcessingRuntime get _rt => ProcessingRuntime.instance;

  FuelType get activeFuelType => activeFuel;
  int get remainingBurnTimeTicks => remainingBurnTime;

  /// `getHeatLevelFromBlock`.
  HeatLevel get heatLevelFromBlock {
    final w = world;
    if (w == null) return HeatLevel.none;
    return BlazeBurnerBlock.heatLevelOf(
      HostBlockGetter(w).stateAt(pos.toPos()),
    );
  }

  /// `getHeatLevelForRender`: a stock keeper glows at least `fading`.
  HeatLevel get heatLevelForRender {
    final heat = heatLevelFromBlock;
    if (!heat.isAtLeast(HeatLevel.fading) && stockKeeper)
      return HeatLevel.fading;
    return heat;
  }

  /// `getHeatLevel()` from the active fuel and the remaining burn time.
  HeatLevel get heatLevel {
    switch (activeFuel) {
      case FuelType.special:
        return HeatLevel.seething;
      case FuelType.normal:
        final lowPercent = remainingBurnTime / maxHeatCapacity < 0.0125;
        return lowPercent ? HeatLevel.fading : HeatLevel.kindled;
      case FuelType.none:
        return HeatLevel.smouldering;
    }
  }

  @override
  void tick() {
    super.tick();
    if (isCreative) return;

    if (remainingBurnTime > 0) remainingBurnTime--;
    if (activeFuel == FuelType.normal) updateBlockState();
    if (remainingBurnTime > 0) return;

    if (activeFuel == FuelType.special) {
      activeFuel = FuelType.normal;
      remainingBurnTime = maxHeatCapacity ~/ 2;
    } else {
      activeFuel = FuelType.none;
    }
    updateBlockState();
  }

  @override
  void lazyTick() {
    super.lazyTick();
    stockKeeper = getStockTicker() != null;
  }

  /// `getStockTicker(level, pos)`: a stock ticker on one of the four horizontal sides.
  CreateBlockEntity? getStockTicker() {
    final w = world;
    if (w == null) return null;
    final getter = HostBlockGetter(w);
    final p = pos.toPos();
    for (final direction in Direction.planeHorizontal) {
      if (getter.stateAt(p.relative(direction)).key != 'create:stock_ticker')
        continue;
      return store.at(worldId, p.relative(direction).toBlockPos());
    }
    return null;
  }

  /// `isValidBlockAbove`: a basin or a fluid tank on top of the burner.
  bool get isValidBlockAbove {
    final w = world;
    if (w == null) return false;
    final above = HostBlockGetter(w).stateAt(pos.toPos().above);
    return above.key == 'create:basin' || above.key == 'create:fluid_tank';
  }

  /// `updateBlockState`.
  void updateBlockState() => setBlockHeat(heatLevel);

  /// `setBlockHeat(heat)`.
  void setBlockHeat(HeatLevel heat) {
    final w = world;
    if (w == null) return;
    final state = HostBlockGetter(w).stateAt(pos.toPos());
    if (state.key != BlazeBurnerBlock.key) return;
    if (BlazeBurnerBlock.heatLevelOf(state) == heat) return;
    unawaited(
      setBlockState(
        w,
        pos.toPos(),
        state.setValue(BlazeBurnerBlock.blazeProperty, heat.serializedName),
      ),
    );
  }

  /// `isCreativeFuel(stack)`.
  bool isCreativeFuel(PStack stack) =>
      stack.isNotEmpty && stack.key == 'create:creative_blaze_cake';

  /// `applyCreativeFuel()`.
  void applyCreativeFuel() {
    activeFuel = FuelType.none;
    remainingBurnTime = 0;
    isCreative = true;

    var next = heatLevelFromBlock.nextActiveLevel();
    if (next == HeatLevel.fading) next = next.nextActiveLevel();
    setBlockHeat(next);
  }

  /// `tryUpdateFuel(itemStack, forceOverflow, simulate)`: true when the fuel is accepted.
  bool tryUpdateFuel(
    PStack stack, {
    required bool forceOverflow,
    required bool simulate,
  }) {
    if (isCreative) return false;

    var newFuel = FuelType.none;
    var newBurnTime = 0;

    final special = BlazeBurnerBlock.specialFuelBurnTime(stack.key);
    final regular = BlazeBurnerBlock.regularFuelBurnTime(stack.key);
    if (special != null) {
      newBurnTime = special;
      newFuel = FuelType.special;
    } else if (regular != null) {
      newBurnTime = regular;
      newFuel = FuelType.normal;
    } else if (_rt.tags.itemHasTag(
      stack.key,
      'create:blaze_burner_fuel/special',
    )) {
      newBurnTime = 3200;
      newFuel = FuelType.special;
    } else if (_rt.tags.itemHasTag(
      stack.key,
      'create:blaze_burner_fuel/regular',
    )) {
      newBurnTime = 1600;
      newFuel = FuelType.normal;
    }

    if (newFuel == FuelType.none) return false;
    if (newFuel.index < activeFuel.index) return false;

    if (newFuel == activeFuel) {
      if (remainingBurnTime <= insertionThreshold) {
        newBurnTime += remainingBurnTime;
      } else if (forceOverflow && newFuel == FuelType.normal) {
        newBurnTime = remainingBurnTime < maxHeatCapacity
            ? min(remainingBurnTime + newBurnTime, maxHeatCapacity)
            : remainingBurnTime;
      } else {
        return false;
      }
    }

    if (simulate) return true;

    activeFuel = newFuel;
    remainingBurnTime = newBurnTime;
    updateBlockState();
    return true;
  }

  /// `FuelAcceptor.tryInsertFuel`: the remainder of [stack].
  @override
  PStack tryInsertFuel(
    PStack stack, {
    bool doNotConsume = false,
    bool forceOverflow = false,
    bool simulate = false,
  }) {
    if (stack.isEmpty) return PStack.empty;
    // An unlit burner has no block entity in Java; here it has one but takes no fuel.
    if (heatLevelFromBlock == HeatLevel.none) return stack;

    if (isCreativeFuel(stack)) {
      if (!simulate) applyCreativeFuel();
      return PStack.empty;
    }
    if (!tryUpdateFuel(stack, forceOverflow: forceOverflow, simulate: simulate))
      return stack;
    if (doNotConsume) return PStack.empty;
    // The crafting remainder of the fuel item (lava buckets give their bucket back) is not
    // available from the host; the common bucket case is handled by the block item's use.
    return stack.shrink(1);
  }

  // -- NBT ---------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    if (!isCreative) {
      tag.putInt('fuelLevel', activeFuel.index);
      tag.putInt('burnTimeRemaining', remainingBurnTime);
    } else {
      tag.putBool('isCreative', true);
    }
    if (goggles) tag.putBool('Goggles', true);
    if (hat) tag.putBool('TrainHat', true);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final fuel = (tag.getInt('fuelLevel') ?? 0).clamp(
      0,
      FuelType.values.length - 1,
    );
    activeFuel = FuelType.values[fuel];
    remainingBurnTime = tag.getInt('burnTimeRemaining') ?? 0;
    isCreative = tag.getBool('isCreative') ?? false;
    goggles = tag.containsKey('Goggles');
    hat = tag.containsKey('TrainHat');
    super.read(tag, clientPacket: clientPacket);
  }
}

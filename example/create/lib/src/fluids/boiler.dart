// `BoilerData` and `BoilerHeaters` (pure): the steam boiler a fluid tank turns into when steam
// engines or whistles sit on it. The tank multiblock is the controller; water poured into the
// boiler is consumed as steam and gives the water supply, the burners below give the heat.
import 'dart:math' as math;

import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'fluid_helper.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';
import 'pipe_blocks.dart';

/// `BoilerHeater`: the heat a block gives to a boiler on top of it. [passiveHeat] is the small
/// free heat of fire and magma, [noHeat] no heat at all; positive values are heat levels.
typedef BoilerHeaterFn = double Function(
  FluidWorld world,
  Pos pos,
  BState state,
);

abstract final class BoilerHeaters {
  static const double passiveHeat = 0;
  static const double noHeat = -1;

  static final Map<String, BoilerHeaterFn> _blocks = {};
  static final Map<String, BoilerHeaterFn> _tags = {};

  /// `BoilerHeater.REGISTRY.register(block, heater)`.
  static void register(String blockKey, BoilerHeaterFn heater) =>
      _blocks[blockKey] = heater;

  /// `registerProvider(forBlockTag(tag, heater))`.
  static void registerTag(String tag, BoilerHeaterFn heater) =>
      _tags[tag] = heater;

  /// Registers the defaults of `BoilerHeaters.registerDefaults`.
  static void registerDefaults() {
    register('create:blaze_burner', blazeBurner);
    registerTag('create:passive_boiler_heaters', passive);
  }

  /// `BoilerHeaters.passive`.
  static double passive(FluidWorld level, Pos pos, BState state) =>
      isNotUnheated(state) ? passiveHeat : noHeat;

  /// `BlockHelper.isNotUnheated`: lit campfires, burners that burn.
  static bool isNotUnheated(BState state) {
    if ((state.key == 'minecraft:campfire' ||
            state.key == 'minecraft:soul_campfire') &&
        state.has('lit')) {
      return state.flag('lit');
    }
    if (state.has('blaze')) return state['blaze'] != 'none';
    return true;
  }

  static const List<String> _heatLevels = [
    'none',
    'smouldering',
    'fading',
    'kindled',
    'seething',
  ];

  /// `BoilerHeaters.blazeBurner`.
  static double blazeBurner(FluidWorld level, Pos pos, BState state) {
    // The manifest names the property `blaze` (`BlazeBurnerBlock.HEAT_LEVEL`).
    final value = state['blaze'] ?? state['heat_level'] ?? 'none';
    if (value == 'none') return noHeat;
    if (value == 'seething') return 2;
    if (_heatLevels.indexOf(value) >= _heatLevels.indexOf('fading')) return 1;
    return passiveHeat;
  }

  /// `BoilerHeater.findHeat(level, pos, state)`.
  static double findHeat(FluidWorld level, Pos pos, BState state) {
    final byBlock = _blocks[state.key];
    if (byBlock != null) return byBlock(level, pos, state);
    for (final e in _tags.entries) {
      if (level.hasTag(pos, e.key)) return e.value(level, pos, state);
    }
    return noHeat;
  }
}

/// What the boiler needs to know of its tank (the controller block entity).
abstract interface class BoilerHost {
  FluidWorld get fluidWorld;

  /// The controller's position (the minimum corner of the tank).
  Pos get controllerPos;

  int get width;
  int get height;

  /// `tankInventory.getCapacity()`.
  int get tankCapacity;

  int get totalTankSize;

  /// The controller is a creative fluid tank.
  bool get isCreative;

  /// `notifyUpdate()`.
  void notifyUpdate();

  /// `award(advancement)` for the tank's owner.
  void award(String advancement);

  /// `getPitchId` of the whistle at [pos] (`WhistleBlockEntity`), for the pipe organ advancement.
  int? whistlePitchAt(Pos pos);
}

class BoilerData {
  static const int sampleRate = 5;
  static const int waterSupplyPerLevel = 10;
  static const double passiveEngineEfficiency = 1 / 8;

  /// Pooled water supply.
  int gatheredSupply = 0;

  final List<double> supplyOverTime = List<double>.filled(10, 0);
  int ticksUntilNextSample = 0;
  int currentIndex = 0;

  // heat score
  bool needsHeatLevelUpdate = false;
  bool passiveHeat = false;
  int activeHeat = 0;
  double waterSupply = 0;
  int attachedEngines = 0;
  int attachedWhistles = 0;

  // display
  int maxHeatForSize = 0;
  int maxHeatForWater = 0;
  int minValue = 0;
  int maxValue = 0;

  /// `tick(controller)`.
  void tick(BoilerHost controller) {
    if (!isActive) return;
    if (needsHeatLevelUpdate && updateTemperature(controller))
      controller.notifyUpdate();

    ticksUntilNextSample--;
    if (ticksUntilNextSample > 0) return;
    final capacity = controller.tankCapacity;
    if (capacity == 0) return;

    ticksUntilNextSample = sampleRate;
    supplyOverTime[currentIndex] = gatheredSupply / sampleRate;
    waterSupply = math.max(waterSupply, supplyOverTime[currentIndex]);
    currentIndex = (currentIndex + 1) % supplyOverTime.length;
    gatheredSupply = 0;

    if (currentIndex == 0) {
      waterSupply = 0;
      for (final i in supplyOverTime) {
        waterSupply = math.max(i, waterSupply);
      }
    }

    if (controller.isCreative)
      waterSupply = (waterSupplyPerLevel * 20).toDouble();

    if (getActualHeat(controller.totalTankSize) == 18)
      controller.award('steam_engine_maxed');
    controller.notifyUpdate();
  }

  int get theoreticalHeatLevel => activeHeat;

  /// `getMaxHeatLevelForBoilerSize(boilerSize)`.
  int getMaxHeatLevelForBoilerSize(int boilerSize) =>
      math.min(18, boilerSize ~/ 4);

  /// `getMaxHeatLevelForWaterSupply()`.
  int getMaxHeatLevelForWaterSupply() =>
      math.min(18, waterSupply.ceil() ~/ waterSupplyPerLevel);

  bool get isPassiveNow =>
      passiveHeat && maxHeatForSize > 0 && maxHeatForWater > 0;

  /// `isPassive(boilerSize)`.
  bool isPassive(int boilerSize) {
    calcMinMaxForSize(boilerSize);
    return isPassiveNow;
  }

  /// `getEngineEfficiency(boilerSize)`.
  double getEngineEfficiency(int boilerSize) {
    if (isPassive(boilerSize)) return passiveEngineEfficiency / attachedEngines;
    if (activeHeat == 0) return 0;
    final actualHeat = getActualHeat(boilerSize);
    return attachedEngines <= actualHeat ? 1 : actualHeat / attachedEngines;
  }

  /// `getActualHeat(boilerSize)`.
  int getActualHeat(int boilerSize) {
    final forBoilerSize = getMaxHeatLevelForBoilerSize(boilerSize);
    final forWaterSupply = getMaxHeatLevelForWaterSupply();
    return math.min(activeHeat, math.min(forWaterSupply, forBoilerSize));
  }

  /// `calcMinMaxForSize(boilerSize)`.
  void calcMinMaxForSize(int boilerSize) {
    maxHeatForSize = getMaxHeatLevelForBoilerSize(boilerSize);
    maxHeatForWater = getMaxHeatLevelForWaterSupply();
    minValue = math.min(
      passiveHeat ? 1 : activeHeat,
      math.min(maxHeatForWater, maxHeatForSize),
    );
    maxValue = math.max(
      passiveHeat ? 1 : activeHeat,
      math.max(maxHeatForWater, maxHeatForSize),
    );
  }

  /// `getHeatLevelTextComponent` as a key: `passive`, `idle`, `max_lvl` or `lvl N`.
  String get heatLevelText {
    final boilerLevel = math.min(
      activeHeat,
      math.min(maxHeatForWater, maxHeatForSize),
    );
    if (isPassiveNow) return 'passive';
    if (boilerLevel == 0) return 'idle';
    if (boilerLevel == 18) return 'max_lvl';
    return 'lvl $boilerLevel';
  }

  /// `evaluate(controller)`: counts the engines and whistles on the tank. Returns whether they
  /// changed.
  bool evaluate(BoilerHost controller) {
    final controllerPos = controller.controllerPos;
    final level = controller.fluidWorld;
    final prevEngines = attachedEngines;
    final prevWhistles = attachedWhistles;
    attachedEngines = 0;
    attachedWhistles = 0;

    for (var yOffset = 0; yOffset < controller.height; yOffset++) {
      for (var xOffset = 0; xOffset < controller.width; xOffset++) {
        for (var zOffset = 0; zOffset < controller.width; zOffset++) {
          final pos = controllerPos.offset(xOffset, yOffset, zOffset);
          final blockState = level.stateAt(pos);
          if (!PipeBlocks.isTank(blockState)) continue;
          for (final d in Direction.values) {
            final attachedPos = pos.relative(d);
            final attachedState = level.stateAt(attachedPos);
            if (attachedState.key == PipeKeys.steamEngine &&
                steamEngineFacing(attachedState) == d)
              attachedEngines++;
            if (attachedState.key == PipeKeys.steamWhistle &&
                whistleAttachedDirection(attachedState).opposite == d) {
              attachedWhistles++;
            }
          }
        }
      }
    }
    needsHeatLevelUpdate = true;
    return prevEngines != attachedEngines || prevWhistles != attachedWhistles;
  }

  /// `SteamEngineBlock.getFacing` = `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`:
  /// the side away from the tank. The port stores that direction in `facing` for wall engines
  /// (`_steamEnginePlacement`), so no opposite is needed here.
  static Direction steamEngineFacing(BState engine) => switch (engine['face']) {
    'ceiling' => Direction.down,
    'floor' => Direction.up,
    _ => engine.dir('facing') ?? Direction.north,
  };

  /// `WhistleBlock.getAttachedDirection`.
  static Direction whistleAttachedDirection(BState whistle) =>
      whistle.flag('wall')
      ? (whistle.dir('facing') ?? Direction.north)
      : Direction.down;

  /// `checkPipeOrganAdvancement(controller)`: twelve different pitches.
  void checkPipeOrganAdvancement(BoilerHost controller) {
    final controllerPos = controller.controllerPos;
    final level = controller.fluidWorld;
    final whistlePitches = <int>{};
    for (var yOffset = 0; yOffset < controller.height; yOffset++) {
      for (var xOffset = 0; xOffset < controller.width; xOffset++) {
        for (var zOffset = 0; zOffset < controller.width; zOffset++) {
          final pos = controllerPos.offset(xOffset, yOffset, zOffset);
          final blockState = level.stateAt(pos);
          if (!PipeBlocks.isTank(blockState)) continue;
          for (final d in Direction.values) {
            final attachedPos = pos.relative(d);
            final attachedState = level.stateAt(attachedPos);
            if (attachedState.key == PipeKeys.steamWhistle &&
                whistleAttachedDirection(attachedState).opposite == d) {
              final pitch = controller.whistlePitchAt(attachedPos);
              if (pitch != null) whistlePitches.add(pitch);
            }
          }
        }
      }
    }
    if (whistlePitches.length >= 12) controller.award('pipe_organ');
  }

  /// `updateTemperature(controller)`: reads the burners below the boiler. Returns whether the
  /// heat changed.
  bool updateTemperature(BoilerHost controller) {
    final controllerPos = controller.controllerPos;
    final level = controller.fluidWorld;
    needsHeatLevelUpdate = false;
    final prevPassive = passiveHeat;
    final prevActive = activeHeat;
    passiveHeat = false;
    activeHeat = 0;

    for (var xOffset = 0; xOffset < controller.width; xOffset++) {
      for (var zOffset = 0; zOffset < controller.width; zOffset++) {
        final pos = controllerPos.offset(xOffset, -1, zOffset);
        final blockState = level.stateAt(pos);
        final heat = BoilerHeaters.findHeat(level, pos, blockState);
        if (heat == 0) {
          passiveHeat = true;
        } else if (heat > 0) {
          activeHeat += heat.toInt();
        }
      }
    }

    passiveHeat = passiveHeat && activeHeat == 0;
    return prevActive != activeHeat || prevPassive != passiveHeat;
  }

  /// `isActive()`.
  bool get isActive => attachedEngines > 0 || attachedWhistles > 0;

  /// `clear()`.
  void clear() {
    waterSupply = 0;
    activeHeat = 0;
    passiveHeat = false;
    attachedEngines = 0;
    for (var i = 0; i < supplyOverTime.length; i++) {
      supplyOverTime[i] = 0;
    }
  }

  /// `write()`: the compound under `Boiler`.
  Map<String, Object> write() => {
    'Supply': waterSupply,
    'ActiveHeat': activeHeat,
    'PassiveHeat': passiveHeat,
    'Engines': attachedEngines,
    'Whistles': attachedWhistles,
    'Update': needsHeatLevelUpdate,
  };

  /// `read(nbt, boilerSize)`.
  void read({
    required double supply,
    required int active,
    required bool passive,
    required int engines,
    required int whistles,
    required bool update,
  }) {
    waterSupply = supply;
    activeHeat = active;
    passiveHeat = passive;
    attachedEngines = engines;
    attachedWhistles = whistles;
    needsHeatLevelUpdate = update;
    for (var i = 0; i < supplyOverTime.length; i++) {
      supplyOverTime[i] = supply.truncateToDouble();
    }
  }

  /// `createHandler()`: accepts any amount of water (consumed as steam), never contains or
  /// provides anything.
  BoilerFluidHandler createHandler() => BoilerFluidHandler(this);
}

/// `BoilerData.BoilerFluidHandler`.
class BoilerFluidHandler implements FluidStorage {
  final BoilerData data;

  BoilerFluidHandler(this.data);

  @override
  int get tanks => 1;

  @override
  FStack fluidInTank(int tank) => FStack.empty;

  @override
  int tankCapacity(int tank) => 10000;

  @override
  bool isFluidValid(int tank, FStack stack) => FluidHelper.isWater(stack.fluid);

  @override
  int fill(FStack resource, {required bool simulate}) {
    if (resource.isEmpty || !FluidHelper.isWater(resource.fluid)) return 0;
    if (!simulate) data.gatheredSupply += resource.amount;
    return resource.amount;
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) => FStack.empty;

  @override
  FStack drain(int maxDrain, {required bool simulate}) => FStack.empty;
}

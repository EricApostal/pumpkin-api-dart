// `FluidTankBlockEntity`, `CreativeFluidTankBlockEntity` and the boiler a tank
// turns into (host side): the multiblock, the tank inventory, the boiler data
// and the `SteamEngineBoilerSource` the kinetics module consumes.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show HostBlockGetter;
import '../common/direction.dart';
import '../common/nbt_convert.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/nbt.dart' show NbtKind;
import '../kinetics/runtime.dart' show SteamEngineBoilerSource;
import 'boiler.dart';
import 'connectivity.dart';
import 'fluid_helper.dart';
import 'fluid_host.dart';
import 'fluid_runtime.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'fluid_world.dart';
import 'nbt_util.dart';
import 'pipe_block_entities.dart' show blockStateOf;
import 'pipe_blocks.dart';

/// The common direction axis of [KAxis]-free code: the multiblock only uses Y.
const Axis _mainAxis = Axis.y;

/// `FluidTankBlockEntity`.
class FluidTankBlockEntity extends CreateBlockEntity
    implements MultiPart, BoilerHost, FluidCapable {
  FluidTankBlockEntity(super.worldId, super.pos) {
    tank = createInventory();
  }

  /// `MAX_SIZE`.
  static const int maxSize = 3;

  /// `SYNC_RATE`.
  static const int syncRate = 8;

  late final SmartFluidTank tank;

  @override
  bool get isRemoved => removed;
  final BoilerData boiler = BoilerData();

  bool window = true;
  int luminosity = 0;
  bool forceFluidLevelUpdate = true;
  bool updateConnectivity = false;
  bool updateCapability = false;
  int syncCooldown = 0;
  bool queuedSync = false;

  Pos? lastKnownPos;
  Pos? _controller;
  int width = 1;
  int height = 1;

  /// `createInventory()`.
  SmartFluidTank createInventory() =>
      SmartFluidTank(capacityMultiplier, onFluidStackChanged);

  /// `getCapacityMultiplier()`: buckets per block, in millibuckets.
  static int get capacityMultiplier =>
      FluidsRuntime.instance.config.fluidTankCapacity * 1000;

  /// `getMaxHeight()`.
  static int get maxHeight => FluidsRuntime.instance.config.fluidTankMaxHeight;

  /// `getTotalTankSize()`.
  int get totalTankSize => width * width * height;

  /// `getFillState()`.
  double get fillState =>
      tank.capacity == 0 ? 0 : tank.fluidAmount / tank.capacity;

  bool get isCreative => false;

  // -- MultiPart ---------------------------------------------------------------------------

  @override
  String get partType => typeKey;

  @override
  Pos get partPos => (this.pos.x, this.pos.y, this.pos.z);

  @override
  Pos get controller => isController ? partPos : (_controller ?? partPos);

  @override
  MultiPart? get controllerPart {
    if (isController) return this;
    final c = _controller;
    if (c == null) return null;
    final be = store.at(worldId, BlockPos(x: c.$1, y: c.$2, z: c.$3));
    return be is FluidTankBlockEntity ? be : null;
  }

  @override
  bool get isController => _controller == null || _controller == partPos;

  @override
  void setController(Pos controller) {
    if (_controller == controller) return;
    _controller = controller;
    updateCapability = true;
    markDirty();
    sendData();
  }

  @override
  void removeController(bool keepContents) {
    updateConnectivity = true;
    if (!keepContents) applyFluidTankSize(1);
    _controller = null;
    width = 1;
    height = 1;
    boiler.clear();
    onFluidStackChanged(tank.fluid);
    final state = blockStateOf(this);
    if (PipeBlocks.isTank(state)) {
      setFluidBlock(
        world,
        partPos,
        state
            .setFlag('bottom', true)
            .setFlag('top', true)
            .setValue('shape', window ? 'window' : 'plain'),
        flags: {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate},
      );
    }
  }

  @override
  void preventConnectivityUpdate() => updateConnectivity = false;

  @override
  void notifyMultiUpdated() {
    final state = blockStateOf(this);
    if (PipeBlocks.isTank(state)) {
      setFluidBlock(
        world,
        partPos,
        state
            .setFlag('bottom', controller.y == this.pos.y)
            .setFlag('top', controller.y + height - 1 == this.pos.y),
        flags: {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate},
      );
    }
    if (isController) setWindows(window);
    onFluidStackChanged(tank.fluid);
    updateBoilerState();
  }

  @override
  Object? get extraData => window;

  @override
  set extraData(Object? data) {
    if (data is bool) window = data;
  }

  @override
  Object? modifyExtraData(Object? data) {
    if (data is bool) return data || window;
    return data;
  }

  @override
  Axis get mainConnectionAxis => _mainAxis;

  @override
  int getMaxLength(Axis longAxis, int width) =>
      longAxis == Axis.y ? maxHeight : maxSize;

  @override
  int get maxWidth => maxSize;

  @override
  bool get hasTank => true;

  @override
  int getTankSize(int tank) => capacityMultiplier;

  @override
  void setTankSize(int tank, int blocks) => applyFluidTankSize(blocks);

  @override
  FluidTank? getTank(int tank) => this.tank;

  @override
  FStack getFluid(int tank) => this.tank.fluid;

  // -- BoilerHost --------------------------------------------------------------------------

  @override
  FluidWorld get fluidWorld => FluidsRuntime.instance.levelOf(worldId)!;

  @override
  Pos get controllerPos => partPos;

  @override
  int get tankCapacity => tank.capacity;

  @override
  void notifyUpdate() => sendData();

  @override
  void award(String advancement) =>
      FluidsRuntime.instance.award(worldId, partPos, advancement);

  @override
  int? whistlePitchAt(Pos pos) => null;

  // -- Lifecycle ---------------------------------------------------------------------------

  @override
  void initialize() {
    super.initialize();
    sendData();
  }

  @override
  void tick() {
    super.tick();
    if (syncCooldown > 0) {
      syncCooldown--;
      if (syncCooldown == 0 && queuedSync) sendData();
    }

    if (lastKnownPos == null) {
      lastKnownPos = partPos;
    } else if (lastKnownPos != partPos) {
      lastKnownPos = partPos;
      removeController(true);
      return;
    }

    if (updateCapability) {
      updateCapability = false;
      // The handler is computed on demand; nothing is cached.
    }
    if (updateConnectivity) updateConnectivityNow();
    if (isController) boiler.tick(this);
  }

  /// `updateConnectivity()`.
  void updateConnectivityNow() {
    updateConnectivity = false;
    if (!isController) return;
    ConnectivityHandler.formMulti(TankMultiWorld(store, worldId), this);
  }

  @override
  void onRemoved() {
    super.onRemoved();
    ConnectivityHandler.splitMulti(TankMultiWorld(store, worldId), this);
  }

  /// `onFluidStackChanged(fluid)`.
  void onFluidStackChanged(FStack fluid) {
    luminosity = (FluidHelper.lightLevel(fluid) / 1.2).floor();
    sendData();
  }

  /// `applyFluidTankSize(blocks)`.
  void applyFluidTankSize(int blocks) {
    tank.capacity = blocks * capacityMultiplier;
    final overflow = tank.fluidAmount - tank.capacity;
    if (overflow > 0) tank.drain(overflow, simulate: false);
    forceFluidLevelUpdate = true;
  }

  /// `getControllerBE()`.
  FluidTankBlockEntity? get controllerBe {
    final part = controllerPart;
    return part is FluidTankBlockEntity ? part : null;
  }

  /// `toggleWindows()`.
  void toggleWindows() {
    final be = controllerBe;
    if (be == null) return;
    if (be.boiler.isActive) return;
    be.setWindows(!be.window);
  }

  /// `setWindows(window)`.
  void setWindows(bool window) {
    this.window = window;
    for (var yOffset = 0; yOffset < height; yOffset++) {
      for (var xOffset = 0; xOffset < width; xOffset++) {
        for (var zOffset = 0; zOffset < width; zOffset++) {
          final p = partPos.offset(xOffset, yOffset, zOffset);
          final state = blockStateAt(worldId, p);
          if (!PipeBlocks.isTank(state)) continue;
          var shape = 'plain';
          if (window) {
            if (width == 1) {
              shape = 'window';
            } else if (width == 2) {
              shape = xOffset == 0
                  ? (zOffset == 0 ? 'window_nw' : 'window_sw')
                  : (zOffset == 0 ? 'window_ne' : 'window_se');
            } else if (width == 3 &&
                ((xOffset.abs() - zOffset.abs()).abs() == 1)) {
              shape = 'window';
            }
          }
          setFluidBlock(
            world,
            p,
            state.setValue('shape', shape),
            flags: {
              BlockFlagsFlag.notifyListeners,
              BlockFlagsFlag.skipShapeUpdate,
            },
          );
        }
      }
    }
  }

  /// `updateBoilerState()`.
  void updateBoilerState() {
    if (!isController) return;
    final wasBoiler = boiler.isActive;
    final changed = boiler.evaluate(this);
    if (wasBoiler != boiler.isActive && boiler.isActive) setWindows(false);
    if (changed) {
      sendData();
      boiler.checkPipeOrganAdvancement(this);
    }
  }

  /// `updateBoilerTemperature()`.
  void updateBoilerTemperature() {
    final be = controllerBe;
    if (be == null) return;
    if (!be.boiler.isActive) return;
    be.boiler.needsHeatLevelUpdate = true;
  }

  /// The handler of this block entity (`Capabilities.Fluid.BLOCK`).
  @override
  FluidStorage? get fluidHandler {
    if (isController) return boiler.isActive ? boiler.createHandler() : tank;
    return controllerBe?.fluidHandler;
  }

  /// `getTankInventory()`.
  FluidStorage get tankInventory => tank;

  /// `sendDataImmediately()`.
  void sendDataImmediately() {
    syncCooldown = 0;
    queuedSync = false;
    sendData();
  }

  @override
  void sendData() {
    if (syncCooldown > 0) {
      queuedSync = true;
      return;
    }
    super.sendData();
    queuedSync = false;
    syncCooldown = syncRate;
  }

  // -- NBT ---------------------------------------------------------------------------------

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);

    updateConnectivity = tag.getBool('Uninitialized') ?? false;
    luminosity = tag.getInt('Luminosity') ?? 0;

    lastKnownPos = null;
    final last = tag.getIntArray('LastKnownPos');
    if (last != null && last.length >= 3)
      lastKnownPos = (last[0], last[1], last[2]);

    _controller = null;
    final c = tag.getIntArray('Controller');
    if (c != null && c.length >= 3) _controller = (c[0], c[1], c[2]);

    if (isController) {
      window = tag.getBool('Window') ?? false;
      width = tag.getInt('Size') ?? 0;
      height = tag.getInt('Height') ?? 0;
      tank.capacity = totalTankSize * capacityMultiplier;
      final content = tag.getCompound('TankContent');
      tank.rawSet(
        content == null
            ? FStack.empty
            : FluidNbt.read(valueOfCompound(content)),
      );
      final overflow = tank.fluidAmount - tank.capacity;
      if (overflow > 0) tank.drain(overflow, simulate: false);
    }

    final boilerTag = tag.getCompound('Boiler');
    if (boilerTag != null) {
      final nbt = valueOfCompound(boilerTag).asCompound;
      boiler.read(
        supply: nbt.readDouble('Supply') ?? 0,
        active: nbt.readInt('ActiveHeat') ?? 0,
        passive: nbt.readBool('PassiveHeat'),
        engines: nbt.readInt('Engines') ?? 0,
        whistles: nbt.readInt('Whistles') ?? 0,
        update: nbt.readBool('Update'),
      );
    }

    forceFluidLevelUpdate = tag.getBool('ForceFluidLevel') ?? true;
    updateCapability = true;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    if (updateConnectivity) tag.putBool('Uninitialized', true);
    final boilerTag = NbtCompound();
    final data = boiler.write();
    boilerTag
      ..putDouble('Supply', (data['Supply'] as num).toDouble())
      ..putInt('ActiveHeat', data['ActiveHeat'] as int)
      ..putBool('PassiveHeat', data['PassiveHeat'] as bool)
      ..putInt('Engines', data['Engines'] as int)
      ..putInt('Whistles', data['Whistles'] as int)
      ..putBool('Update', data['Update'] as bool);
    tag.putCompound('Boiler', boilerTag);

    final last = lastKnownPos;
    if (last != null)
      tag.putIntArray('LastKnownPos', [last.$1, last.$2, last.$3]);
    final c = _controller;
    if (!isController && c != null)
      tag.putIntArray('Controller', [c.$1, c.$2, c.$3]);
    if (isController) {
      tag
        ..putBool('Window', window)
        ..putInt('Size', width)
        ..putInt('Height', height);
      final fluid = FluidNbt.write(tank.fluid);
      if (fluid.kind == NbtKind.compound)
        tag.putCompound('TankContent', compoundOf(fluid));
    }
    tag.putInt('Luminosity', luminosity);

    super.write(tag, clientPacket: clientPacket);

    if (!clientPacket) return;
    if (forceFluidLevelUpdate) tag.putBool('ForceFluidLevel', true);
    if (queuedSync) tag.putBool('LazySync', true);
    forceFluidLevelUpdate = false;
  }
}

/// `CreativeFluidTankBlockEntity`.
class CreativeFluidTankBlockEntity extends FluidTankBlockEntity {
  CreativeFluidTankBlockEntity(super.worldId, super.pos);

  @override
  SmartFluidTank createInventory() => CreativeSmartFluidTank(
    FluidTankBlockEntity.capacityMultiplier,
    onFluidStackChanged,
  );

  @override
  bool get isCreative => true;

  /// `setContainedFluid`.
  void setContainedFluid(FStack fluid) =>
      (tank as CreativeSmartFluidTank).setContainedFluid(fluid);
}

/// The [MultiPartWorld] of the tank multiblock over the block entity store.
final class TankMultiWorld implements MultiPartWorld {
  final BlockEntityStore store;
  final String worldId;

  const TankMultiWorld(this.store, this.worldId);

  @override
  MultiPart? partAt(String type, Pos pos) {
    final be = store.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
    if (be is! FluidTankBlockEntity) return null;
    final part = be;
    if (part.partType != type || part.removed) return null;
    return part;
  }

  @override
  MultiPart? anyPartAt(Pos pos) {
    final be = store.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
    return be is FluidTankBlockEntity ? be : null;
  }

  @override
  void invalidateCapabilities(Pos pos) {
    // The tank handler is computed on demand from the controller.
  }
}

/// `SteamEngineBoilerSource`: the efficiency of the boiler behind a steam engine.
final class TankBoilerSource implements SteamEngineBoilerSource {
  final BlockEntityStore store;

  const TankBoilerSource(this.store);

  @override
  double? engineEfficiency(String worldId, int x, int y, int z) {
    final be = store.at(worldId, BlockPos(x: x, y: y, z: z));
    if (be is! FluidTankBlockEntity) return null;
    final controller = be.controllerBe;
    if (controller == null) return null;
    return controller.boiler.getEngineEfficiency(controller.totalTankSize);
  }
}

/// The block state of the tank at [p] (`world.getBlockState`).
BState blockStateAt(String worldId, Pos p) {
  final world = FluidsRuntime.instance.worlds.byId(worldId);
  if (world == null) return BState.air;
  return HostBlockGetter.stateOfId(
    world.getBlockStateId(
      pos: BlockPos(x: p.$1, y: p.$2, z: p.$3),
    ),
  );
}

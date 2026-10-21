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
import '../decoration/block_entities.dart' show WhistleBlockEntity;
import '../equipment/host/env.dart';
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

  /// `fluidCapability`: the handler the pipe network sees, cached like Java's field.
  FluidStorage? _capability;

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
    _capability = null;
    updateCapability = true;
    markDirty();
    sendData();
  }

  /// The writes of this block's own state, in the order they were issued.
  ///
  /// A member's state is written several times inside one form: the split first gives it a lone
  /// tank's `bottom`/`top` (`removeController`), then the merge gives it the boundary of its
  /// place in the multiblock (`notifyMultiUpdated`, `setWindows`). Java writes synchronously, so
  /// the last write is the one that stays; here a block write is an asynchronous host call
  /// (`setFluidBlock`, one `spawn_blocking` per call) and two writes issued in the same form can
  /// reach the server in either order - a member that keeps the lone tank state is what makes an
  /// 8 tall tank render as several short ones. Chaining the writes keeps Java's order.
  Future<void> _pendingStateWrites = Future<void>.value();

  /// Writes the state of one member of the multiblock, queued after the previous one.
  void _writeState(Pos p, BState state) {
    final w = world;
    if (w == null) return;
    final id = BlockRegistry.resolveState(state.key, state.props);
    if (id == null) return;
    _pendingStateWrites = _pendingStateWrites
        .then(
          (_) => w.setBlockState(
            pos: BlockPos(x: p.$1, y: p.$2, z: p.$3),
            state: id,
            updateFlags: {
              BlockFlagsFlag.notifyListeners,
              BlockFlagsFlag.skipShapeUpdate,
            },
          ),
        )
        .catchError((Object e, StackTrace s) {});
  }

  @override
  void removeController(bool keepContents) {
    updateConnectivity = true;
    if (!keepContents) applyFluidTankSize(1);
    _controller = null;
    _capability = null;
    width = 1;
    height = 1;
    boiler.clear();
    onFluidStackChanged(tank.fluid);
    markDirty();
    final state = blockStateOf(this);
    if (PipeBlocks.isTank(state)) {
      _writeState(
        partPos,
        state
            .setFlag('bottom', true)
            .setFlag('top', true)
            .setValue('shape', window ? 'window' : 'plain'),
      );
    }
  }

  @override
  void preventConnectivityUpdate() => updateConnectivity = false;

  @override
  void notifyMultiUpdated() {
    _capability = null;
    final state = _memberState(0, 0, 0);
    if (state != null) _writeState(partPos, state);
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
  int? whistlePitchAt(Pos pos) {
    final be = store.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
    if (be is! WhistleBlockEntity) return null;
    final size = blockStateAt(worldId, pos)['size'];
    return size == null ? null : be.pitchId(size);
  }

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
      _capability = null;
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

  /// `onFluidStackChanged(fluid)`: distributes the light over the tank blocks, brightest where
  /// the fluid is (the other way round for fluids lighter than air).
  void onFluidStackChanged(FStack fluid) {
    final level = (FluidHelper.lightLevel(fluid) / 1.2).floor();
    final reversed = FluidHelper.isLighterThanAir(fluid);
    final maxY = (fillState * height + 1).floor();

    for (var yOffset = 0; yOffset < height; yOffset++) {
      final isBright = reversed ? height - yOffset <= maxY : yOffset < maxY;
      final actualLuminosity = isBright ? level : (level > 0 ? 1 : 0);
      for (var xOffset = 0; xOffset < width; xOffset++) {
        for (var zOffset = 0; zOffset < width; zOffset++) {
          final p = partPos.offset(xOffset, yOffset, zOffset);
          final be = store.at(worldId, BlockPos(x: p.$1, y: p.$2, z: p.$3));
          if (be is! FluidTankBlockEntity) continue;
          // `level.updateNeighbourForOutputSignal(pos, ...)`: the fill state is the comparator
          // output, so the comparators read the tank again.
          final w = world;
          if (w != null) w.updateComparators(pos: p.blockPos);
          be.setLuminosity(actualLuminosity);
        }
      }
    }

    sendData();
  }

  /// `setLuminosity(luminosity)`.
  void setLuminosity(int luminosity) {
    if (this.luminosity == luminosity) return;
    this.luminosity = luminosity;
    _applyLight();
    sendData();
  }

  /// `FluidTankBlock.getLightEmission`: a tank only lights the area while its windows show the
  /// fluid, and only as bright as the fluid in that part of the multiblock.
  void _applyLight() {
    final w = world;
    if (w == null) return;
    final be = controllerBe;
    final lit = be != null && be.window;
    w.setBlockLight(
      pos: BlockPos(x: partPos.$1, y: partPos.$2, z: partPos.$3),
      level: lit ? luminosity.clamp(0, 15) : 0,
    );
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
          final state = _memberState(xOffset, yOffset, zOffset);
          if (state == null) continue;
          _writeState(p, state);
        }
      }
    }
    // The windows decide whether the tank emits light at all.
    _applyLight();
  }

  /// The whole state of the member at the offset (`0,0,0` is this block): the `bottom`/`top`
  /// boundaries of Java's `notifyMultiUpdated` *and* the `shape` of Java's `setWindows`.
  ///
  /// Both are written by two different passes of the same form, and here a block write is an
  /// asynchronous host call (`setFluidBlock`), so each pass used to write a state it had read
  /// from the world before the other pass landed: the boundary write carried the old `shape`,
  /// the window write carried the old `bottom`/`top`, and whichever reached the server last won.
  /// That is a tank whose members keep a lone tank's or a shorter tank's boundaries - an 8 tall
  /// tank rendering as two short ones, and only some of them. Java cannot lose that race because
  /// its writes are synchronous, so the port writes the *complete* member state from both passes
  /// instead: the two writes are then identical and the result does not depend on their order.
  BState? _memberState(int xOffset, int yOffset, int zOffset) {
    final p = partPos.offset(xOffset, yOffset, zOffset);
    final state = blockStateAt(worldId, p);
    if (!PipeBlocks.isTank(state)) return null;

    var shape = 'plain';
    if (window) {
      if (width == 1) {
        shape = 'window';
      } else if (width == 2) {
        shape = xOffset == 0
            ? (zOffset == 0 ? 'window_nw' : 'window_sw')
            : (zOffset == 0 ? 'window_ne' : 'window_se');
      } else if (width == 3 && ((xOffset.abs() - zOffset.abs()).abs() == 1)) {
        shape = 'window';
      }
    }

    return state
        .setFlag('bottom', controller.y == p.y)
        .setFlag('top', controller.y + height - 1 == p.y)
        .setValue('shape', shape);
  }

  /// `updateBoilerState()`.
  void updateBoilerState() {
    if (!isController) return;
    final wasBoiler = boiler.isActive;
    final changed = boiler.evaluate(this);
    if (wasBoiler != boiler.isActive) {
      // The handler changes between the tank and the boiler.
      _capability = null;
      if (boiler.isActive) setWindows(false);
    }
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

  /// The handler of this block entity (`Capabilities.Fluid.BLOCK`). The controller caches its
  /// handler like Java's `fluidCapability`; a part always delegates to the controller.
  @override
  FluidStorage? get fluidHandler {
    if (!isController) {
      return controllerBe?.fluidHandler ?? const EmptyFluidStorage();
    }
    return _capability ??= boiler.isActive ? boiler.createHandler() : tank;
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
      // `CreateFluidTank.readFromNBT`: the stack is nested under `Fluid`.
      tank.rawSet(
        content == null
            ? FStack.empty
            : readFluidTankNbt(valueOfCompound(content)),
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
    _capability = null;
    // `level.getChunkSource().getLightEngine().checkBlock(worldPosition)` when the saved
    // luminosity differs from the one in the light engine.
    _applyLight();
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
      // `CreateFluidTank.writeToNBT`: the stack is nested under `Fluid`.
      tag.putCompound('TankContent', compoundOf(fluidTankNbt(tank.fluid)));
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

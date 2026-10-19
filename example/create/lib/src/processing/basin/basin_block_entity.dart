// `BasinBlockEntity`: the basin's item and fluid storage, the recipe filter, the spout that
// moves outputs to the side, and the heat it reads from the block below. The recipe matching
// itself is in `basin_recipe_ops.dart`; the machines that drive it are the basin operators
// (`basin_operating_block_entity.dart`).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../../core/block_entity.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/heat.dart';
import '../transport/transport_behaviours.dart';
import 'basin_block.dart';
import 'basin_operating_block_entity.dart';
import 'basin_recipe_ops.dart';

/// `BasinInventory`: one stack per item type, and the first empty slot only (prevents
/// overfilling in the simulated pass of the recipe matching).
final class BasinInventory extends SmartInventory {
  /// `packagerMode`: plain insertion, one stack per slot (packagers put unique stacks in).
  bool packagerMode = false;

  BasinInventory(
    int size, {
    int stackSize = 64,
    void Function(int slot)? onChanged,
  }) : super(size, stackSize: stackSize, onChanged: onChanged);

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) {
    if (stack.isEmpty || packagerMode)
      return super.insert(slot, stack, simulate: simulate);
    var firstFree = -1;
    for (var i = 0; i < slots; i++) {
      if (i != slot &&
          stackIn(i).isNotEmpty &&
          stackIn(i).sameItemSameComponents(stack))
        return stack;
      if (stackIn(i).isEmpty && firstFree < 0) firstFree = i;
    }
    if (stackIn(slot).isEmpty && firstFree != slot) return stack;
    return super.insert(slot, stack, simulate: simulate);
  }
}

/// `BasinBlockEntity`.
class BasinBlockEntity extends CreateBlockEntity
    implements ItemStorageProvider, FluidStorageProvider, BasinRecipeHost {
  static const String type = 'create:basin';

  /// `SmartFluidTankBehaviour(INPUT/OUTPUT, this, 2, 1000, true)`.
  static const int tankCapacity = 1000;

  /// `OUTPUT_ANIMATION_TIME` (client only; kept for the client data).
  static const int outputAnimationTime = 10;

  late final BasinInventory inputInventory;
  late final BasinInventory outputInventory;
  late final SmartFluidTank inputTankA;
  late final SmartFluidTank inputTankB;
  late final SmartFluidTank outputTankA;
  late final SmartFluidTank outputTankB;
  late final CombinedStorage _items;
  late final CombinedFluidStorage _fluids;
  late final DirectBeltInputBehaviour directBeltInput;

  /// `FilteringBehaviour` (`forRecipes`): the item (or bucket) a result must match.
  PStack filter = PStack.empty;

  bool contentsChanged = true;
  HeatLevel? _cachedHeatLevel;

  /// `spoutputBuffer` / `spoutputFluidBuffer`: outputs waiting for the spout target.
  final List<PStack> spoutputBuffer = [];
  final List<PFluid> spoutputFluidBuffer = [];
  Direction? preferredSpoutput;
  final Set<Direction> disabledSpoutputs = {};

  int _recipeBackupCheck = 20;
  bool _clearingSpoutput = false;

  BasinBlockEntity(super.worldId, super.pos) {
    inputInventory = BasinInventory(9, onChanged: _onSlotChanged);
    outputInventory = BasinInventory(9, onChanged: _onSlotChanged)
      ..insertionAllowed = false;
    inputTankA = SmartFluidTank(tankCapacity, onChanged: _onTankChanged);
    inputTankB = SmartFluidTank(tankCapacity, onChanged: _onTankChanged);
    outputTankA = SmartFluidTank(tankCapacity, onChanged: _onTankChanged)
      ..fillAllowed = false;
    outputTankB = SmartFluidTank(tankCapacity, onChanged: _onTankChanged)
      ..fillAllowed = false;
    _items = CombinedStorage([inputInventory, outputInventory]);
    _fluids = CombinedFluidStorage([
      outputTankA,
      outputTankB,
      inputTankA,
      inputTankB,
    ]);
    directBeltInput = addBehaviour(DirectBeltInputBehaviour())
      ..defaultInsertion = (transported, side, simulate) =>
          insertInput(transported.stack, simulate: simulate);
  }

  ProcessingRuntime get _rt => ProcessingRuntime.instance;

  /// The position as a [Pos] record.
  Pos get _p => pos.toPos();

  void _onSlotChanged(int slot) => contentsChanged = true;

  void _onTankChanged() => contentsChanged = true;

  // -- Capabilities ----------------------------------------------------------------------

  @override
  ItemStorage? itemStorage(String? side) => _items;

  @override
  FluidStorage? fluidStorage(String? side) => _fluids;

  @override
  ItemStorage get recipeItems => _items;

  @override
  List<FluidStorage> get recipeFluidTanks => [
    outputTankA,
    outputTankB,
    inputTankA,
    inputTankB,
  ];

  /// `insert(inputInventory)`: the belt / funnel insertion.
  PStack insertInput(PStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return PStack.empty;
    final rest = ItemStorages.insertStacked(
      inputInventory,
      stack,
      simulate: simulate,
    );
    if (!simulate && rest.count != stack.count) sendData();
    return rest;
  }

  // -- Contents --------------------------------------------------------------------------

  SmartInventory get input => inputInventory;
  SmartInventory get output => outputInventory;

  bool get isEmpty =>
      ItemStorages.isEmpty(inputInventory) &&
      ItemStorages.isEmpty(outputInventory) &&
      inputTankA.isEmpty &&
      inputTankB.isEmpty &&
      outputTankA.isEmpty &&
      outputTankB.isEmpty;

  /// `canContinueProcessing`: nothing waits for the spout.
  bool get canContinueProcessing =>
      spoutputBuffer.isEmpty && spoutputFluidBuffer.isEmpty;

  void notifyChangeOfContents() => contentsChanged = true;

  /// The heat of the block below (`getHeatLevelOf`).
  @override
  HeatLevel get heatLevel {
    final cached = _cachedHeatLevel;
    if (cached != null) return cached;
    final w = world;
    if (w == null) return HeatLevel.none;
    final state = HostBlockGetter(w).stateAt(_p.below);
    return _cachedHeatLevel = BasinBlock.heatLevelOf(state, _rt.tags);
  }

  @override
  bool filterAccepts(PStack stack) {
    if (filter.isEmpty) return true;
    return stack.isNotEmpty && filter.sameItemSameComponents(stack);
  }

  @override
  bool filterAcceptsFluid(PFluid fluid) {
    if (filter.isEmpty) return true;
    if (fluid.isEmpty) return false;
    // A fluid filter is the fluid's bucket (`minecraft:water_bucket`, `create:chocolate_bucket`).
    return filter.key == fluid.key || filter.key == '${fluid.key}_bucket';
  }

  // -- Outputs ---------------------------------------------------------------------------

  /// `acceptOutputs(outputItems, outputFluids, simulate)`.
  @override
  bool acceptOutputs(
    List<PStack> outputItems,
    List<PFluid> outputFluids, {
    required bool simulate,
  }) {
    outputInventory.insertionAllowed = true;
    outputTankA.fillAllowed = true;
    outputTankB.fillAllowed = true;
    try {
      return _acceptOutputsInner(outputItems, outputFluids, simulate);
    } finally {
      outputInventory.insertionAllowed = false;
      outputTankA.fillAllowed = false;
      outputTankB.fillAllowed = false;
    }
  }

  bool _acceptOutputsInner(
    List<PStack> outputItems,
    List<PFluid> outputFluids,
    bool simulate,
  ) {
    final w = world;
    if (w == null) return false;
    final direction = facingDirection;

    if (direction != Direction.down) {
      // The spout points sideways: outputs go to the block below the neighbour in that direction.
      final targetPos = _p.below.relative(direction);
      final side = direction.opposite.name;
      final target = store.at(worldId, targetPos.toBlockPos());
      final pluginItems = target is ItemStorageProvider
          ? (target as ItemStorageProvider).itemStorage(side)
          : null;
      final hasItemTarget =
          pluginItems != null ||
          _rt.storage.hasItemStorage(
            w,
            worldId,
            targetPos.toBlockPos(),
            side: side,
          );
      final pluginFluids = target is FluidStorageProvider
          ? (target as FluidStorageProvider).fluidStorage(side)
          : null;
      final hostFluids = FluidHandlers.at(
        w,
        targetPos.toBlockPos(),
        side: direction.opposite.toHost(),
      );
      final externalTankNotPresent = pluginFluids == null && hostFluids == null;

      if (outputItems.isNotEmpty && !hasItemTarget) return false;
      if (outputFluids.isNotEmpty && externalTankNotPresent) {
        // Fluid outputs but the spout only accepts items: keep them in the basin's output tanks.
        if (!_acceptFluidOutputsIntoBasin(outputFluids, simulate)) return false;
      }
      if (simulate) return true;
      for (final stack in outputItems) {
        if (stack.isNotEmpty) spoutputBuffer.add(stack);
      }
      if (!externalTankNotPresent) {
        for (final fluid in outputFluids) {
          spoutputFluidBuffer.add(fluid);
        }
      }
      return true;
    }

    if (!_acceptItemOutputsIntoBasin(outputItems, simulate)) return false;
    if (outputFluids.isEmpty) return true;
    return _acceptFluidOutputsIntoBasin(outputFluids, simulate);
  }

  bool _acceptItemOutputsIntoBasin(List<PStack> outputItems, bool simulate) {
    for (final stack in outputItems) {
      if (stack.isEmpty) continue;
      if (ItemStorages.insertStacked(
        outputInventory,
        stack,
        simulate: simulate,
      ).isNotEmpty)
        return false;
    }
    return true;
  }

  bool _acceptFluidOutputsIntoBasin(List<PFluid> outputFluids, bool simulate) {
    final out = CombinedFluidStorage([outputTankA, outputTankB]);
    for (final fluid in outputFluids) {
      if (out.fill(fluid, simulate: simulate) != fluid.amount) return false;
    }
    return true;
  }

  /// The `facing` of the block state (`FACING_HOPPER`, `down` when outputs stay inside).
  Direction get facingDirection {
    final w = world;
    if (w == null) return Direction.down;
    final state = HostBlockGetter(w).stateAt(_p);
    return state.dir(BasinBlock.facingProperty) ?? Direction.down;
  }

  // -- Spout -------------------------------------------------------------------------

  /// `onWrenched(face)`: cycle the spout facing.
  void onWrenched(Direction face) {
    final w = world;
    if (w == null) return;
    final state = HostBlockGetter(w).stateAt(_p);
    final current = state.dir(BasinBlock.facingProperty) ?? Direction.down;

    disabledSpoutputs.remove(face);
    if (current == face) {
      if (preferredSpoutput == face) preferredSpoutput = null;
      disabledSpoutputs.add(face);
    } else {
      preferredSpoutput = face;
    }
    updateSpoutput();
  }

  /// `updateSpoutput`: point the spout at the first side that accepts outputs.
  void updateSpoutput() {
    final w = world;
    if (w == null) return;
    final state = HostBlockGetter(w).stateAt(_p);
    if (state.key != BasinBlock.key) return;
    final current = state.dir(BasinBlock.facingProperty) ?? Direction.down;

    var next = Direction.down;
    for (final test in Direction.planeHorizontal) {
      if (BasinBlock.canOutputTo(w, worldId, _p, test) &&
          !disabledSpoutputs.contains(test))
        next = test;
    }
    final preferred = preferredSpoutput;
    if (preferred != null &&
        preferred != Direction.up &&
        BasinBlock.canOutputTo(w, worldId, _p, preferred)) {
      next = preferred;
    }
    if (next == current) return;

    unawaited(
      setBlockState(
        w,
        _p,
        state.setDir(BasinBlock.facingProperty, next),
      ).then((_) => _afterSpoutputChange(next)),
    );
  }

  Future<void> _afterSpoutputChange(Direction newFacing) async {
    if (newFacing.axis.isVertical) return;

    for (var slot = 0; slot < outputInventory.slots; slot++) {
      final peek = outputInventory.extract(slot, 64, simulate: true);
      if (peek.isEmpty) continue;
      if (!acceptOutputs([peek], const [], simulate: true)) continue;
      acceptOutputs(
        [outputInventory.extract(slot, 64)],
        const [],
        simulate: false,
      );
    }

    final tanks = CombinedFluidStorage([outputTankA, outputTankB]);
    for (var tank = 0; tank < tanks.tanks; tank++) {
      final fluid = tanks.fluidIn(tank);
      if (fluid.isEmpty) continue;
      if (!acceptOutputs(const [], [fluid], simulate: true)) continue;
      tanks.drainFluid(fluid);
      acceptOutputs(const [], [fluid], simulate: false);
    }

    notifyChangeOfContents();
    sendData();
  }

  /// `tryClearingSpoutputOverflow`: push the buffered outputs to the spout target.
  Future<void> _clearSpoutputOverflow() async {
    if (_clearingSpoutput) return;
    final w = world;
    if (w == null) return;
    final state = HostBlockGetter(w).stateAt(_p);
    if (state.key != BasinBlock.key) return;
    final direction = state.dir(BasinBlock.facingProperty) ?? Direction.down;
    final targetPos = _p.below.relative(direction);

    _clearingSpoutput = true;
    try {
      var update = false;
      for (var i = 0; i < spoutputBuffer.length;) {
        final stack = spoutputBuffer[i];
        if (direction == Direction.down) {
          final host = await HostStacks.write(stack);
          if (host != null) await w.dropItem(_p.center, host);
          spoutputBuffer.removeAt(i);
          update = true;
          continue;
        }
        final remainder = await _insertInto(w, targetPos, direction, stack);
        if (remainder.count == stack.count) {
          i++;
          continue;
        }
        if (remainder.isEmpty) {
          spoutputBuffer.removeAt(i);
        } else {
          spoutputBuffer[i] = remainder;
          i++;
        }
        update = true;
      }

      for (var i = 0; i < spoutputFluidBuffer.length;) {
        final fluid = spoutputFluidBuffer[i];
        if (direction == Direction.down) {
          spoutputFluidBuffer.removeAt(i);
          update = true;
          continue;
        }
        if (!await _fillInto(w, targetPos, direction, fluid)) {
          i++;
          continue;
        }
        spoutputFluidBuffer.removeAt(i);
        update = true;
      }

      if (update) {
        notifyChangeOfContents();
        sendData();
      }
    } finally {
      _clearingSpoutput = false;
    }
  }

  Future<PStack> _insertInto(
    World w,
    Pos targetPos,
    Direction direction,
    PStack stack,
  ) async {
    final side = direction.opposite.name;
    final target = store.at(worldId, targetPos.toBlockPos());
    if (target is ItemStorageProvider) {
      final inv = (target as ItemStorageProvider).itemStorage(side);
      if (inv != null) return ItemStorages.insertStacked(inv, stack);
    }
    return _rt.storage.hostInsert(w, targetPos.toBlockPos(), stack, side: side);
  }

  Future<bool> _fillInto(
    World w,
    Pos targetPos,
    Direction direction,
    PFluid fluid,
  ) async {
    final side = direction.opposite.name;
    final target = store.at(worldId, targetPos.toBlockPos());
    if (target is FluidStorageProvider) {
      final tank = (target as FluidStorageProvider).fluidStorage(side);
      if (tank != null) {
        if (tank.fill(fluid, simulate: true) != fluid.amount) return false;
        tank.fill(fluid);
        return true;
      }
    }
    final host = FluidHandlers.at(
      w,
      targetPos.toBlockPos(),
      side: direction.opposite.toHost(),
    );
    if (host == null) return false;
    final stack = FluidStack(
      fluid: fluid.key,
      amount: fluid.amount,
      data: null,
    );
    if (host.fill(stack: stack, simulate: true) != fluid.amount) return false;
    host.fill(stack: stack, simulate: false);
    return true;
  }

  // -- Lifecycle ------------------------------------------------------------------------

  /// `remove()` / `destroy()`: tell the operator and drop the contents.
  @override
  void onRemoved() {
    super.onRemoved();
    onEmptied();
    final w = world;
    if (w != null) {
      for (final stack in [
        ...inputInventory.contents,
        ...outputInventory.contents,
        ...spoutputBuffer,
      ]) {
        if (stack.isEmpty) continue;
        unawaited(_drop(w, stack));
      }
    }
    spoutputBuffer.clear();
    spoutputFluidBuffer.clear();
  }

  Future<void> _drop(World w, PStack stack) async {
    final host = await HostStacks.write(stack);
    if (host != null) await w.dropItem(_p.center, host);
  }

  /// `onEmptied`: the operator stops its current processing run.
  void onEmptied() => _operator?.basinRemoved = true;

  BasinOperatingBlockEntity? get _operator => store
      .typed<BasinOperatingBlockEntity>(worldId, _p.aboveBy(2).toBlockPos());

  @override
  void tick() {
    _cachedHeatLevel = null;
    super.tick();

    if (spoutputBuffer.isNotEmpty || spoutputFluidBuffer.isNotEmpty)
      unawaited(_clearSpoutputOverflow());
    if (!contentsChanged) return;

    contentsChanged = false;
    _operator?.scheduleBasinCheck();

    // Basins in a row notify each other when their facing points at the neighbour.
    final w = world;
    if (w == null) return;
    final getter = HostBlockGetter(w);
    for (final offset in Direction.planeHorizontal) {
      final p = _p.above.relative(offset);
      final state = getter.stateAt(p);
      if (state.key != BasinBlock.key ||
          state.dir(BasinBlock.facingProperty) != offset.opposite)
        continue;
      final be = store.at(worldId, p.toBlockPos());
      if (be is BasinBlockEntity) be.contentsChanged = true;
    }
  }

  @override
  void lazyTick() {
    super.lazyTick();
    updateSpoutput();
    if (_recipeBackupCheck-- > 0) return;
    _recipeBackupCheck = 20;
    if (isEmpty) return;
    notifyChangeOfContents();
  }

  // -- NBT -------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putCompound('InputItems', StackNbt.writeList(inputInventory.contents));
    tag.putCompound(
      'OutputItems',
      StackNbt.writeList(outputInventory.contents),
    );
    final preferred = preferredSpoutput;
    if (preferred != null) tag.putString('PreferredSpoutput', preferred.name);
    tag.putString(
      'DisabledSpoutput',
      [for (final d in disabledSpoutputs) d.name].join(','),
    );
    tag.putList('Overflow', [
      for (final stack in spoutputBuffer) StackNbt.write(stack),
    ]);
    tag.putList('FluidOverflow', [
      for (final fluid in spoutputFluidBuffer) StackNbt.writeFluid(fluid),
    ]);
    if (filter.isNotEmpty) tag.putCompound('Filter', StackNbt.write(filter));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    inputInventory.load(
      StackNbt.readList(tag.getCompound('InputItems'), inputInventory.slots),
    );
    outputInventory.load(
      StackNbt.readList(tag.getCompound('OutputItems'), outputInventory.slots),
    );

    final preferred = tag.getString('PreferredSpoutput');
    preferredSpoutput = preferred == null ? null : Direction.byName(preferred);
    disabledSpoutputs.clear();
    for (final name in (tag.getString('DisabledSpoutput') ?? '').split(',')) {
      if (name.isEmpty) continue;
      final direction = Direction.byName(name);
      if (direction != null) disabledSpoutputs.add(direction);
    }
    spoutputBuffer
      ..clear()
      ..addAll([
        for (final element in tag.getList('Overflow') ?? const <Object>[])
          if (element is NbtCompound) StackNbt.read(element),
      ]);
    spoutputFluidBuffer
      ..clear()
      ..addAll([
        for (final element in tag.getList('FluidOverflow') ?? const <Object>[])
          if (element is NbtCompound) StackNbt.readFluid(element),
      ]);
    filter = StackNbt.read(tag.getCompound('Filter'));
    contentsChanged = true;
  }
}

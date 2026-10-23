// `MechanicalCrafterBlockEntity`: the mechanical crafter. One item slot per crafter, connected
// crafters forming one crafting grid; the grid assembles through Create's
// `mechanical_crafting` recipes (or, when the config allows it, vanilla crafting recipes) and
// sends the result towards the crafter it points at.
//
// Ported from `content/kinetics/crafter/MechanicalCrafterBlockEntity.java`,
// `ConnectedInputHandler.java` and `RecipeGridHandler.java`. Crafting remainders of the grid
// items are not available to plugins, so they are not returned (documented deviation).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../api/block_state.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import '../transport/transport_behaviours.dart';
import 'crafter_model.dart';
import 'crafter_recipe.dart';
import 'machine_support.dart';

/// `MechanicalCrafterBlockEntity`.
final class MechanicalCrafterBlockEntity extends KineticBlockEntity
    implements CrafterNode, ItemStorageProvider {
  MechanicalCrafterBlockEntity(super.worldId, super.pos) {
    advancements = addBehaviour(
      AdvancementBehaviour(
        [AllAdvancements.crafter, AllAdvancements.crafterLazy],
        () => ProcessingRuntime.instance.advancements,
      ),
    );
    inventory = SmartInventory(1)
      ..extractionAllowed = false
      ..validator = _mayInsert
      ..onChanged = _onInventoryChanged;
    lazyTickRate = 20;
  }

  /// `registerAwardables(behaviours, CRAFTER, CRAFTER_LAZY)`
  /// (`MechanicalCrafterBlockEntity.java:151`): the crafter awards its owner.
  late final AdvancementBehaviour advancements;

  /// `onSpeedChanged` (`MechanicalCrafterBlockEntity.java:155-161`): a running crafter awards
  /// `CRAFTER`, and a slow one (`|speed| < 5`) also `CRAFTER_LAZY`.
  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    if (speed == 0) return;
    unawaited(advancements.awardPlayer(AllAdvancements.crafter));
    if (speed.abs() < 5) {
      unawaited(advancements.awardPlayer(AllAdvancements.crafterLazy));
    }
  }

  /// `inventory`: the single crafting slot (extraction is refused, as in `Inventory`).
  late final SmartInventory inventory;

  /// `groupedItems`: the grid this crafter holds while a craft runs.
  GroupedItems groupedItems = GroupedItems();

  /// `input`: the crafters sharing this one's input.
  @override
  ConnectedInput input = ConnectedInput();

  /// `phase`.
  @override
  CrafterPhase phase = CrafterPhase.idle;

  /// `countDown`.
  int countDown = 0;

  /// `covered`: a crafter slot cover hides the slot.
  bool covered = false;

  /// `wasPoweredBefore` (not saved; initialised to `true` like Java).
  bool wasPoweredBefore = true;

  /// The combined item handler of the connected crafters (`getInvCapability`).
  ItemStorage? _invCap;

  /// Async host work (`tryInsert`, crafting, ejection) must not overlap.
  bool _busy = false;
  bool _pollingPower = false;

  ProcessingRuntime get _rt => ProcessingRuntime.instance;

  /// The crafter world view used by the pure chain logic.
  late final _StoreCrafterWorld _crafterWorld = _StoreCrafterWorld(this);

  // -- CrafterNode ----------------------------------------------------------------------------

  @override
  Pos get crafterPos => pos.toPos();

  @override
  BState get crafterState => bStateOf(blockState);

  @override
  bool get hasCraftingItem => inventory.stackIn(0).isNotEmpty;

  @override
  bool get hasCraftingItemOrCover => hasCraftingItem || covered;

  @override
  void begin() {
    phase = CrafterPhase.accepting;
    groupedItems = GroupedItems.single(inventory.stackIn(0));
    inventory.setStack(0, PStack.empty);
    if (precedingCrafters(_crafterWorld, this).isEmpty) {
      phase = CrafterPhase.assembling;
      countDown = 1;
    }
    sendData();
  }

  @override
  void continueIfAllPrecedingFinished() {
    final preceding = precedingCrafters(_crafterWorld, this);
    for (final be in preceding) {
      if (be.phase != CrafterPhase.waiting) return;
    }
    phase = CrafterPhase.assembling;
    countDown = 1;
  }

  @override
  void eject() {
    final state = blockState;
    final facing = state.dirOf('facing') ?? Dir.south;
    final ejectPos = (
      pos.x + .5 + facing.dx * .75,
      pos.y + .5 + facing.dy * .75,
      pos.z + .5 + facing.dz * .75,
    );
    for (final stack in groupedItems.grid.values) {
      _dropItem(ejectPos, stack);
    }
    final slot = inventory.stackIn(0);
    if (slot.isNotEmpty) _dropItem(ejectPos, slot);
    phase = CrafterPhase.idle;
    groupedItems = GroupedItems();
    inventory.setStack(0, PStack.empty);
    sendData();
  }

  // -- Capabilities ---------------------------------------------------------------------------

  @override
  ItemStorage? itemStorage(String? side) {
    if (!input.isController) {
      final controllerPos = pos.toPos() + input.data.first;
      final controller = store.typed<MechanicalCrafterBlockEntity>(
        worldId,
        controllerPos.toBlockPos(),
      );
      if (controller == null ||
          identical(controller, this) ||
          !controller.input.isController) {
        return null;
      }
      return controller.itemStorage(side);
    }
    return _invCap ??= CombinedStorage(_inventories());
  }

  /// `ConnectedInput.getInventories`: the inventories of the group, in insertion order.
  List<ItemStorage> get connectedInventories => _inventories();

  /// `ConnectedInput.getInventories`: the inventories of the group, in insertion order.
  List<ItemStorage> _inventories() {
    if (!input.isController) {
      final controllerPos = pos.toPos() + input.data.first;
      final controller = store.typed<MechanicalCrafterBlockEntity>(
        worldId,
        controllerPos.toBlockPos(),
      );
      if (controller == null ||
          identical(controller, this) ||
          !controller.input.isController) {
        return const [];
      }
      return controller._inventories();
    }

    final facing = blockState.dirOf('facing') ?? Dir.south;
    final axisDirection = facing.isPositive ? 1 : -1;
    final compareAxis = facing.clockWise(KAxis.y).axis;

    final offsets = List<Pos>.of(input.data)
      ..sort((p1, p2) {
        final compareY = -p1.y.compareTo(p2.y);
        final modifier = axisDirection * (compareAxis == KAxis.z ? -1 : 1);
        final c1 = compareAxis.choose(p1.x, p1.y, p1.z);
        final c2 = compareAxis.choose(p2.x, p2.y, p2.z);
        return compareY != 0 ? compareY : modifier * c1.compareTo(c2);
      });

    return [
      for (final offset in offsets)
        if (store.typed<MechanicalCrafterBlockEntity>(
              worldId,
              (pos.toPos() + offset).toBlockPos(),
            )
            case final be?)
          be.inventory,
    ];
  }

  // -- Inventory ------------------------------------------------------------------------------

  bool _mayInsert(int slot, PStack stack) =>
      phase == CrafterPhase.idle && !covered;

  void _onInventoryChanged(int slot) {
    if (inventory.stackIn(slot).isEmpty) return;
    if (phase == CrafterPhase.idle) checkCompletedRecipe(false);
  }

  /// The slot item, for the arm's `CrafterPoint`.
  void allowExtraction() => inventory.extractionAllowed = true;

  void forbidExtraction() => inventory.extractionAllowed = false;

  // -- Persistence ----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Inventory', StackNbt.writeList(inventory.contents));
    tag.putCompound('ConnectedInput', _writeInput(input));
    tag.putCompound('GroupedItems', _writeGroupedItems(groupedItems));
    tag.putString('Phase', phase.javaName);
    tag.putInt('CountDown', countDown);
    tag.putBool('Cover', covered);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final inv = tag.getCompound('Inventory');
    if (inv != null) inventory.load(StackNbt.readList(inv, 1));
    input = _readInput(tag.getCompound('ConnectedInput'));
    groupedItems = _readGroupedItems(tag.getCompound('GroupedItems'));
    phase =
        CrafterPhase.fromJavaName(tag.getString('Phase')) ?? CrafterPhase.idle;
    countDown = tag.getInt('CountDown') ?? 0;
    covered = tag.getBool('Cover') ?? false;
    _invCap = null;
  }

  static NbtCompound _writeInput(ConnectedInput input) {
    final data = <Object>[
      for (final p in input.data)
        NbtCompound()
          ..putInt('X', p.$1)
          ..putInt('Y', p.$2)
          ..putInt('Z', p.$3),
    ];
    return NbtCompound()
      ..putBool('Controller', input.isController)
      ..putList('Data', data);
  }

  static ConnectedInput _readInput(NbtCompound? tag) {
    if (tag == null) return ConnectedInput();
    final isController = tag.getBool('Controller') ?? false;
    final data = <Pos>[
      for (final e in tag.getList('Data') ?? const <Object>[])
        if (e is NbtCompound)
          (e.getInt('X') ?? 0, e.getInt('Y') ?? 0, e.getInt('Z') ?? 0),
    ];
    // NBT got wiped -> reset to a lone controller.
    if (data.isEmpty) return ConnectedInput();
    return ConnectedInput(isController: isController, data: data);
  }

  static NbtCompound _writeGroupedItems(GroupedItems items) {
    final grid = <Object>[
      for (final e in items.grid.entries)
        NbtCompound()
          ..putInt('x', e.key.$1)
          ..putInt('y', e.key.$2)
          ..putCompound('item', StackNbt.write(e.value)),
    ];
    return NbtCompound()..putList('Grid', grid);
  }

  static GroupedItems _readGroupedItems(NbtCompound? tag) {
    final items = GroupedItems();
    for (final e in tag?.getList('Grid') ?? const <Object>[]) {
      if (e is! NbtCompound) continue;
      final x = e.getInt('x') ?? 0;
      final y = e.getInt('y') ?? 0;
      items.grid[(x, y)] = StackNbt.read(e.getCompound('item'));
    }
    return items;
  }

  // -- Ticking --------------------------------------------------------------------------------

  /// `getCountDownSpeed`.
  int get countDownSpeed {
    final value = speed.abs().toInt();
    if (value == 0) return 0;
    return value < 4 ? 4 : (value > 250 ? 250 : value);
  }

  @override
  void tick() {
    super.tick();
    if (phase == CrafterPhase.accepting) return;

    _pollPower();

    if (phase == CrafterPhase.assembling) {
      countDown -= countDownSpeed;
      if (countDown < 0) {
        countDown = 0;
        final target = targetingCrafter(_crafterWorld, this);
        if (target != null) {
          phase = CrafterPhase.exporting;
          countDown = groupedItems.onlyEmptyItems ? 0 : 1000;
          sendData();
          return;
        }
        _run(_assemble);
        return;
      }
    }

    if (phase == CrafterPhase.exporting) {
      countDown -= countDownSpeed;
      if (countDown < 0) {
        countDown = 0;
        _run(_export);
        return;
      }
    }

    if (phase == CrafterPhase.crafting) {
      final previous = countDown;
      countDown -= countDownSpeed;
      if (countDown < 1000 && previous >= 1000) {
        _playSound('create:crafter_click', 1, 2);
        _playSound('create:crafter_craft', 1, 1);
      }
      if (countDown < 0) {
        countDown = 0;
        _run(tryInsert);
        return;
      }
    }

    if (phase == CrafterPhase.inserting) {
      if (_isTargetingBelt()) _run(tryInsert);
      return;
    }
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (phase == CrafterPhase.idle && hasCraftingItem) {
      checkCompletedRecipe(false);
    }
    if (phase == CrafterPhase.inserting) _run(tryInsert);
  }

  @override
  void onRemoved() {
    super.onRemoved();
    // `MechanicalCrafterBlock.affectNeighborsAfterRemoval`: the cover and the grid drop.
    final world = this.world;
    if (world != null && covered) {
      unawaited(
        dropPStack(
          world,
          pos.toPos().center,
          const PStack('create:crafter_slot_cover', 1),
        ),
      );
    }
    unawaited(_guard(ejectWholeGrid));
  }

  /// Runs [body] unless host work of this entity is already in flight.
  void _run(Future<void> Function() body) => unawaited(_guard(body));

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    try {
      await body();
    } catch (e, s) {
      _rt.log.error(
        'The mechanical crafter at $pos failed',
        error: e,
        stackTrace: s,
      );
    } finally {
      _busy = false;
    }
  }

  /// `level.hasNeighborSignal` polled each tick (`wasPoweredBefore` is not saved).
  void _pollPower() {
    if (_pollingPower) return;
    final world = this.world;
    if (world == null) return;
    _pollingPower = true;
    unawaited(() async {
      try {
        final powered = await world.hasNeighborSignal(pos: pos);
        if (powered == wasPoweredBefore) return;
        wasPoweredBefore = powered;
        if (powered) checkCompletedRecipe(true);
      } catch (_) {
        // a world that is going away
      } finally {
        _pollingPower = false;
      }
    }());
  }

  // -- Crafting -------------------------------------------------------------------------------

  /// `checkCompletedRecipe`.
  void checkCompletedRecipe(bool poweredStart) {
    if (speed == 0) return;
    final chain = allCraftersOfChainIf(
      _crafterWorld,
      this,
      poweredStart ? (n) => n.hasCraftingItem : (n) => n.hasCraftingItemOrCover,
      poweredStart: poweredStart,
    );
    if (chain == null) return;
    for (final node in chain) {
      node.begin();
    }
  }

  /// The `ASSEMBLING` phase: apply a recipe to the grid, or eject it.
  Future<void> _assemble() async {
    final result = await _tryToApplyRecipe();
    if (result != null) {
      groupedItems = GroupedItems.single(result);
      phase = CrafterPhase.crafting;
      countDown = 2000;
      sendData();
      return;
    }
    await ejectWholeGrid();
  }

  /// `RecipeGridHandler.tryToApplyRecipe`: a vanilla crafting recipe when the config allows it,
  /// then Create's `mechanical_crafting` recipes.
  Future<PStack?> _tryToApplyRecipe() async {
    final input = craftingInputOf(groupedItems);
    if (input.isEmpty) return null;

    final configs = _rt.configs;
    final allowRegular =
        configs?.server.recipes.allowRegularCraftingInCrafter.value ?? true;
    final manager = sharedCraftingRecipes;
    if (allowRegular && manager != null) {
      try {
        final result = manager.matchCrafting(input.rows);
        if (result != null && _isVanillaCraftingAllowed(result, input)) {
          return PStack(result.output.item, result.output.count);
        }
      } on Object {
        // a recipe manager that cannot be read leaves the mechanical recipes
      }
    }

    final recipe = findMechanicalCraftingRecipe(
      _rt.recipes.mechanicalCrafting,
      groupedItems,
      _rt.tags,
    );
    if (recipe == null) return null;
    return recipe.result.roll(_rt.random);
  }

  /// `RecipeGridHandler.isRecipeAllowed`: firework rockets may not exceed the configured number
  /// of ingredients.
  bool _isVanillaCraftingAllowed(
    CraftingResult result,
    CraftingGridInput input,
  ) {
    if (result.recipeType != 'minecraft:crafting_special_firework_rocket') {
      return true;
    }
    final max =
        _rt.configs?.server.recipes.maxFireworkIngredientsInCrafter.value ?? 9;
    var count = 0;
    for (final stack in input.cells) {
      if (stack.isNotEmpty) count++;
    }
    return count <= max;
  }

  /// The `EXPORTING` phase: move the grid onto the crafter this one points at.
  Future<void> _export() async {
    final target = targetingCrafter(_crafterWorld, this);
    if (target is! MechanicalCrafterBlockEntity) {
      await ejectWholeGrid();
      return;
    }

    final empty = groupedItems.onlyEmptyItems;
    final pointing =
        crafterPointingByName(blockState['pointing']) ?? CrafterPointing.up;
    groupedItems.mergeOnto(target.groupedItems, pointing);
    groupedItems = GroupedItems();

    final pitch = target.groupedItems.grid.length / 16 + .5;
    if (!empty) _playSound('create:crafter_click', 1, pitch);

    phase = CrafterPhase.waiting;
    countDown = 0;
    sendData();
    target.continueIfAllPrecedingFinished();
    target.sendData();
  }

  /// `tryInsert`: hand the grid to the inventory or belt the crafter points at.
  Future<void> tryInsert() async {
    final world = this.world;
    if (world == null) return;

    final targetDirection = crafterTargetDirection(crafterState);
    final targetPos =
        pos.toPos() +
        (targetDirection.stepX, targetDirection.stepY, targetDirection.stepZ);
    final targetBlockPos = targetPos.toBlockPos();

    final belt = store
        .at(worldId, targetBlockPos)
        ?.getBehaviour<DirectBeltInputBehaviour>();
    final storage = _rt.storage.pluginItemStorage(worldId, targetBlockPos);
    final hasHostStorage =
        storage == null &&
        _rt.storage.hasItemStorage(world, worldId, targetBlockPos);
    if (belt == null && storage == null && !hasHostStorage) {
      await ejectWholeGrid();
      return;
    }

    final changedPhase = phase != CrafterPhase.inserting;
    final inserted = <(int, int)>[];

    for (final entry in groupedItems.grid.entries) {
      final stack = entry.value;
      PStack remainder;
      if (belt != null) {
        remainder = belt.handleInsertionOfStack(
          stack,
          targetDirection.name,
          false,
        );
      } else if (storage != null) {
        remainder = ItemStorages.insertStacked(storage, stack);
      } else {
        remainder = await _rt.storage.hostInsert(world, targetBlockPos, stack);
      }
      if (remainder.isNotEmpty) {
        groupedItems.grid[entry.key] = stack.withCount(remainder.count);
        continue;
      }
      inserted.add(entry.key);
    }

    for (final key in inserted) {
      groupedItems.grid.remove(key);
    }
    if (groupedItems.grid.isEmpty) {
      await ejectWholeGrid();
    } else {
      phase = CrafterPhase.inserting;
    }
    if (inserted.isNotEmpty || changedPhase) sendData();
  }

  /// Whether the crafter points at a belt that accepts items from its side.
  bool _isTargetingBelt() {
    final targetDirection = crafterTargetDirection(crafterState);
    final targetPos =
        pos.toPos() +
        (targetDirection.stepX, targetDirection.stepY, targetDirection.stepZ);
    final behaviour = store
        .at(worldId, targetPos.toBlockPos())
        ?.getBehaviour<DirectBeltInputBehaviour>();
    return behaviour != null &&
        behaviour.canInsertFromSide(targetDirection.name);
  }

  /// `ejectWholeGrid`.
  Future<void> ejectWholeGrid() async {
    final chain = allCraftersOfChain(_crafterWorld, this);
    if (chain == null) return;
    for (final node in chain) {
      node.eject();
    }
  }

  /// `connectivityChanged`: the combined handler has to be rebuilt.
  void connectivityChanged() {
    _invCap = null;
    sendData();
  }

  // -- Connected inputs (`ConnectedInputHandler`) ---------------------------------------------

  /// `ConnectedInputHandler.toggleConnection`: joins or splits the connected input groups of
  /// [a] and [b]. Create triggers this from an edge interaction; the host has no edge
  /// interactions, so the crafter calls it when a wrench clicks the side towards [b].
  static void toggleConnection(
    BlockEntityStore store,
    String worldId,
    Pos a,
    Pos b,
  ) {
    MechanicalCrafterBlockEntity? crafterAt(Pos p) =>
        store.typed<MechanicalCrafterBlockEntity>(worldId, p.toBlockPos());

    var crafter1 = crafterAt(a);
    var crafter2 = crafterAt(b);
    if (crafter1 == null || crafter2 == null) return;

    final controllerPos1 = crafter1.pos.toPos() + crafter1.input.data.first;
    final controllerPos2 = crafter2.pos.toPos() + crafter2.input.data.first;

    if (controllerPos1 == controllerPos2) {
      // Split the group in two: everything reachable from b stays with b.
      final positions = <Pos>{
        for (final offset in crafter1.input.data) controllerPos1 + offset,
      };
      final frontier = <Pos>[b];
      final splitGroup = <Pos>[];
      positions.remove(b);
      positions.remove(a);
      while (frontier.isNotEmpty) {
        final current = frontier.removeAt(0);
        for (final direction in Direction.values) {
          final next = current.relative(direction);
          if (!positions.remove(next)) continue;
          splitGroup.add(next);
          frontier.add(next);
        }
      }

      _initAndAddAll(store, worldId, crafter1, positions);
      _initAndAddAll(store, worldId, crafter2, splitGroup);

      crafter1.markDirty();
      crafter1.connectivityChanged();
      crafter2.markDirty();
      crafter2.connectivityChanged();
      return;
    }

    if (!crafter1.input.isController) {
      crafter1 = crafterAt(controllerPos1);
    }
    if (!crafter2.input.isController) {
      crafter2 = crafterAt(controllerPos2);
    }
    if (crafter1 == null || crafter2 == null) return;

    _connectControllers(store, worldId, crafter1, crafter2);

    crafter1.markDirty();
    crafter1.connectivityChanged();
    crafter2.markDirty();
    crafter2.connectivityChanged();
  }

  static void _initAndAddAll(
    BlockEntityStore store,
    String worldId,
    MechanicalCrafterBlockEntity crafter,
    Iterable<Pos> positions,
  ) {
    crafter.input = ConnectedInput();
    for (final splitPos in positions) {
      _modifyAndUpdate(store, worldId, splitPos, (input) {
        input.attachTo(crafter.pos.toPos(), splitPos);
        crafter.input.data.add(splitPos - crafter.pos.toPos());
      });
    }
  }

  static void _connectControllers(
    BlockEntityStore store,
    String worldId,
    MechanicalCrafterBlockEntity crafter1,
    MechanicalCrafterBlockEntity crafter2,
  ) {
    for (final offset in List<Pos>.of(crafter1.input.data)) {
      _modifyAndUpdate(store, worldId, crafter1.pos.toPos() + offset, (_) {});
    }

    for (final offset in List<Pos>.of(crafter2.input.data)) {
      if (offset == posZero) continue;
      final connectedPos = crafter2.pos.toPos() + offset;
      _modifyAndUpdate(store, worldId, connectedPos, (input) {
        input.attachTo(crafter1.pos.toPos(), connectedPos);
        crafter1.input.data.add(posZero - input.data.first);
      });
    }

    crafter2.input.attachTo(crafter1.pos.toPos(), crafter2.pos.toPos());
    crafter1.input.data.add(posZero - crafter2.input.data.first);
  }

  static void _modifyAndUpdate(
    BlockEntityStore store,
    String worldId,
    Pos pos,
    void Function(ConnectedInput input) callback,
  ) {
    final crafter = store.typed<MechanicalCrafterBlockEntity>(
      worldId,
      pos.toBlockPos(),
    );
    if (crafter == null) return;
    callback(crafter.input);
    crafter.markDirty();
    crafter.connectivityChanged();
  }

  /// `getTargetDirection` of this crafter.
  Direction get targetDirection => crafterTargetDirection(crafterState);

  void _dropItem(Vec3 ejectPos, PStack stack) {
    final world = this.world;
    if (world == null || stack.isEmpty) return;
    unawaited(dropPStack(world, ejectPos, stack));
  }

  void _playSound(String sound, double volume, double pitch) {
    final world = this.world;
    if (world == null) return;
    world.playCustomSound(
      soundName: sound,
      category: SoundCategory.blocks,
      pos: (pos.x + .5, pos.y + .5, pos.z + .5),
      volume: volume,
      pitch: pitch,
    );
  }

  @override
  String toString() => 'MechanicalCrafter${super.toString()}';
}

/// The [CrafterWorld] over the block entity store and the kinetic level.
final class _StoreCrafterWorld implements CrafterWorld {
  final MechanicalCrafterBlockEntity _be;

  _StoreCrafterWorld(this._be);

  @override
  BState stateAt(Pos pos) {
    final level = KineticsRuntime.instance.level(_be.worldId);
    return bStateOf(level.stateAt(toKPos(pos.toBlockPos())));
  }

  @override
  bool isLoaded(Pos pos) => _be.world?.isLoaded(pos: pos.toBlockPos()) ?? false;

  @override
  CrafterNode? crafterAt(Pos pos) => _be.store
      .typed<MechanicalCrafterBlockEntity>(_be.worldId, pos.toBlockPos());
}

// `DeployerBlockEntity`: the mechanical deployer. A kinetic block entity that owns a fake player,
// fills its hand from its overflow, and every cycle extends the hand to use the held item on the
// block (or entity) in front of it, or to punch it.
//
// Ported from `content/kinetics/deployer/DeployerBlockEntity.java` and `DeployerFakePlayer.java`.
// The fake player is the host's (`FakePlayers`), so `canEat`, menu opening and mob retaliation
// behave like the host's fake players rather than Java's overrides. `spawnedItemEffects` (client
// particles) is not ported.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../api/value_settings.dart';
import '../support/kinetics_bridge.dart';
import '../crafter/machine_support.dart' show dropPStack;
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/recipe.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';
import '../transport/transport_behaviours.dart';
import 'belt_deployer_callbacks.dart';
import 'deployer_filter.dart';
import 'deployer_handler.dart';
import 'deployer_item_handler.dart';
import 'deployer_items.dart';
import 'deployer_types.dart';

/// `DeployerBlockEntity`.
final class DeployerBlockEntity extends KineticBlockEntity
    implements ItemStorageProvider, ValueSettingsHost {
  DeployerBlockEntity(super.worldId, super.pos) {
    filtering = addBehaviour(DeployerFilterBehaviour());
    processingBehaviour = addBehaviour(
      BeltProcessingBehaviour()
        ..whenItemEnters(
          (s, i) => BeltDeployerCallbacks.onItemReceived(s, i, this),
        )
        ..whileItemHeld(
          (s, i) => BeltDeployerCallbacks.whenItemHeld(s, i, this),
        ),
    );
    invHandler = DeployerItemHandler(
      overflow: overflowItems,
      getHeld: () => heldItem,
      setHeld: _setHeld,
      validator: (stack) => filtering.test(stack),
      isFilterActive: () => filtering.filter.isNotEmpty,
      onChanged: () {
        markDirty();
        sendData();
      },
    );
  }

  /// `state`.
  DeployerState state = DeployerState.waiting;

  /// `mode`.
  DeployerMode mode = DeployerMode.use;

  /// The item in the fake player's main hand (a cached value of the host stack).
  PStack heldItem = PStack.empty;

  /// `overflowItems`: the items that do not fit the hand.
  final List<PStack> overflowItems = [];

  /// `filtering`.
  late final DeployerFilterBehaviour filtering;

  /// `processingBehaviour`.
  late final BeltProcessingBehaviour processingBehaviour;

  /// `timer`.
  int timer = 0;

  /// `reach`.
  double reach = 0;

  /// `fistBump`.
  bool fistBump = false;

  /// `redstoneLocked`.
  bool redstoneLocked = false;

  /// `owner`: the uuid of the player that placed the deployer.
  String? owner;

  /// `blockBreakingProgress` (the block being punched).
  Pos? blockBreakingPos;

  /// `deferredInventoryList`: the inventory read before the fake player could be created.
  List<PStack>? _deferredInventory;

  /// The fake player (owned; kept alive across ticks).
  Player? _player;

  /// The fake player's 36 main slots, mirrored for [write]: the host inventory can only be read
  /// asynchronously, so it is refreshed after everything that can change it.
  List<PStack> _playerInventory = List<PStack>.filled(36, PStack.empty);

  /// `invHandler`.
  late final DeployerItemHandler invHandler;

  bool _busy = false;
  bool _redstonePolling = false;

  ProcessingRuntime get _rt => ProcessingRuntime.instance;

  // -- Lifecycle ------------------------------------------------------------------------------

  @override
  void initialize() {
    super.initialize();
    _initHandler();
  }

  @override
  void onUnload() {
    // The chunk unloads: the saved data keeps the inventory, the fake player is not needed.
    _discardPlayer(drop: false);
    super.onUnload();
  }

  @override
  void onRemoved() {
    _discardPlayer(drop: true);
    super.onRemoved();
  }

  /// `initHandler`.
  void _initHandler() {
    if (_player != null) return;
    final world = this.world;
    if (world == null) return;
    try {
      final ownerUuid = owner == null ? null : Uuids.tryParse(owner!);
      Player player;
      try {
        player = FakePlayers.create(world, 'Deployer', id: ownerUuid).keep();
      } on Object {
        // Two deployers of one owner cannot share the host's fake player uuid: use a unique name.
        player = FakePlayers.create(
          world,
          'Deployer@${pos.x},${pos.y},${pos.z}',
        ).keep();
      }
      _player = player;
      final inventory = player.getInventory();
      inventory.setSelectedSlot(slot: 0);

      final deferred = _deferredInventory;
      if (deferred != null) {
        _deferredInventory = null;
        unawaited(_loadInventory(player, deferred));
      } else if (heldItem.isNotEmpty) {
        // A saved `HeldItem` without a saved inventory still has to reach the hand.
        unawaited(setHeld(heldItem));
      }

      final facing = blockState.dirOf('facing') ?? Dir.up;
      final (yaw, pitch) = lookOf(facing);
      FakePlayerActions(player).moveTo(
        world,
        (
          pos.x + .5 + facing.dx,
          pos.y + .5 + facing.dy,
          pos.z + .5 + facing.dz,
        ),
        yaw: yaw,
        pitch: pitch,
      );

      sendData();
    } on Object catch (e, s) {
      _rt.log.error(
        'The deployer at $pos could not create its fake player',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// The look of the fake player for [facing] (`DeployerBlockEntity.activate`): `XRot` is -90
  /// looking up, 90 looking down and 0 sideways; `YRot` is the facing's yaw.
  static (double, double) lookOf(Dir facing) => (
    Direction.values[facing.index].toYRot,
    facing == Dir.up ? -90.0 : (facing == Dir.down ? 90.0 : 0.0),
  );

  /// The fake player (`DeployerBlockEntity.getPlayer`).
  Player? get player => _player;

  /// Refreshes [_playerInventory] from the fake player's main slots. Called after everything
  /// that can change them, so [write] can serialise them synchronously.
  Future<void> snapshotInventory() async {
    final player = _player;
    if (player == null) return;
    final inventory = player.getInventory().storage;
    final size = inventory.getSize();
    final slots = List<PStack>.filled(36, PStack.empty);
    for (var slot = 0; slot < size && slot < slots.length; slot++) {
      final item = inventory.getItem(slot: slot);
      if (item == null) continue;
      slots[slot] = await HostStacks.read(item);
      item.dispose();
    }
    _playerInventory = slots;
  }

  Future<void> _loadInventory(Player player, List<PStack> stacks) async {
    final inventory = player.getInventory().storage;
    for (
      var slot = 0;
      slot < stacks.length && slot < inventory.getSize();
      slot++
    ) {
      final stack = stacks[slot];
      if (stack.isEmpty) continue;
      final item = await HostStacks.write(stack);
      if (item == null) continue;
      await inventory.setItem(slot: slot, item: item);
    }
    // `HeldItem` is the authoritative hand item (the inventory carries it at the selected slot).
    if (heldItem.isNotEmpty) await setHeld(heldItem);
    await _syncHeld();
    await snapshotInventory();
  }

  /// `discardPlayer`: drops the inventory (when [drop]) and releases the fake player.
  void _discardPlayer({required bool drop}) {
    final player = _player;
    _player = null;
    if (player == null) return;
    if (drop) {
      unawaited(_dropPlayerContentsThenRelease(player));
      return;
    }
    // The player is gone but the contents are not: the saved data has to keep them.
    _deferredInventory = List<PStack>.of(_playerInventory);
    _releasePlayer(player);
  }

  Future<void> _dropPlayerContentsThenRelease(Player player) async {
    await _dropPlayerContents(player);
    _releasePlayer(player);
  }

  void _releasePlayer(Player player) {
    try {
      FakePlayers.remove(player);
    } on Object {
      // already gone
    }
    try {
      player.dispose();
    } on Object {
      // already released
    }
  }

  Future<void> _dropPlayerContents(Player player) async {
    final world = this.world;
    if (world != null) {
      final inventory = player.getInventory().storage;
      for (var slot = 0; slot < inventory.getSize(); slot++) {
        final item = inventory.getItem(slot: slot);
        if (item == null) continue;
        final stack = await HostStacks.read(item);
        item.dispose();
        if (stack.isEmpty) continue;
        await inventory.setItem(slot: slot, item: null);
        await dropPStack(world, pos.toPos().center, stack);
      }
      for (final stack in List<PStack>.of(overflowItems)) {
        await dropPStack(world, pos.toPos().center, stack);
      }
    }
    overflowItems.clear();
  }

  // -- Capabilities ---------------------------------------------------------------------------

  @override
  ItemStorage? itemStorage(String? side) {
    _initHandler();
    return invHandler;
  }

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [filtering];

  void _setHeld(PStack stack) {
    heldItem = stack.isEmpty ? PStack.empty : stack;
    final player = _player;
    if (player == null) return;
    unawaited(_writeHeld(player, heldItem));
  }

  /// Sets the item in the fake player's main hand and updates the cached hand.
  Future<void> setHeld(PStack stack) async {
    heldItem = stack.isEmpty ? PStack.empty : stack;
    final player = _player;
    if (player == null) return;
    await _writeHeld(player, heldItem);
  }

  Future<void> _writeHeld(Player player, PStack stack) async {
    try {
      final item = await HostStacks.write(stack);
      await player.setItemInHand(hand: Hand.right, stack: item);
    } on Object {
      // the player is going away
    }
  }

  /// Reads the main hand of the fake player into [heldItem].
  Future<void> _syncHeld() async {
    final player = _player;
    if (player == null) {
      heldItem = PStack.empty;
      return;
    }
    try {
      final item = player.getItemInHand(hand: Hand.right);
      if (item == null) {
        heldItem = PStack.empty;
        return;
      }
      heldItem = await HostStacks.read(item);
      item.dispose();
    } on Object {
      heldItem = PStack.empty;
    }
  }

  // -- Persistence ----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putString('Mode', mode.javaName);
    tag.putString('State', state.javaName);
    tag.putInt('Timer', timer);
    tag.putBool('Powered', redstoneLocked);
    final owner = this.owner;
    if (owner != null) {
      final ownerUuid = _ownerToNbt(owner);
      if (ownerUuid != null) tag.putIntArray('Owner', ownerUuid);
    }

    // Java: the fake player's inventory is written as the vanilla `Inventory` list (byte `Slot`),
    // with `HeldItem` and `Overflow` alongside; without a player only the deferred list is kept.
    final player = _player;
    if (player != null) {
      // The host inventory can only be read asynchronously, so the mirror (refreshed after every
      // activation) is what gets saved. The selected slot is the hand.
      final inventory = List<PStack>.of(_playerInventory);
      inventory[0] = heldItem;
      tag.putList('Inventory', _writeInventoryList(inventory));
      tag.putCompound('HeldItem', StackNbt.writeOrEmpty(heldItem));
      tag.putList('Overflow', [
        for (final stack in overflowItems) StackNbt.write(stack),
      ]);
    } else {
      final deferred = _deferredInventory;
      if (deferred != null) {
        tag.putList('Inventory', _writeInventoryList(deferred));
      }
    }

    super.write(tag, clientPacket: clientPacket);

    if (!clientPacket) return;
    tag.putBool('Fistbump', fistBump);
    tag.putFloat('Reach', reach);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    mode = DeployerMode.fromJavaName(tag.getString('Mode'));
    state = DeployerState.fromJavaName(tag.getString('State'));
    timer = tag.getInt('Timer') ?? 0;
    redstoneLocked = tag.getBool('Powered') ?? false;
    owner = _ownerFromNbt(tag.getIntArray('Owner')) ?? tag.getString('Owner');
    // The vanilla list form; the compound `{Items, Size}` of earlier versions is still read.
    final inventoryList = tag.getList('Inventory');
    if (inventoryList != null) {
      _deferredInventory = _readInventoryList(inventoryList, 36);
    } else {
      final legacy = tag.getCompound('Inventory');
      _deferredInventory = legacy == null
          ? List<PStack>.filled(36, PStack.empty)
          : StackNbt.readList(legacy, 36);
    }
    heldItem = StackNbt.read(tag.getCompound('HeldItem'));
    overflowItems
      ..clear()
      ..addAll([
        for (final e in tag.getList('Overflow') ?? const <Object>[])
          if (e is NbtCompound) StackNbt.read(e),
      ]);
    if (clientPacket) {
      fistBump = tag.getBool('Fistbump') ?? false;
      reach = tag.getDouble('Reach') ?? 0;
    }
  }

  /// The vanilla `Inventory` list: one `{Slot, ...stack}` compound per non-empty slot.
  static List<Object> _writeInventoryList(List<PStack> stacks) {
    final items = <Object>[];
    for (var slot = 0; slot < stacks.length; slot++) {
      if (stacks[slot].isEmpty) continue;
      items.add(StackNbt.write(stacks[slot])..putByte('Slot', slot));
    }
    return items;
  }

  static List<PStack> _readInventoryList(List<Object> list, int size) {
    final out = List<PStack>.filled(size, PStack.empty);
    for (final element in list) {
      if (element is! NbtCompound) continue;
      final slot = element.getInt('Slot') ?? -1;
      if (slot >= 0 && slot < size) out[slot] = StackNbt.read(element);
    }
    return out;
  }

  /// `UUIDUtil.CODEC`: four ints (the two halves of the uuid, big-endian each).
  static List<int>? _ownerToNbt(String owner) {
    final uuid = Uuids.tryParse(owner);
    if (uuid == null) return null;
    return [
      (uuid.high >> 32) & 0xFFFFFFFF,
      uuid.high & 0xFFFFFFFF,
      (uuid.low >> 32) & 0xFFFFFFFF,
      uuid.low & 0xFFFFFFFF,
    ];
  }

  static String? _ownerFromNbt(List<int>? value) {
    if (value == null || value.length < 4) return null;
    return Uuid(
      high: (value[0] << 32) | (value[1] & 0xFFFFFFFF),
      low: (value[2] << 32) | (value[3] & 0xFFFFFFFF),
    ).asString;
  }

  // -- Ticking --------------------------------------------------------------------------------

  /// `getTimerSpeed`.
  int get timerSpeed {
    final value = (speed.abs() * 2).toInt();
    if (value == 0) return 0;
    return value < 8 ? 8 : (value > 512 ? 512 : value);
  }

  Vec3 get _movementVector {
    final facing = blockState.dirOf('facing') ?? Dir.up;
    return (facing.dx.toDouble(), facing.dy.toDouble(), facing.dz.toDouble());
  }

  @override
  void tick() {
    super.tick();
    if (speed == 0) return;

    // A block that disappeared while being punched clears the progress.
    final breaking = blockBreakingPos;
    if (breaking != null) {
      final world = this.world;
      if (world != null && world.getBlock(pos: breaking.toBlockPos()).isAir) {
        blockBreakingPos = null;
      }
    }

    if (timer > 0) {
      timer -= timerSpeed;
      return;
    }
    if (_player == null) {
      _initHandler();
      if (_player == null) return;
    }
    _run(_tickAsync);
  }

  Future<void> _tickAsync() async {
    final player = _player;
    final world = this.world;
    if (player == null || world == null) return;

    if (state == DeployerState.waiting) {
      if (overflowItems.isNotEmpty) {
        timer = timerSpeed * 10;
        return;
      }

      var changed = false;
      final inventory = player.getInventory().storage;
      final selected = player.getInventory().getSelectedSlot();
      for (var slot = 0; slot < inventory.getSize(); slot++) {
        if (overflowItems.length > 10) break;
        final item = inventory.getItem(slot: slot);
        if (item == null) continue;
        final stack = await HostStacks.read(item);
        item.dispose();
        if (stack.isEmpty) continue;
        if (slot != selected || !filtering.test(stack)) {
          overflowItems.add(stack);
          await inventory.setItem(slot: slot, item: null);
          changed = true;
        }
      }

      if (changed) {
        await _syncHeld();
        await snapshotInventory();
        sendData();
        timer = timerSpeed * 10;
        return;
      }

      final facing = blockState.dirOf('facing') ?? Dir.up;
      final target = pos.toPos().relative(Direction.values[facing.index], 2);
      if (mode == DeployerMode.use &&
          !DeployerHandler.shouldActivate(
            heldItem,
            world,
            target,
            Direction.values[facing.index],
          )) {
        timer = timerSpeed * 10;
        return;
      }

      if (mode == DeployerMode.punch && !fistBump && startFistBump(facing)) {
        return;
      }
      if (redstoneLocked) return;

      await start();
      return;
    }

    if (state == DeployerState.expanding) {
      if (fistBump) triggerFistBump();
      await activate();
      await snapshotInventory();
      state = DeployerState.retracting;
      timer = 1000;
      sendData();
      return;
    }

    if (state == DeployerState.retracting) {
      state = DeployerState.waiting;
      timer = 500;
      sendData();
    }
  }

  /// `start`: extends the hand and measures how far it reaches.
  Future<void> start() async {
    state = DeployerState.expanding;
    final world = this.world;
    final movement = _movementVector;
    final center = pos.toPos().center;
    final origin = center + movement * (3 / 2);
    final target = center + movement * (5 / 2);
    var length = (target - origin).length;
    if (world != null) {
      try {
        final hit = world.rayTraceBlock(
          start: origin,
          end: target,
          includeFluids: false,
        );
        if (hit != null) {
          length = (hit.hitPos - origin).length;
        }
      } on Object {
        // no ray trace available
      }
    }
    reach = .5 + math.min(length, .75);
    timer = 1000;
    sendData();
  }

  /// `activate`: uses the held item in front of the deployer.
  Future<void> activate() async {
    final player = _player;
    final world = this.world;
    if (player == null || world == null) return;

    final facing = blockState.dirOf('facing') ?? Dir.up;
    final direction = Direction.values[facing.index];
    final clickedPos = pos.toPos().relative(direction, 2);
    final (yaw, pitch) = lookOf(facing);

    // `DeployerBlockEntity.activate`: a belt or depot below the deployer is processed by
    // `BeltDeployerCallbacks`, not by the vanilla item use.
    if (facing == Dir.down && _beltBelow(clickedPos)) return;

    blockBreakingPos = await DeployerHandler.activate(
      player,
      world,
      pos.toPos().center,
      clickedPos,
      _movementVector,
      mode,
      breakingPos: blockBreakingPos,
      look: (yaw, pitch),
    );
    await _syncHeld();
  }

  /// Whether the block at [clickedPos] carries a `TransportedItemStackHandlerBehaviour`
  /// (`BlockEntityBehaviour.get(level, pos, TYPE) != null`).
  bool _beltBelow(Pos clickedPos) {
    final rt = _rt;
    final world = this.world;
    if (world == null) return false;
    final worldId = rt.worlds.touch(world);
    final be = rt.store.at(worldId, clickedPos.toBlockPos());
    return be?.getBehaviour<TransportedItemStackHandlerBehaviour>() != null;
  }

  /// `startFistBump`: two deployers facing each other with punch mode bump fists.
  bool startFistBump(Dir facing) {
    final world = this.world;
    if (world == null) return false;
    for (var i = 2; i < 5; i++) {
      final otherPos = pos.toPos().relative(Direction.values[facing.index], i);
      if (!world.isLoaded(pos: otherPos.toBlockPos())) return false;
      final other = store.typed<DeployerBlockEntity>(
        worldId,
        otherPos.toBlockPos(),
      );
      if (other == null) continue;

      final otherFacing = other.blockState.dirOf('facing') ?? Dir.up;
      if (otherFacing.opposite != facing || other.mode != DeployerMode.punch) {
        return false;
      }
      if (other.speed == 0) return false;

      for (final be in [this, other]) {
        be.fistBump = true;
        be.reach = (i - 2) * .5;
        be.timer = 1000;
        be.state = DeployerState.expanding;
        be.sendData();
      }
      return true;
    }
    return false;
  }

  /// `triggerFistBump`.
  void triggerFistBump() {
    final world = this.world;
    if (world == null) return;
    final facing = blockState.dirOf('facing') ?? Dir.up;
    for (var i = 2; i < 5; i++) {
      final otherPos = pos.toPos().relative(Direction.values[facing.index], i);
      if (!world.isLoaded(pos: otherPos.toBlockPos())) return;
      final other = store.typed<DeployerBlockEntity>(
        worldId,
        otherPos.toBlockPos(),
      );
      if (other == null) continue;

      if (!other.fistBump || other.state != DeployerState.expanding) return;
      if (other.timer > 0) return;

      fistBump = false;
      other.fistBump = false;
      other.state = DeployerState.retracting;
      other.timer = 1000;
      other.sendData();
      world.playSound(
        sound: Sound.entityPlayerAttackNodamage,
        category: SoundCategory.blocks,
        pos: (
          (pos.x + other.pos.x) / 2 + .5,
          (pos.y + other.pos.y) / 2 + .5,
          (pos.z + other.pos.z) / 2 + .5,
        ),
        volume: .75,
        pitch: .75,
      );
      return;
    }
  }

  /// `changeMode`.
  void changeMode() {
    mode = mode == DeployerMode.punch ? DeployerMode.use : DeployerMode.punch;
    markDirty();
    sendData();
  }

  /// `redstoneUpdate`.
  void redstoneUpdate() {
    if (_redstonePolling) return;
    final world = this.world;
    if (world == null) return;
    _redstonePolling = true;
    unawaited(() async {
      try {
        final powered = await world.hasNeighborSignal(pos: pos);
        if (powered == redstoneLocked) return;
        redstoneLocked = powered;
        sendData();
      } on Object {
        // the world is going away
      } finally {
        _redstonePolling = false;
      }
    }());
  }

  /// The recipe the deployer would apply to [stack] (`DeployerBlockEntity.getRecipe`).
  ///
  /// `checkRecipe` filters with `AllRecipeTypes.CAN_BE_AUTOMATED`: a recipe whose id ends in
  /// `_manual_only` is never applied by a deployer.
  RecipeMatch? getRecipe(PStack stack) {
    if (heldItem.isEmpty) return null;
    bool automated(ProcessingRecipe recipe) => !ignoredInAutomation(recipe.id);
    if (isSandPaperItem(heldItem)) {
      final polishing = _rt.recipes.findForInput(
        CreateRecipeType.sandpaperPolishing,
        stack,
        accept: automated,
      );
      if (polishing != null) return polishing;
    }
    return _rt.recipes.findApplication(
      const [CreateRecipeType.deploying, CreateRecipeType.itemApplication],
      stack,
      heldItem,
      accept: automated,
    );
  }

  void _run(Future<void> Function() body) => unawaited(_guard(body));

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    try {
      await body();
    } catch (e, s) {
      _rt.log.error('The deployer at $pos failed', error: e, stackTrace: s);
    } finally {
      _busy = false;
    }
  }

  @override
  String toString() => 'Deployer${super.toString()}';
}

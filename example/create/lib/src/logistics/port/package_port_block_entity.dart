// `PackagePortBlockEntity`, `FrogportBlockEntity` and `PostboxBlockEntity`: the ports that accept
// packages and forward them to their target (a chain conveyor or a train station).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../conveyance/chain/chain_conveyor_block_entity.dart';
import '../../conveyance/chain/chain_conveyor_logic.dart';
import '../../conveyance/chain/chain_conveyor_port.dart';
import '../../conveyance/items/inventory.dart' hide insertStacked;
import '../../conveyance/items/item_data.dart';
import '../../conveyance/transport/transport_inventory_api.dart'
    show ItemInventoryProvider;
import '../host/host_inventory.dart';
import '../host/lg_block_entity.dart';
import '../host/lvl.dart';
import '../host/nbt_codecs.dart';
import '../host/runtime.dart';
import '../model/inventory.dart';
import '../model/package.dart';
import '../model/stack.dart';
import '../packager/packager_block_entity.dart';
import 'conveyance_items.dart';
import 'package_port_target.dart';

/// A frogport that can be woken by the packager below it (`FrogportBlockEntity`).
abstract interface class FrogportPuller {
  void tryPullingFromOwnAndAdjacentInventories();
}

/// `PackagePortBlockEntity`.
abstract class PackagePortBlockEntity extends LgBlockEntity
    implements ItemInventoryProvider {
  /// The 18 package slots (`inventory` in Java; named `packages` here because `inventory` is a
  /// host top-level name).
  final MemoryInv packages = MemoryInv(
    18,
    limit: 64,
    validator: (slot, stack) => PackageItem.isPackage(stack),
  );

  bool acceptsPackages = true;
  String addressFilter = '';
  PackagePortTarget? target;

  final Map<String, dynamic> _state = {};

  PackagePortBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => _state;

  /// The package filter string (`getFilterString`), `null` when packages are not accepted.
  String? get filterString => acceptsPackages ? addressFilter : null;

  bool get isBackedUp => packages.nonEmpty().length >= packages.slots;

  /// `PackagePortAutomationInventoryWrapper`: the buffer as automation sees it. A box can only
  /// be taken out when the port does not want it (it does not match the address filter), and a
  /// box the port wants cannot be put in by automation.
  @override
  ItemInventory? itemInventory(Direction? side) => _automation;

  late final ItemInventory _automation = _PackagePortAutomationInventory(this);

  /// The buffer stack at [slot] in the conveyance value type (`ItemValue`).
  ItemValue packageValue(int slot) => packageValueOf(packages.at(slot));

  /// The buffer stack at [slot] as a logistics stack.
  LStack packageStack(int slot) => packageFrom(packageValue(slot));

  /// [stack] in the conveyance value type.
  ItemValue packageValueOf(LStack stack) =>
      stack.isEmpty ? ItemValue.empty : toItemValue(stack, Lg.i.wire);

  /// [value] as a logistics stack.
  LStack packageFrom(ItemValue value) => fromItemValue(value, Lg.i.wire);

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
    acceptsPackages = map['AcceptsPackages'] as bool? ?? true;
    addressFilter = map['AddressFilter'] as String? ?? '';
    target = PackagePortTarget.fromMap(map['Target']);
    final stacks = map['Inventory'];
    if (stacks is List) {
      for (var i = 0; i < packages.slots && i < stacks.length; i++) {
        packages.stacks[i] = stacks[i] is String
            ? _stack(stacks[i] as String)
            : LStack.empty;
      }
    }
  }

  static LStack _stack(String json) {
    try {
      return LStackMapper.fromJson(json);
    } on Object {
      return LStack.empty;
    }
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'AcceptsPackages': acceptsPackages,
    'AddressFilter': addressFilter,
    'Target': target?.toMap(),
    'Inventory': [
      for (final s in packages.stacks) s.isEmpty ? null : s.toJson(),
    ],
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final t = target;
    if (t != null) {
      tag.putCompound('Target', packagePortTargetToNbt(t));
    }
    tag
      ..putString('AddressFilter', addressFilter)
      ..putBool('AcceptsPackages', acceptsPackages)
      ..putCompound(
        'Inventory',
        itemHandlerToNbt(packages, client: clientPacket),
      );
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final targetTag = tag.getCompound('Target');
    if (targetTag != null) target = packagePortTargetFromNbt(targetTag);
    if (tag.containsKey('AddressFilter')) {
      addressFilter = tag.getString('AddressFilter') ?? '';
    }
    if (tag.containsKey('AcceptsPackages')) {
      acceptsPackages = tag.getBool('AcceptsPackages') ?? false;
    }
    final inventory = tag.getCompound('Inventory');
    if (inventory != null) itemHandlerFromNbt(inventory, packages);
  }

  /// `filterChanged()`: the target has to learn the new address filter.
  void filterChanged() {
    deregisterTarget();
    registerTarget();
  }

  /// `lazyTick()`: keep the port registered with its target (the target may have been replaced).
  @override
  void lazyTick() {
    super.lazyTick();
    registerTarget();
  }

  /// `PackagePortTarget.register`: the target blocks belong to other modules; the concrete port
  /// (`FrogportBlockEntity`, `PostboxBlockEntity`) knows which target it can talk to.
  void registerTarget() {}

  /// `PackagePortTarget.deregister`.
  void deregisterTarget() {}

  /// `getComparatorOutput()`: the fill of the eighteen package slots.
  int get comparatorOutput =>
      calcRedstoneFromInventory(packages.stacks, slotLimit: packages.limit);

  /// `drop(box)`.
  void drop(LStack box) {
    if (box.isEmpty) return;
    final w = world;
    if (w == null) return;
    unawaited(_drop(w, box));
  }

  Future<void> _drop(World w, LStack box) async {
    final stack = await Lg.i.write(box);
    if (stack != null) await w.dropItem(pos.toPos().center, stack);
  }

  /// The block key at [pos].
  String get blockKey =>
      world == null ? 'minecraft:air' : Lvl(world!).blockKey(pos.toPos());

  @override
  void onUnload() {
    deregisterTarget();
    super.onUnload();
  }

  @override
  void onRemoved() {
    deregisterTarget();
    for (final stack in packages.nonEmpty()) {
      drop(stack);
    }
    packages.clear();
    super.onRemoved();
  }
}

/// `FrogportBlockEntity`.
class FrogportBlockEntity extends PackagePortBlockEntity
    implements FrogportPuller, ChainConveyorPort {
  static const String type = 'create:package_frogport';

  double passiveYaw = 0;
  bool failedLastExport = false;

  FrogportBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => super.state;

  @override
  void readState(Map<String, dynamic> map) {
    super.readState(map);
    passiveYaw = (map['PlacedYaw'] as num?)?.toDouble() ?? 0;
    failedLastExport = map['FailedLastExport'] == true;
  }

  @override
  Map<String, dynamic> stateToMap() => {
    ...super.stateToMap(),
    'PlacedYaw': passiveYaw,
    'FailedLastExport': failedLastExport,
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putFloat('PlacedYaw', passiveYaw);
    if (failedLastExport) {
      // `NBTHelper.putMarker`: an empty compound marks a boolean flag.
      tag.putCompound('FailedLastExport', NbtCompound());
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.containsKey('PlacedYaw')) {
      passiveYaw = tag.getDouble('PlacedYaw') ?? 0;
    }
    if (tag.containsKey('FailedLastExport')) failedLastExport = true;
  }

  // -- ChainConveyorPort ----------------------------------------------------------------------

  /// The client animation is not simulated on the server; packages move immediately.
  @override
  bool get isAnimationInProgress => false;

  /// `sendAnticipate()`: a client particle effect.
  @override
  void sendAnticipate() {}

  /// `startAnimation(box, deposit: false)` from the chain: the port catches the package.
  @override
  void startAnimation(ItemValue package) {
    final box = fromItemValue(package, Lg.i.wire);
    if (box.isEmpty) return;
    if (packages.insertStackedNow(box).isNotEmpty) drop(box);
    markDirty();
  }

  ChainConveyorBlockEntity? get _chainConveyor {
    final t = target;
    if (t == null) return null;
    return store.typed<ChainConveyorBlockEntity>(
      worldId,
      (pos.toPos() + t.relativePos).toBlockPos(),
    );
  }

  /// `PackagePortTarget.ChainConveyorFrogportTarget.register`.
  @override
  void registerTarget() {
    final t = target;
    if (t == null || t.type != PackagePortTargetType.chainConveyor) return;
    final chain = _chainConveyor;
    if (chain == null) return;
    final filter = filterString;
    final offset = -t.relativePos;
    if (filter == null) {
      chain.removePort(offset);
      return;
    }
    chain.receivePortInfo(offset, t.chainPos, t.connection, filter);
  }

  @override
  void deregisterTarget() {
    final t = target;
    if (t == null || t.type != PackagePortTargetType.chainConveyor) return;
    _chainConveyor?.removePort(-t.relativePos);
  }

  /// `PackagePortTarget.export` of a chain conveyor target.
  bool _exportToTarget(LStack box, {required bool simulate}) {
    final t = target;
    if (t == null || t.type != PackagePortTargetType.chainConveyor) {
      return false;
    }
    final chain = _chainConveyor;
    if (chain == null) return false;
    final connection = t.connection;
    if (connection != null && !chain.connections.contains(connection)) {
      return false;
    }
    if (simulate) {
      return chain.speed != 0 && chain.canAcceptPackagesFor(connection);
    }
    final package = ChainConveyorPackage(
      t.chainPos,
      toItemValue(box, Lg.i.wire),
      ChainConveyorPackage.nextNetId(),
    );
    return connection == null
        ? chain.addLoopingPackage(package)
        : chain.addTravellingPackage(package, connection);
  }

  @override
  void lazyTick() {
    super.lazyTick();
    final previousFail = failedLastExport;
    _tryPushingToAdjacentInventories();
    tryPullingFromOwnAndAdjacentInventories();
    if (failedLastExport != previousFail) sendData();
  }

  /// `tryPushingToAdjacentInventories()`: packages in the port move into the inventory below.
  void _tryPushingToAdjacentInventories() {
    if (packages.nonEmpty().isEmpty) return;
    failedLastExport = false;
    final below = pos.toPos().below;

    // A packager below exposes its tray as an inventory: inserting a package unpacks it.
    final belowBe = store.at(worldId, below.toBlockPos());
    if (belowBe is PackagerBlockEntity) {
      for (var slot = 0; slot < packages.slots; slot++) {
        if (packages.at(slot).isEmpty) continue;
        unawaited(_pushIntoPackager(belowBe, slot));
      }
      return;
    }

    final inv = inventoryAt(
      worldId,
      below,
      Lg.i.io,
      side: Direction.up,
    );
    if (inv == null) return;
    for (var slot = 0; slot < packages.slots; slot++) {
      final stack = packages.at(slot);
      if (stack.isEmpty) continue;
      unawaited(_pushOne(inv, slot));
    }
  }

  /// `PackagerItemHandler.insertItem`: the packager takes the package and unpacks it.
  Future<void> _pushIntoPackager(PackagerBlockEntity packager, int slot) async {
    final box = packages.at(slot);
    if (box.isEmpty) return;
    if (packager.heldBox.isNotEmpty ||
        packager.queuedExitingPackages.isNotEmpty ||
        packager.animationTicks != 0) {
      failedLastExport = true;
      return;
    }
    if (!await packager.unwrapBox(box, simulate: true)) {
      failedLastExport = true;
      return;
    }
    if (!await packager.unwrapBox(box, simulate: false)) {
      failedLastExport = true;
      return;
    }
    packages.extractNow(slot, 1);
    markDirty();
    await packager.triggerStockCheck();
  }

  Future<void> _pushOne(ItemInv target, int slot) async {
    final stack = packages.extractNow(slot, 1, simulate: true);
    if (stack.isEmpty) return;
    final remainder = await insertStacked(target, stack);
    if (remainder.isEmpty) {
      packages.extractNow(slot, 1);
      markDirty();
    } else {
      failedLastExport = true;
    }
  }

  /// `tryPullingFromOwnAndAdjacentInventories()`.
  @override
  void tryPullingFromOwnAndAdjacentInventories() => unawaited(_pull());

  Future<void> _pull() async {
    if (target == null) return;
    // `tryPullingFromOwnAndAdjacentInventories`: only pull when the target can take a package.
    if (!_exportToTarget(PackageStyles.defaultBox(), simulate: true)) return;
    if (await _tryPullingFrom(packages)) return;

    // The packager below exposes its held box through its capability in Java; plugin block
    // entities have no item handler here, so the box is taken from the block entity directly.
    final below = store.typed<PackagerBlockEntity>(
      worldId,
      pos.toPos().below.toBlockPos(),
    );
    if (below != null && below.heldBox.isNotEmpty) {
      if (packages.nonEmpty().length < packages.slots) {
        final box = below.heldBox;
        below.heldBox = LStack.empty;
        below.notifyUpdate();
        startAnimationFor(box, deposit: true);
        return;
      }
    }

    final inv = inventoryAt(
      worldId,
      pos.toPos().below,
      Lg.i.io,
      side: Direction.up,
    );
    if (inv == null) return;
    await _tryPullingFrom(inv);
  }

  /// `tryPullingFrom(handler)`.
  Future<bool> _tryPullingFrom(ItemInv handler) async {
    final filter = filterString;
    for (var slot = 0; slot < handler.slots; slot++) {
      final stack = await handler.stackAt(slot);
      if (stack.isEmpty || !PackageItem.isPackage(stack)) continue;
      if (filter != null && PackageItem.matchBoxAddress(stack, filter))
        continue;
      final taken = await handler.extract(slot, 1);
      if (taken.isEmpty) continue;
      startAnimationFor(taken, deposit: true);
      return true;
    }
    return false;
  }

  /// `startAnimation(box, deposit)`; the client animation is skipped, the transfer is immediate.
  void startAnimationFor(LStack box, {required bool deposit}) {
    if (!PackageItem.isPackage(box)) return;
    if (deposit) {
      _deposit(box);
      return;
    }
    if (packages.insertStackedNow(box).isNotEmpty) drop(box);
  }

  void _deposit(LStack box) {
    if (!_exportToTarget(box, simulate: false)) drop(box);
  }
}

/// `PostboxBlockEntity`: a package port with an 18 slot buffer, used by train stations.
class PostboxBlockEntity extends PackagePortBlockEntity {
  static const String type = 'create:package_postbox';

  bool forceFlag = false;

  /// `sendParticles`: the client-only `Particles` marker of the update tag.
  bool sendParticles = false;

  PostboxBlockEntity(super.worldId, super.pos);

  /// `spawnParticles()`.
  void spawnParticles() => sendParticles = true;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket && sendParticles) {
      tag.putCompound('Particles', NbtCompound());
    }
    sendParticles = false;
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    sendParticles = clientPacket && tag.containsKey('Particles');
  }

  /// `onOpenChange(open)`.
  void onOpenChange(bool open) {
    final w = world;
    if (w == null) return;
    final info = Lvl(w).info(pos.toPos());
    if (info == null || !info.key.contains('_postbox')) return;
    unawaited(
      Lvl(w).setProps(pos.toPos(), {
        'open': open ? 'true' : 'false',
      }, neighbors: true),
    );
  }
}

/// `PackagePortAutomationInventoryWrapper`: what a hopper (or another plugin inventory) sees of
/// the port's buffer.
final class _PackagePortAutomationInventory implements ItemInventory {
  final PackagePortBlockEntity be;

  _PackagePortAutomationInventory(this.be);

  MemoryInv get _buffer => be.packages;

  @override
  int get slots => _buffer.slots;

  @override
  ItemValue getStack(int slot) => be.packageValue(slot);

  @override
  int slotLimit(int slot) => _buffer.limit;

  @override
  bool isItemValid(int slot, ItemValue stack) =>
      _buffer.validator?.call(slot, be.packageFrom(stack)) ?? true;

  @override
  ItemValue insert(int slot, ItemValue stack, {bool simulate = false}) {
    if (!PackageItem.isPackage(be.packageFrom(stack))) return stack;
    final filter = be.filterString;
    if (filter != null && PackageItem.matchBoxAddress(be.packageFrom(stack), filter)) {
      return stack;
    }
    return be.packageValueOf(
      _buffer.insertNow(slot, be.packageFrom(stack), simulate: simulate),
    );
  }

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    // `super.extractItem(slot, 64, true)`: only a whole box is ever offered.
    final preview = _buffer.at(slot);
    if (!PackageItem.isPackage(preview)) return ItemValue.empty;
    final filter = be.filterString;
    if (filter == null || !PackageItem.matchBoxAddress(preview, filter)) {
      return ItemValue.empty;
    }
    final taken = _buffer.extractNow(slot, amount, simulate: simulate);
    return be.packageValueOf(taken);
  }
}

// `PackagePortBlockEntity`, `FrogportBlockEntity` and `PostboxBlockEntity`: the ports that accept
// packages and forward them to their target (a chain conveyor or a train station).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/equipment.dart' show addClipboardAddress;
import '../../api/util.dart' hide pos;
import '../../conveyance/chain/chain_conveyor_block_entity.dart';
import '../../conveyance/chain/chain_conveyor_logic.dart';
import '../../conveyance/chain/chain_conveyor_port.dart';
import '../../conveyance/items/inventory.dart' hide insertStacked;
import '../../conveyance/items/item_data.dart';
import '../../conveyance/transport/transport_inventory_api.dart'
    show ItemInventoryProvider;
import '../../common/host_bridge.dart';
import '../../trains/station/station_block_entity.dart';
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
import 'package_port_menu.dart';
import 'package_port_target.dart';
import 'station_ports.dart';

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

  /// The players that have the port's screen open (`PackagePortMenu`).
  final Set<String> openViewers = {};

  final Map<String, dynamic> _state = {};

  PackagePortBlockEntity(super.worldId, super.pos) {
    // `SmartInventory` calls `setChanged` after a change; the port saves (and the postbox copies
    // its buffer into the station's offline buffer).
    packages.onChanged = (_) => markDirty();
  }

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

  /// `PackagePortTarget.register`: a train station target adds the port to the station's
  /// `connectedPorts`; a chain conveyor target is handled by the frogport itself.
  void registerTarget() {
    _stationTarget()?.attachPackagePort(this);
  }

  /// `PackagePortTarget.deregister`.
  void deregisterTarget() {
    _stationTarget()?.removePackagePort(this);
  }

  /// The station this port sends to, when its target is a train station.
  StationBlockEntity? _stationTarget() {
    final t = target;
    if (t == null || t.type != PackagePortTargetType.trainStation) return null;
    return store.typed<StationBlockEntity>(
      worldId,
      (pos.toPos() + t.relativePos).toBlockPos(),
    );
  }

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

  /// `use(player)`: a clipboard takes the address, otherwise the port opens its screen. Returns
  /// false when the click is passed on to the held item.
  Future<bool> use(Player player) async {
    if (player.asEntity().isSneaking()) return false;

    // `PackagePortBlockEntity.use` (`PackagePortBlockEntity.java:148-176`): a clipboard in the main
    // hand gets the port's address as a `#address` entry instead of opening the screen.
    final inventory = player.getInventory();
    try {
      final held = inventory.getItemInHand(hand: Hand.right);
      if (held != null) {
        final stack = await Lg.i.read(held);
        if (stack.key == 'create:clipboard') {
          final address = addressFilter;
          if (address.trim().isNotEmpty &&
              addClipboardAddress(held, address)) {
            await inventory.setItemInHand(hand: Hand.right, item: held);
            player.showActionbar(
              text: TextComponent.translate(
                key: 'create.clipboard.address_added',
                with_: [TextComponent.text(plain: address)],
              ),
            );
          }
          return true;
        }
      }
    } finally {
      inventory.dispose();
    }

    if (!await PackagePortMenus.open(player, this)) return false;
    onOpenedManually();
    return true;
  }

  /// `onOpenedManually()`: the frogport plays its opening animation on the client.
  void onOpenedManually() {}

  /// `onOpenChange(open)`: the postbox opens its lid, the frogport does nothing.
  void onOpenChange(bool open) {}

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
    var t = target;
    if (t == null || t.type != PackagePortTargetType.chainConveyor) return;
    var chain = _chainConveyor;
    if (chain == null) return;

    // Jump to opposite chain if motion reversed (`PackagePortTarget.java:132-149`). The target
    // moves to the conveyor on the other end of the connection, mirrored along the chain.
    final connection = t.connection;
    if (connection != null && (chain.speed < 0) != t.flipped) {
      deregisterTarget();
      final otherPos = pos.toPos() + t.relativePos + connection;
      final other = store.typed<ChainConveyorBlockEntity>(
        worldId,
        otherPos.toBlockPos(),
      );
      if (other == null) return;
      chain.prepareStats();
      final stats = chain.connectionStats?[connection];
      t = t.copyWith(
        relativePos: otherPos - pos.toPos(),
        chainPos: stats == null ? t.chainPos : stats.chainLength - t.chainPos,
        connection: -connection,
        flipped: !t.flipped,
      );
      target = t;
      chain = other;
      sendData();
    }

    final flippedConnection = t.connection;
    if (flippedConnection != null &&
        !chain.connections.contains(flippedConnection)) {
      return;
    }
    final filter = filterString;
    if (filter == null) return;
    chain.receivePortInfo(-t.relativePos, t.chainPos, flippedConnection, filter);
  }

  @override
  void deregisterTarget() {
    final t = target;
    if (t == null || t.type != PackagePortTargetType.chainConveyor) return;
    _chainConveyor?.removePort(-t.relativePos, filter: filterString);
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
    unawaited(_tryPushingToAdjacentInventories());
    tryPullingFromOwnAndAdjacentInventories();
    if (failedLastExport != previousFail) sendData();
  }

  /// `tryPushingToAdjacentInventories()`: boxes the port does not want move into the inventory
  /// below.
  Future<void> _tryPushingToAdjacentInventories() async {
    // Java clears the flag before it looks at the buffer, so a port that emptied its buffer stops
    // reporting the previous failure.
    failedLastExport = false;
    if (packages.nonEmpty().isEmpty) return;

    final inv = _adjacentInventory(Direction.down);
    if (inv == null) return;

    for (var slot = 0; slot < packages.slots; slot++) {
      // The automation view (`PackagePortAutomationInventoryWrapper`) only offers boxes the port
      // does not want; a box it is waiting for stays in the buffer.
      final box = packageFrom(
        await _automation.extract(slot, 1, simulate: true),
      );
      if (box.isEmpty) continue;
      unawaited(_pushOne(inv, slot, box));
    }
  }

  /// `getAdjacentInventory(side)`: the inventory next to the port, never another frogport (two
  /// frogports would hand a box back and forth).
  ItemInv? _adjacentInventory(Direction side) {
    final p = pos.toPos().relative(side);
    final be = store.at(worldId, p.toBlockPos());
    if (be == null || be is FrogportBlockEntity) return null;
    return inventoryAt(worldId, p, Lg.i.io, side: side.opposite);
  }

  Future<void> _pushOne(ItemInv target, int slot, LStack box) async {
    final remainder = await insertStacked(target, box);
    if (remainder.isNotEmpty) {
      failedLastExport = true;
      return;
    }
    _automation.extract(slot, 1);
    markDirty();
  }

  /// `tryPullingFromOwnAndAdjacentInventories()`.
  @override
  void tryPullingFromOwnAndAdjacentInventories() => unawaited(_pull());

  Future<void> _pull() async {
    if (isAnimationInProgress) return;
    if (target == null) return;
    // `tryPullingFromOwnAndAdjacentInventories`: only pull when the target can take a package.
    if (!_exportToTarget(PackageStyles.defaultBox(), simulate: true)) return;
    if (await _tryPullingFrom(packages)) return;

    final below = _adjacentInventory(Direction.down);
    if (below == null) return;
    final belowBe = store.at(worldId, pos.toPos().below.toBlockPos());
    await _tryPullingFrom(below, isPackager: belowBe is PackagerBlockEntity);
  }

  /// `tryPullingFrom(handler)`: takes the first box the port wants out of [handler].
  Future<bool> _tryPullingFrom(ItemInv handler, {bool isPackager = false}) async {
    final filter = filterString;
    for (var slot = 0; slot < handler.slots; slot++) {
      final stack = await handler.stackAt(slot);
      if (stack.isEmpty || !PackageItem.isPackage(stack)) continue;
      // A packager's tray hands out the box it finished, which is not subject to the port's
      // address filter.
      if (filter != null &&
          !isPackager &&
          PackageItem.matchBoxAddress(stack, filter)) {
        continue;
      }
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

  /// `trackedGlobalStation`: the station whose `connectedPorts` this postbox is in. A station keeps
  /// its postboxes' contents in an offline buffer, so mail survives an unloaded chunk; the link
  /// back is only used to write that buffer. Java keeps a `WeakReference`, a plain field is enough
  /// here because a station is dropped with its world.
  Object? trackedStation;

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

  /// `setChanged()`: every change of the buffer is copied into the station's offline buffer.
  @override
  void markDirty() {
    saveOfflineBuffer();
    super.markDirty();
  }

  /// `saveOfflineBuffer()`: the station keeps a copy of the buffer for while the chunk is unloaded.
  void saveOfflineBuffer() => savePostboxOfflineBuffer(this);

  /// `onOpenChange(open)`: the barrel lid of the postbox and its sounds.
  void onOpenChange(bool open) {
    final w = world;
    if (w == null) return;
    final info = Lvl(w).info(pos.toPos());
    // A cached block state can be stale after the block was blown up; the property is only set on
    // a postbox.
    if (info == null || !info.key.endsWith('_postbox')) return;
    unawaited(
      Lvl(w).setProps(pos.toPos(), {
        'open': open ? 'true' : 'false',
      }, neighbors: true),
    );
    w.playSound(
      sound: open ? Sound.blockBarrelOpen : Sound.blockBarrelClose,
      category: SoundCategory.blocks,
      pos: pos.toPos().center,
      volume: 1,
      pitch: 1,
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

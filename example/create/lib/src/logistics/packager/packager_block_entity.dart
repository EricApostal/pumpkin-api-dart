// `PackagerBlockEntity`: extracts items from the inventory behind its facing and wraps them into
// packages, and unpacks packages inserted by a player into that inventory.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../factory/factory_panel_block_entity.dart';
import '../host/host_inventory.dart';
import '../host/lg_block_entity.dart';
import '../host/lvl.dart';
import '../host/nbt_codecs.dart';
import '../host/nbt_util.dart';
import '../host/runtime.dart';
import '../host/state_props.dart';
import '../link/packager_link_block_entity.dart';
import '../model/inventory.dart';
import '../model/manager.dart';
import '../model/network.dart';
import '../model/orders.dart';
import '../model/package.dart';
import '../model/stack.dart';
import '../port/package_port_block_entity.dart';
import 'unpacking.dart';

/// `AllInventoryIdentifiers`: which inventory a packager faces, so two packagers on the same
/// inventory do not request items from each other.
abstract final class InventoryIdentifiers {
  /// The identifier of the inventory at [pos] seen from [face]. Falls back to the single block.
  static InventoryIdentifier identifierAt(
    String worldId,
    Pos pos,
    Direction face,
  ) {
    final world = Lg.i.world(worldId);
    if (world == null) return SingleInventoryId(pos);
    final info = Lvl(world).info(pos);
    final key = info?.key ?? 'minecraft:air';
    final props = info?.properties ?? const <String, String>{};

    // Double chests: a chest with a `type` and a `facing` property pairs with its neighbour.
    if (props.containsKey('type') && props.containsKey('facing')) {
      final type = props['type'];
      final facing =
          Direction.byName(props['facing'] ?? 'north') ?? Direction.north;
      if (type == 'left' || type == 'right') {
        // `ChestBlock.getConnectedDirection`: left -> counter clockwise, right -> clockwise.
        final other = pos.relative(
          type == 'left' ? facing.counterClockWise : facing.clockWise,
        );
        final otherInfo = Lvl(world).info(other);
        if (otherInfo?.key == key) return PairInventoryId(pos, other);
      }
    }
    return SingleInventoryId(pos);
  }
}

/// `PackagerBlockEntity`. The animation of the tray is visual only and skipped.
class PackagerBlockEntity extends LgBlockEntity implements PackagerHandle {
  static const String type = 'create:packager';

  /// `CYCLE`: ticks of the tray animation.
  static const int cycle = 20;

  bool redstonePowered = false;
  int buttonCooldown = 0;
  String signBasedAddress = '';

  /// `customComputerAddress` / `hasCustomComputerAddress` (ComputerCraft). There is no
  /// ComputerCraft bridge in this port, but Java persists the keys and a client reads them.
  String customComputerAddress = '';
  bool hasCustomComputerAddress = false;

  LStack heldBox = LStack.empty;
  LStack previouslyUnwrapped = LStack.empty;
  List<BigStack> queuedExitingPackages = [];

  int animationTicks = 0;
  bool animationInward = true;

  /// `availableItems`, cached for one tick (`getAvailableItems`).
  InventorySummary? _available;
  int _availableTick = -1;

  final Map<String, dynamic> _state = {};

  PackagerBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => _state;

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
    // The keys are the Java NBT names (the values stay JSON in the private `State`).
    redstonePowered = map['Active'] as bool? ?? false;
    buttonCooldown = map['ButtonCooldown'] as int? ?? 0;
    signBasedAddress = map['SignAddress'] as String? ?? '';
    customComputerAddress = map['ComputerAddress'] as String? ?? '';
    hasCustomComputerAddress = map['HasComputerAddress'] as bool? ?? false;
    heldBox = _stack(map['HeldBox']);
    previouslyUnwrapped = _stack(map['InsertedBox']);
    queuedExitingPackages = [
      for (final e
          in (map['QueuedExitingPackages'] as List<dynamic>? ?? const []))
        if (e is Map)
          BigStack(_stack(e['item_stack']), e['count'] as int? ?? 1),
    ];
    animationTicks = map['AnimationTicks'] as int? ?? 0;
    animationInward = map['AnimationInward'] as bool? ?? true;
  }

  static LStack _stack(Object? value) {
    if (value is! String) return LStack.empty;
    try {
      return LStackMapper.fromJson(value);
    } on Object {
      return LStack.empty;
    }
  }

  static String? _stackJson(LStack stack) =>
      stack.isEmpty ? null : stack.toJson();

  @override
  Map<String, dynamic> stateToMap() => {
    'Active': redstonePowered,
    // Java does not persist the button cooldown; it is kept so a reload does not reopen the tray.
    'ButtonCooldown': buttonCooldown,
    'SignAddress': signBasedAddress,
    'ComputerAddress': customComputerAddress,
    'HasComputerAddress': hasCustomComputerAddress,
    'HeldBox': _stackJson(heldBox),
    'InsertedBox': _stackJson(previouslyUnwrapped),
    'QueuedExitingPackages': [
      for (final b in queuedExitingPackages)
        {'item_stack': b.stack.toJson(), 'count': b.count},
    ],
    'AnimationTicks': animationTicks,
    'AnimationInward': animationInward,
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag
      ..putBool('Active', redstonePowered)
      ..putBool('AnimationInward', animationInward)
      ..putInt('AnimationTicks', animationTicks)
      ..putString('SignAddress', signBasedAddress)
      ..putString('ComputerAddress', customComputerAddress)
      ..putBool('HasComputerAddress', hasCustomComputerAddress)
      ..putCompound('HeldBox', stackToNbt(heldBox, client: clientPacket))
      ..putCompound(
        'InsertedBox',
        stackToNbt(previouslyUnwrapped, client: clientPacket),
      );
    if (clientPacket) return;
    tag.putList(
      'QueuedExitingPackages',
      bigStacksToNbt(queuedExitingPackages, client: false),
    );
    final available = _available;
    if (available != null) {
      tag.putList(
        'LastSummary',
        bigStacksToNbt(available.getStacks(), client: false),
      );
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.containsKey('Active')) {
      redstonePowered = tag.getBool('Active') ?? false;
    }
    if (tag.containsKey('AnimationInward')) {
      animationInward = tag.getBool('AnimationInward') ?? false;
    }
    if (tag.containsKey('AnimationTicks')) {
      animationTicks = tag.getInt('AnimationTicks') ?? 0;
    }
    if (tag.containsKey('SignAddress')) {
      signBasedAddress = tag.getString('SignAddress') ?? '';
    }
    if (tag.containsKey('ComputerAddress')) {
      customComputerAddress = tag.getString('ComputerAddress') ?? '';
    }
    if (tag.containsKey('HasComputerAddress')) {
      hasCustomComputerAddress = tag.getBool('HasComputerAddress') ?? false;
    }
    if (tag.containsKey('HeldBox')) {
      heldBox = stackFromNbt(tag.getCompound('HeldBox'));
    }
    if (tag.containsKey('InsertedBox')) {
      previouslyUnwrapped = stackFromNbt(tag.getCompound('InsertedBox'));
    }
    if (clientPacket) return;
    if (tag.containsKey('QueuedExitingPackages')) {
      queuedExitingPackages = bigStacksFromNbt(
        tag.getList('QueuedExitingPackages'),
      );
    }
    if (tag.containsKey('LastSummary')) {
      _available = InventorySummary.fromList(
        bigStacksFromNbt(tag.getList('LastSummary')),
      );
      _availableTick = Lg.loaded ? Lg.i.tick : 0;
    }
  }

  Lvl? get _lvl => world == null ? null : Lvl(world!);

  /// This block entity's position as a [Pos].
  Pos get _pos => pos.toPos();

  /// The `facing` property of the block.
  Direction get facing {
    final info = _lvl?.info(_pos);
    return Direction.byName(info?.properties['facing'] ?? 'north') ??
        Direction.north;
  }

  /// The position of the inventory this packager works with.
  Pos get targetPos => _pos.relative(facing.opposite);

  /// `targetInventory.getInventory()`.
  ItemInv? get targetInventory {
    final w = world;
    if (w == null) return null;
    return hostInvAt(w, targetPos.toBlockPos(), Lg.i.io, side: facing.toHost());
  }

  /// `getIdentifiedInventory()`.
  IdentifiedInventory? get identifiedInventory {
    final inv = targetInventory;
    if (inv == null) return null;
    return IdentifiedInventory(
      InventoryIdentifiers.identifierAt(worldId, targetPos, facing),
      inv,
    );
  }

  @override
  void initialize() {
    super.initialize();
    recheckIfLinksPresent();
  }

  @override
  void tick() {
    super.tick();
    if (buttonCooldown > 0) buttonCooldown--;

    if (animationTicks == 0) {
      previouslyUnwrapped = LStack.empty;
      if (!queuedExitingPackages.isEmpty && heldBox.isEmpty) {
        final entry = queuedExitingPackages.first;
        heldBox = entry.stack;
        entry.count--;
        if (entry.count <= 0) queuedExitingPackages.removeAt(0);
        animationInward = false;
        animationTicks = cycle;
        notifyUpdate();
      }
      return;
    }

    animationTicks--;
    if (animationTicks == 0) {
      _wakeTheFrogs();
      markDirty();
    }
  }

  @override
  void lazyTick() {
    super.lazyTick();
    recheckIfLinksPresent();
    if (!redstonePowered) return;
    redstonePowered = _lvl?.info(_pos)?.properties['powered'] == 'true';
    if (!redstoneModeActive) return;
    updateSignAddress();
    unawaited(attemptToSend(null));
  }

  /// `recheckIfLinksPresent()`: the `linked` state follows whether a stock link is attached.
  void recheckIfLinksPresent() {
    final lvl = _lvl;
    if (lvl == null) return;
    final info = lvl.info(_pos);
    if (info == null || !info.properties.containsKey('linked')) return;
    final shouldBeLinked = linkPos != null;
    final isLinked = info.properties['linked'] == 'true';
    if (shouldBeLinked == isLinked) return;
    lvl.setProps(_pos, {
      'linked': shouldBeLinked ? 'true' : 'false',
    }, neighbors: true);
  }

  /// `redstoneModeActive()`: a linked packager ignores redstone.
  bool get redstoneModeActive =>
      _lvl?.info(_pos)?.properties['linked'] != 'true';

  /// The adjacent stock link (`getLinkPos`), or `null`.
  Pos? get linkPos {
    final lvl = _lvl;
    if (lvl == null) return null;
    for (final d in Direction.values) {
      final p = _pos.relative(d);
      final info = lvl.info(p);
      if (info == null || info.key != 'create:stock_link') continue;
      if (faceConnectedDirection(info.properties) != d) continue;
      return p;
    }
    return null;
  }

  /// `flashLink()`: sends the stock link's Wi-Fi effect to the players that track the link.
  @override
  void flashLink() {
    final link = linkPos;
    final world = this.world;
    if (link == null || world == null) return;
    Lg.i.bus.sendToTracking(
      'create:packager_link_effect',
      world,
      link.toBlockPos(),
      {'pos': link.toBlockPos()},
    );
  }

  @override
  bool isTooBusyFor(RequestType type) {
    final queue = queuedExitingPackages.length;
    return queue >=
        switch (type) {
          RequestType.player => 50,
          RequestType.redstone => 20,
          RequestType.restock => 10,
        };
  }

  /// `activate()`: a rising redstone edge sends one package.
  void activate() {
    redstonePowered = true;
    markDirty();
    recheckIfLinksPresent();
    if (!redstoneModeActive) return;
    updateSignAddress();
    unawaited(attemptToSend(null));
    if (buttonCooldown <= 0) buttonCooldown = 40;
  }

  /// `unwrapBox(box, simulate)`: unpack into the inventory behind the packager.
  Future<bool> unwrapBox(LStack box, {required bool simulate}) async {
    if (animationTicks > 0) return false;

    final items = PackageItem.contentsList(box);
    if (items.isEmpty) return true;

    final targetState = _lvl?.info(targetPos);
    final handler = UnpackingHandlers.of(targetState?.key ?? 'minecraft:air');
    final inv = targetInventory;
    if (inv == null) return false;

    final unpacked = await handler.unpack(inv, items, simulate: simulate);
    if (unpacked && !simulate) {
      previouslyUnwrapped = box;
      animationInward = true;
      animationTicks = cycle;
      notifyUpdate();
    }
    return unpacked;
  }

  /// `attemptToSend(queuedRequests)`.
  @override
  Future<void> attemptToSend(List<PackagingRequest>? queuedRequests) async {
    if (queuedRequests == null &&
        (heldBox.isNotEmpty || animationTicks != 0 || buttonCooldown > 0)) {
      return;
    }
    if (queuedRequests != null && queuedRequests.isEmpty) return;

    final targetInv = targetInventory;
    if (targetInv == null) return;

    var anyItemPresent = false;
    final extractedItems = MemoryInv(PackageItem.slots);
    var extractedPackageItem = LStack.empty;
    PackagingRequest? nextRequest;
    String? fixedAddress;
    var fixedOrderId = 0;

    var linkIndexInOrder = 0;
    var finalLinkInOrder = false;
    var packageIndexAtLink = 0;
    var finalPackageAtLink = false;
    PackageOrderWithCrafts? orderContext;
    final requestQueue = queuedRequests != null;

    if (requestQueue && queuedRequests.isNotEmpty) {
      nextRequest = queuedRequests.first;
      fixedAddress = nextRequest.address;
      fixedOrderId = nextRequest.orderId;
      linkIndexInOrder = nextRequest.linkIndex;
      finalLinkInOrder = nextRequest.finalLink.value;
      packageIndexAtLink = nextRequest.packageCounter.getAndIncrement();
      orderContext = nextRequest.context;
    }

    outer:
    for (var i = 0; i < PackageItem.slots; i++) {
      var continuePacking = true;

      while (continuePacking) {
        continuePacking = false;

        for (var slot = 0; slot < targetInv.slots; slot++) {
          final request = nextRequest;
          final initialCount = requestQueue && request != null
              ? min(64, request.count)
              : 64;
          final extracted = await targetInv.extract(
            slot,
            initialCount,
            simulate: true,
          );
          if (extracted.isEmpty) continue;
          if (requestQueue &&
              request != null &&
              !extracted.sameItemSameComponents(request.item))
            continue;

          final bulky = PackageItem.isPackage(extracted);
          if (bulky && anyItemPresent) continue;

          anyItemPresent = true;
          final leftovers = extractedItems.insertStackedNow(extracted);
          final transferred = extracted.count - leftovers.count;
          await targetInv.extract(slot, transferred);

          if (PackageItem.isPackage(extracted))
            extractedPackageItem = extracted;

          if (!requestQueue) {
            if (bulky) break outer;
            continue;
          }

          request!.subtract(transferred);

          if (request.count > 0) {
            if (bulky) break outer;
            continue;
          }

          finalPackageAtLink = true;
          queuedRequests.removeAt(0);
          if (queuedRequests.isEmpty) break outer;
          final previousCount = request.packageCounter.value;
          nextRequest = queuedRequests.first;
          if (fixedAddress != nextRequest.address) break outer;
          if (fixedOrderId != nextRequest.orderId) break outer;

          nextRequest.packageCounter.value = previousCount;
          finalPackageAtLink = false;
          continuePacking = true;
          if (nextRequest.context != null) orderContext = nextRequest.context;

          if (bulky) break outer;
          break;
        }
      }
    }

    if (!anyItemPresent) {
      if (nextRequest != null) queuedRequests?.removeAt(0);
      return;
    }

    var createdBox = extractedPackageItem.isEmpty
        ? PackageItem.containing(extractedItems)
        : extractedPackageItem;
    createdBox = PackageItem.clearAddress(createdBox);

    if (fixedAddress != null)
      createdBox = PackageItem.addAddress(createdBox, fixedAddress);
    if (requestQueue) {
      createdBox = PackageItem.setOrder(
        createdBox,
        fixedOrderId,
        linkIndexInOrder,
        finalLinkInOrder,
        packageIndexAtLink,
        finalPackageAtLink,
        orderContext,
      );
    }
    if (!requestQueue && signBasedAddress.trim().isNotEmpty) {
      createdBox = PackageItem.addAddress(createdBox, signBasedAddress);
    }

    final linkPos = this.linkPos;
    if (extractedPackageItem.isEmpty && linkPos != null) {
      final link = store.typed<PackagerLinkBlockEntity>(
        worldId,
        linkPos.toBlockPos(),
      );
      link?.behaviour.deductFromAccurateSummary(extractedItems.stacks);
    }

    if (heldBox.isNotEmpty || animationTicks != 0) {
      queuedExitingPackages.add(BigStack(createdBox, 1));
      markDirty();
      return;
    }

    heldBox = createdBox;
    animationInward = false;
    animationTicks = cycle;
    triggerStockCheck();
    notifyUpdate();
  }

  /// `updateSignAddress()`: signs are read through a block entity the host does not expose, so
  /// the address stays empty.
  void updateSignAddress() {}

  void _wakeTheFrogs() {
    final above = store.typed<FrogportBlockEntity>(
      worldId,
      _pos.above.toBlockPos(),
    );
    above?.tryPullingFromOwnAndAdjacentInventories();
  }

  /// `triggerStockCheck()`.
  @override
  Future<void> triggerStockCheck() {
    _availableTick = -1;
    return getAvailableItems();
  }

  /// `getAvailableItems()`: a summary of the inventory behind the packager.
  Future<InventorySummary> getAvailableItems() async {
    final now = Lg.i.tick;
    if (_available != null && now - _availableTick < 1) return _available!;

    final available = InventorySummary();
    final inv = targetInventory;
    if (inv == null) {
      _available = available;
      _availableTick = now;
      return available;
    }

    for (var slot = 0; slot < inv.slots; slot++) {
      available.addStack(await inv.stackAt(slot));
    }

    final before = _available;
    _available = available;
    _availableTick = now;
    if (before != null) await _submitNewArrivals(before, available);
    return available;
  }

  /// `submitNewArrivals(before, after)`: promise queues of adjacent restockers and links hear
  /// about items that arrived since the last check.
  Future<void> _submitNewArrivals(
    InventorySummary before,
    InventorySummary after,
  ) async {
    if (after.isEmpty) return;
    final queues = <RequestPromiseQueue>{};

    for (final d in Direction.values) {
      final p = _pos.relative(d);
      final info = _lvl?.info(p);
      if (info == null) continue;

      if (info.key == 'create:factory_gauge') {
        if (faceConnectedDirection(info.properties) != d) continue;
        final fpbe = store.typed<FactoryPanelBlockEntity>(
          worldId,
          p.toBlockPos(),
        );
        if (fpbe == null || !fpbe.restocker) continue;
        for (final behaviour in fpbe.panels.values) {
          if (!behaviour.isActive) continue;
          queues.add(behaviour.restockerPromises);
        }
      }

      if (info.key == 'create:stock_link') {
        if (faceConnectedDirection(info.properties) != d) continue;
        final plbe = store.typed<PackagerLinkBlockEntity>(
          worldId,
          p.toBlockPos(),
        );
        if (plbe == null) continue;
        final queue = Lg.i.global.getQueuedPromises(plbe.behaviour.freqId);
        if (queue != null) queues.add(queue);
      }
    }

    if (queues.isEmpty) return;

    for (final entry in after.getStacks()) {
      before.add(entry.stack, -entry.count);
    }
    for (final queue in queues) {
      for (final entry in before.getStacks()) {
        if (entry.count < 0) queue.itemEnteredSystem(entry.stack, -entry.count);
      }
    }
  }

  /// `isTargetingSameInventory(inventory)`.
  bool isTargetingSameInventory(IdentifiedInventory? inventory) {
    if (inventory == null) return false;
    final inv = targetInventory;
    if (inv == null) return false;
    if (inventory.identifier != null)
      return inventory.identifier!.contains((targetPos, facing));
    return identical(inv, inventory.handler);
  }

  @override
  void notifyUpdate() => sendData();

  @override
  void onRemoved() {
    super.onRemoved();
    final w = world;
    if (w != null) unawaited(_dropContents(w));
  }

  Future<void> _dropContents(World w) async {
    final held = await Lg.i.write(heldBox);
    if (held != null) await w.dropItem(_pos.center, held);
    for (final entry in queuedExitingPackages) {
      for (var i = 0; i < entry.count; i++) {
        final stack = await Lg.i.write(entry.stack);
        if (stack != null) await w.dropItem(_pos.center, stack);
      }
    }
    queuedExitingPackages.clear();
  }
}

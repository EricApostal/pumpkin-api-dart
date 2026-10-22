// `PackagerBlockEntity`: extracts items from the inventory behind its facing and wraps them into
// packages, and unpacks packages inserted by a player into that inventory.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../api/util.dart' hide pos;
import '../../common/bounds.dart';
import '../../conveyance/items/inventory.dart' show ItemInventory;
import '../../conveyance/items/item_data.dart';
import '../../conveyance/transport/crate/creative_crate_block_entity.dart'
    show CreativeCrateBlockEntity;
import '../../conveyance/transport/vault/item_vault_block_entity.dart'
    show ItemVaultBlockEntity;
import '../../conveyance/transport/hatch/item_hatch_logic.dart'
    show canFitInsideContainerItems;
import '../../conveyance/transport/transport_inventory_api.dart'
    show ItemInventoryProvider;
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
import '../port/conveyance_items.dart';
import '../port/package_port_block_entity.dart';
import 'unpacking.dart';
import 'unpacking_host.dart';

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

    // Vaults: every part of the multiblock names the whole box, so two packagers on the same
    // vault do not each report its contents.
    if (key == 'create:item_vault') {
      final bounds = PackagerBlockEntity.vaultBounds(worldId, pos);
      if (bounds != null) return BoundsInventoryId(bounds);
    }

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
class PackagerBlockEntity extends LgBlockEntity
    implements PackagerHandle, ItemInventoryProvider {
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

  /// `availableItems`: the last summary, valid while the inventory's version is unchanged
  /// (`invVersionTracker.stillWaiting`).
  InventorySummary? _available;
  final VersionTracker _invVersionTracker = VersionTracker();

  final Map<String, dynamic> _state = {};

  /// `AdvancementBehaviour(this, AllAdvancements.PACKAGER)`: the player that placed the packager
  /// gets the advancement when it sends its first package.
  late final AdvancementBehaviour advancements;

  PackagerBlockEntity(super.worldId, super.pos) {
    advancements = addBehaviour(
      AdvancementBehaviour(
        [AllAdvancements.packager],
        () => Lg.i.advancements,
      ),
    );
  }

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
  ItemInv? get targetInventory => inventoryAt(
    worldId,
    targetPos,
    Lg.i.io,
    side: facing,
  );

  /// `PackagerItemHandler`: the tray seen as a one-slot inventory. A package inserted into it
  /// is unpacked into the inventory behind the packager; the box it currently holds can be
  /// taken out again.
  @override
  ItemInventory? itemInventory(Direction? side) => _tray ??= _PackagerInventory(this);

  _PackagerInventory? _tray;

  /// The block entity at [targetPos], when it is a packager (its tray is not a real inventory).
  bool get targetsPackager =>
      store.at(worldId, targetPos.toBlockPos()) is PackagerBlockEntity;

  /// `ItemVaultBlockEntity.getInvId`: the bounds of the vault the part at [pos] belongs to.
  static BlockBounds? vaultBounds(String worldId, Pos pos) {
    final be = Lg.i.store.typed<ItemVaultBlockEntity>(
      worldId,
      pos.toBlockPos(),
    );
    if (be == null) return null;
    final controller = be.isController
        ? be
        : Lg.i.store.typed<ItemVaultBlockEntity>(
            worldId,
            be.controller.toBlockPos(),
          );
    if (controller == null) return null;
    final origin = controller.partPos;
    final axis = controller.mainConnectionAxis;
    final far = switch (axis) {
      Axis.x => origin.offset(controller.length, controller.radius, controller.radius),
      Axis.z => origin.offset(controller.radius, controller.radius, controller.length),
      Axis.y => origin.offset(controller.radius, controller.length, controller.radius),
    };
    return BlockBounds.fromCorners(origin, far);
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

    final unpacked = await handler.unpack(
      inv,
      items,
      simulate: simulate,
      where: HostUnpackTarget(
        worldId,
        targetPos,
        orderContext: PackageItem.getOrderContext(box),
      ),
    );
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
    // `targetInv instanceof PackagerItemHandler`: a packager does not pull out of another's tray.
    if (targetsPackager) return;

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

          // `!extracted.getItem().canFitInsideContainerItems()`: shulker boxes (and other
          // container items) do not fit into a package; a package always fits.
          final bulky = !canFitInsideContainerItems(
            ItemValue(extracted.key, 1, maxStack: extracted.maxStack),
          );
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
    // `advancements.awardPlayer(AllAdvancements.PACKAGER)`.
    unawaited(advancements.awardPlayer(AllAdvancements.packager));
    triggerStockCheck();
    notifyUpdate();
  }

  /// `updateSignAddress()`: an adjacent sign (front, else back text) supplies the address that a
  /// redstone-triggered packager stamps onto its boxes.
  void updateSignAddress() {
    signBasedAddress = '';
    final world = this.world;
    if (world == null) return;
    for (final side in Direction.values) {
      final address = _signAt(world, _pos.relative(side));
      if (address == null || address.trim().isEmpty) continue;
      signBasedAddress = address;
    }
    // There is no ComputerCraft bridge in this port, so a custom address never stays attached.
    if (hasCustomComputerAddress) {
      signBasedAddress = customComputerAddress;
    } else {
      hasCustomComputerAddress = false;
    }
  }

  /// `getSign(side)`: the front text of the sign at [p], else its back text.
  static String? _signAt(World world, Pos p) {
    final be = world.getBlockEntity(pos: p.toBlockPos());
    SignText Function()? front;
    SignText Function()? back;
    switch (be) {
      case BlockEntityTypeSignBlockEntity(:final value):
        front = value.getFrontText;
        back = value.getBackText;
      case BlockEntityTypeHangingSignBlockEntity(:final value):
        front = value.getFrontText;
        back = value.getBackText;
      default:
        return null;
    }
    String? read(SignText Function() text) {
      final address = StringBuffer();
      for (final message in text().messages) {
        final trimmed = message.trim();
        if (trimmed.isEmpty) continue;
        address.write('$trimmed ');
      }
      final joined = address.toString().trim();
      return joined.isEmpty ? null : joined;
    }

    return read(front) ?? read(back);
  }

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
    _invVersionTracker.reset();
    return getAvailableItems();
  }

  /// The version of [inv] for the tracker, `null` when it does not count changes.
  static (int, int)? _versionOf(ItemInv? inv) =>
      inv is VersionedInv ? (inv as VersionedInv).inventoryVersion : null;

  /// `getAvailableItems()`: a summary of the inventory behind the packager.
  Future<InventorySummary> getAvailableItems() async {
    final inv = targetInventory;
    final version = _versionOf(inv);
    if (_available != null && _invVersionTracker.stillWaiting(version)) {
      return _available!;
    }

    final available = InventorySummary();
    if (inv == null || targetsPackager) {
      _available = available;
      return available;
    }

    // `targetInv instanceof BottomlessItemHandler`: a creative crate has an endless supply.
    final crate = store.typed<CreativeCrateBlockEntity>(
      worldId,
      targetPos.toBlockPos(),
    );
    if (crate != null) {
      final supplied = fromItemValue(crate.suppliedStack, Lg.i.wire);
      if (supplied.isNotEmpty) available.add(supplied, BigStack.inf);
      _available = available;
      return available;
    }

    for (var slot = 0; slot < inv.slots; slot++) {
      available.addStack(await inv.stackAt(slot));
    }

    _invVersionTracker.awaitNewVersion(version);
    await _submitNewArrivals(_available, available);
    _available = available;
    return available;
  }

  /// `submitNewArrivals(before, after)`: promise queues of adjacent restockers and links hear
  /// about items that arrived since the last check.
  Future<void> _submitNewArrivals(
    InventorySummary? before,
    InventorySummary after,
  ) async {
    if (before == null || after.isEmpty) return;
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

/// `PackagerItemHandler`: the packager's tray. One slot holding the box it is working on;
/// inserting a package unpacks it into the inventory behind the packager (the box itself is
/// never kept), taking it out returns the box the tray currently holds.
final class _PackagerInventory implements ItemInventory {
  final PackagerBlockEntity be;

  _PackagerInventory(this.be);

  @override
  int get slots => 1;

  @override
  ItemValue getStack(int slot) {
    final box = be.heldBox;
    return box.isEmpty ? ItemValue.empty : toItemValue(box, Lg.i.wire);
  }

  @override
  int slotLimit(int slot) => 1;

  @override
  bool isItemValid(int slot, ItemValue stack) =>
      PackageItem.isPackage(fromItemValue(stack, Lg.i.wire));

  @override
  Future<ItemValue> insert(
    int slot,
    ItemValue stack, {
    bool simulate = false,
  }) async {
    final box = fromItemValue(stack, Lg.i.wire);
    if (!PackageItem.isPackage(box)) return stack;
    if (be.heldBox.isNotEmpty ||
        be.queuedExitingPackages.isNotEmpty ||
        be.animationTicks != 0) {
      return stack;
    }
    if (!await be.unwrapBox(box, simulate: true)) return stack;
    if (!simulate) {
      await be.unwrapBox(box, simulate: false);
      await be.triggerStockCheck();
    }
    return stack.count > 1 ? stack.withCount(stack.count - 1) : ItemValue.empty;
  }

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    if (amount <= 0 || be.animationTicks != 0) return ItemValue.empty;
    final box = be.heldBox;
    if (box.isEmpty) return ItemValue.empty;
    if (!simulate) {
      be.heldBox = LStack.empty;
      be.notifyUpdate();
    }
    return toItemValue(box, Lg.i.wire);
  }
}

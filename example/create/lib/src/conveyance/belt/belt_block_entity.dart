// `BeltBlockEntity` (host side): the kinetic block entity of a belt segment. The controller
// segment owns the [BeltInventory]; every segment knows its index and length, exposes its
// one-slot handler to the world, takes items from belts, funnels and item entities, and moves
// entities standing on it. Ported from
// `content/kinetics/belt/BeltBlockEntity.java` (the client-only model data and render bounds are
// omitted).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/kinetics.dart';
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../core/block_entity.dart';
import '../../processing/common/capabilities.dart' show ItemStorageProvider;
import '../../processing/common/storage.dart' show ItemStorage;
import '../../processing/transport/transport_behaviours.dart' as pt;
import '../behaviours/belt_interfaces.dart';
import '../behaviours/processing_bridge.dart';
import '../items/inventory.dart';
import '../items/item_codec.dart';
import '../items/item_data.dart';
import '../runtime.dart';
import '../transport/transport_inventory_api.dart' show ItemInventoryProvider;
import 'belt_entity_movement.dart';
import 'belt_geometry.dart';
import 'belt_handlers.dart';
import 'belt_inventory.dart';
import 'belt_ports.dart';
import 'belt_segment_inventory.dart';
import 'transported_item.dart';

export 'belt_block_def.dart' show BeltBlockDef;

/// `BeltBlockEntity.CasingType` (the names Create's client reads from the update tag).
abstract final class BeltCasing {
  static const String none = 'NONE';
  static const String andesite = 'ANDESITE';
  static const String brass = 'BRASS';
}

/// `BeltBlockEntity`.
class BeltBlockEntity extends KineticBlockEntity
    implements
        BeltEnvironment,
        DirectBeltInput,
        TransportedItemStackHandler,
        ItemInventoryProvider,
        ItemStorageProvider {
  BeltBlockEntity(super.worldId, super.pos) {
    final view = ProcessingHandlerView(this);
    addBehaviour<pt.TransportedItemStackHandlerBehaviour>(
      pt.TransportedItemStackHandlerBehaviour(
        (maxDistance, process) =>
            view.handleCenteredProcessingOnAllItems(maxDistance, process),
        positionGetter: (t) => view.worldPositionOf(t),
      ),
    );
  }

  /// `controller`: the position of the controller segment, `null` until `initBelt` ran.
  Pos? controller;
  int beltLength = 0;
  int index = 0;

  /// `CasingType.name()`.
  String casing = BeltCasing.none;
  bool covered = false;

  /// `DyeColor.name()`, or `null`.
  String? dye;

  BeltInventory? _inventory;
  BeltSegmentInventory? _itemHandler;

  /// `VersionedInventoryTrackerBehaviour`: the funnel insertion back-off.
  final VersionTracker invVersionTracker = VersionTracker();

  /// `passengers`, keyed by entity id (host handles cannot be kept between ticks).
  final Map<int, TransportedEntityInfo> passengers = {};

  /// The state of the belt block as a [BState] (the pure geometry helpers speak [BState]).
  BState get beltState => BState(blockState.block, blockState.props);

  /// The pure position record of this block entity.
  Pos get p => this.pos.toPos();

  bool get isController => controller != null && controller == p;

  Pos get controllerPos => controller ?? p;

  BeltBlockEntity? get controllerBE {
    final c = controller;
    if (c == null) return null;
    final w = world;
    if (w != null && !w.isLoaded(pos: c.toBlockPos())) return null;
    return store.typed<BeltBlockEntity>(worldId, c.toBlockPos());
  }

  void setController(Pos controllerPos) => controller = controllerPos;

  /// `getBeltMovementSpeed`.
  double get beltMovementSpeed => speed / 480;

  /// `getDirectionAwareBeltMovementSpeed`.
  double get directionAwareBeltMovementSpeed {
    var offset = beltFacing.axisDirection.step;
    if (beltFacing.axis == Axis.x) offset *= -1;
    return beltMovementSpeed * offset;
  }

  Direction get beltFacing =>
      Direction.values[(blockState.dirOf('facing') ?? Dir.north).index];

  /// `hasPulley`.
  bool get hasPulley =>
      beltState.isBelt && beltState.beltPart != BeltPart.middle;

  /// `getMovementFacing`.
  @override
  Direction get movementFacing {
    final axis = beltFacing.axis;
    final negative = (beltMovementSpeed < 0) ^ (axis == Axis.x);
    return Direction.fromAxisAndDirection(
      axis,
      negative ? AxisDirection.negative : AxisDirection.positive,
    );
  }

  /// `getMovementDirection(firstHalf, ignoreHalves)` as a unit vector.
  Pos getMovementDirection({
    required bool firstHalf,
    required bool ignoreHalves,
  }) {
    if (speed == 0) return posZero;
    final facing = blockState.dirOf('facing') ?? Dir.north;
    final slope = BeltSlope.fromName(blockState['slope']);
    final part = BeltPart.fromName(blockState['part']);
    final axis = facing.axis;

    var movementFacing = Dir.along(
      axis,
      positive: axis == KAxis.x ? false : true,
    );
    final notHorizontal = slope != BeltSlope.horizontal;
    if (speed < 0) movementFacing = movementFacing.opposite;
    final movement = (movementFacing.dx, movementFacing.dy, movementFacing.dz);

    final slopeBeforeHalf = (part == BeltPart.end) == facing.isPositive;
    final onSlope =
        notHorizontal &&
        (part == BeltPart.middle ||
            slopeBeforeHalf == firstHalf ||
            ignoreHalves);
    final movingUp =
        onSlope &&
        slope ==
            (movementFacing == facing ? BeltSlope.upward : BeltSlope.downward);
    if (!onSlope) return movement;
    return (movement.$1, movingUp ? 1 : -1, movement.$3);
  }

  /// `getBeltChainDirection`.
  @override
  Pos get beltChainDirection =>
      getMovementDirection(firstHalf: true, ignoreHalves: true);

  /// `getInventory`: only the controller owns one.
  BeltInventory? getInventory() {
    if (!isController) return controllerBE?.getInventory();
    return _inventory ??= BeltInventory(this);
  }

  /// `initializeItemHandler`.
  void initializeItemHandler() {
    if (_itemHandler != null || beltLength == 0) return;
    final w = world;
    if (w == null || !w.isLoaded(pos: controllerPos.toBlockPos())) return;
    final inv = getInventory();
    if (inv == null) return;
    _itemHandler = BeltSegmentInventory(inv, index);
  }

  /// The one-slot handler of this segment (`ItemHandlerBeltSegment`).
  ItemInventory? get itemHandler {
    initializeItemHandler();
    return _itemHandler;
  }

  /// The segment inventory for the funnels, tunnels, chutes and depots of the conveyance module.
  @override
  ItemInventory? itemInventory(Direction? side) {
    if (!canTransportObjects(beltState)) return null;
    return itemHandler;
  }

  /// The segment as the processing machines' storage (`StorageLookup`).
  @override
  ItemStorage? itemStorage(String? side) {
    if (!canTransportObjects(beltState)) return null;
    initializeItemHandler();
    final handler = _itemHandler;
    return handler == null ? null : BeltSegmentStorage(handler);
  }

  /// `invalidateItemHandler`: the segment handler is rebuilt on the next access.
  void invalidateItemHandler() {
    _itemHandler = null;
  }

  /// `controllerBE.inventory = null`: the controller hands its inventory to a new controller.
  void clearInventory() {
    _inventory = null;
    _itemHandler = null;
  }

  // -- Kinetic hooks --------------------------------------------------------------------------

  @override
  double calculateStressApplied() {
    if (!isController) return 0;
    return super.calculateStressApplied();
  }

  @override
  bool canPropagateDiagonally(KineticBlockDef block, KState state) {
    final slope = state['slope'];
    return slope == BeltSlope.upward.name || slope == BeltSlope.downward.name;
  }

  @override
  double propagateRotationTo(
    KineticNode target,
    KState stateFrom,
    KState stateTo,
    KPos diff,
    bool connectedViaAxes,
    bool connectedViaCogs,
  ) {
    if (target is BeltBlockEntity && !connectedViaAxes) {
      return controllerPos == target.controllerPos ? 1 : 0;
    }
    return 0;
  }

  // -- Lifecycle ------------------------------------------------------------------------------

  @override
  void sendData() {
    final inv = isController ? getInventory() : null;
    runtime.log.info(
      'DBG sendData $p controller=$controller idx=$index speed=$speed '
      'items=${inv?.items.map((t) => '${t.beltPosition.toStringAsFixed(3)}/${t.prevBeltPosition.toStringAsFixed(3)}').join(',')} '
      'toInsert=${inv?.toInsert.length} toRemove=${inv?.toRemove.length}',
    );
    super.sendData();
  }

  @override
  void tick() {
    if (beltLength == 0) initBelt(this);
    super.tick();
    if (!beltState.isBelt) return;
    initializeItemHandler();
    if (isController) {
      final inv0 = getInventory();
      runtime.log.info(
        'DBG tick $p speed=$speed len=$beltLength '
        'items=${inv0?.items.map((t) => '${t.beltPosition.toStringAsFixed(3)}/${t.prevBeltPosition.toStringAsFixed(3)}/${t.sideOffset.toStringAsFixed(3)}/${t.prevSideOffset.toStringAsFixed(3)}').join(',')}',
      );
    }
    if (!isController) return;
    final inv = getInventory();
    if (inv == null) return;
    unawaited(
      inv.tick().catchError((Object e, StackTrace s) {
        runtime.log.error(
          'Ticking the belt at $p failed',
          error: e,
          stackTrace: s,
        );
      }),
    );
    if (speed == 0) return;
    _tickPassengers();
  }

  void _tickPassengers() {
    if (passengers.isEmpty) return;
    final w = world;
    if (w == null) return;
    final slope = blockState['slope'];
    final limit = slope != BeltSlope.horizontal.name ? 3 : 1;
    for (final id in passengers.keys.toList()) {
      final info = passengers[id]!;
      final entity = w.getEntityById(id: id);
      if (entity == null) {
        passengers.remove(id);
        continue;
      }
      try {
        final left = info.ticksSinceLastCollision > limit;
        if (!canBeTransported(entity) || left) {
          passengers.remove(id);
          continue;
        }
        info.tick();
        transportEntity(this, entity, info);
      } finally {
        entity.dispose();
      }
    }
  }

  @override
  void onRemoved() {
    if (isController) {
      final inv = _inventory;
      if (inv != null) unawaited(inv.ejectAll());
    }
    super.onRemoved();
  }

  @override
  void clearKineticInformation() {
    super.clearKineticInformation();
    beltLength = 0;
    index = 0;
    controller = null;
  }

  // -- World views ----------------------------------------------------------------------------

  /// The state at [at] (`level.getBlockState`).
  BState stateAt(Pos at) {
    final w = world;
    if (w == null) return BState.air;
    return HostBlockGetter(w).stateAt(at);
  }

  CreateBlockEntity? _beAt(Pos at) => store.at(worldId, at.toBlockPos());

  /// `getSegmentBE` for [at].
  BeltBlockEntity? segmentAt(Pos at) =>
      store.typed<BeltBlockEntity>(worldId, at.toBlockPos());

  // -- BeltEnvironment ------------------------------------------------------------------------

  @override
  bool get isHorizontal => blockState['slope'] == BeltSlope.horizontal.name;

  @override
  Pos positionForOffset(int offset) =>
      beltPositionForOffset(controllerPos, controllerState, beltLength, offset);

  BState get controllerState {
    final c = controllerBE;
    return c != null ? c.beltState : beltState;
  }

  @override
  Vec3 vectorForOffset(double offset) =>
      beltVectorForOffset(controllerPos, controllerState, beltLength, offset);

  @override
  bool isLoaded(Pos at) => world?.isLoaded(pos: at.toBlockPos()) ?? false;

  @override
  DirectBeltInput? directInputAt(Pos at) {
    final be = _beAt(at);
    if (be == null) return null;
    if (be is DirectBeltInput) return be as DirectBeltInput;
    final behaviour = be.getBehaviour<pt.DirectBeltInputBehaviour>();
    if (behaviour != null) return DirectInputAdapter(behaviour);
    return null;
  }

  @override
  BeltProcessing? processingAt(Pos at) {
    final be = _beAt(at);
    if (be == null) return null;
    if (be is BeltProcessing) return be as BeltProcessing;
    final behaviour = be.getBehaviour<pt.BeltProcessingBehaviour>();
    if (behaviour != null) return ProcessingBeltAdapter(behaviour);
    return null;
  }

  @override
  TransportedItemStackHandler? stackHandlerAt(Pos at) {
    final be = _beAt(at);
    if (be == null) return null;
    if (be is TransportedItemStackHandler)
      return be as TransportedItemStackHandler;
    final behaviour = be
        .getBehaviour<pt.TransportedItemStackHandlerBehaviour>();
    if (behaviour != null) return ConveyanceHandlerView(behaviour);
    return null;
  }

  @override
  bool isProcessingBlocked(Pos processingSpace) {
    final above = processingSpace.above;
    final state = stateAt(above);
    final isFunnel = _isFunnel(state.key);
    final hasCollision = !HostBlockGetter(world!).collisionShapeEmpty(above);
    return pt.BeltProcessingBehaviour.isBlocked(
      isFunnelAbove: isFunnel,
      hasCollisionAbove: hasCollision,
    );
  }

  @override
  bool hasSolidSide(Pos at, Direction side) {
    final w = world;
    if (w == null) return false;
    return HostBlockGetter(w).isFaceSturdy(at, side);
  }

  @override
  BeltFunnelPort? funnelAbove(int segment) {
    final at = positionForOffset(segment).above;
    final state = stateAt(at);
    if (!_isBeltFunnel(state.key)) return null;
    final be = _beAt(at);
    return _FunnelPort(state, be is FunnelPort ? be as FunnelPort : null);
  }

  @override
  BeltTunnelPort? tunnelOnSegment(int segment) {
    final at = positionForOffset(segment).above;
    final state = stateAt(at);
    if (state.key != 'create:andesite_tunnel' &&
        state.key != 'create:brass_tunnel')
      return null;
    final be = _beAt(at);
    return be is BeltTunnelPort ? be as BeltTunnelPort : null;
  }

  @override
  BeltTunnelPort? brassTunnelAbove(int segment) {
    final tunnel = tunnelOnSegment(segment);
    return tunnel != null && tunnel.isBrass ? tunnel : null;
  }

  @override
  BeltCrusherPort? crusherAbove(int segment) {
    final at = positionForOffset(segment).above;
    final state = stateAt(at);
    if (state.key != 'create:crushing_wheel_controller') return null;
    final be = _beAt(at);
    if (be is BeltCrusherPort) return be as BeltCrusherPort;
    return _CrusherPort(state);
  }

  @override
  VersionTracker get versionTracker => invVersionTracker;

  @override
  void notifyUpdate() {
    markDirty();
    sendData();
  }

  @override
  void spawnItem(ItemValue stack, Vec3 position, Vec3 motion) {
    final w = world;
    if (w == null) return;
    unawaited(
      ItemCodec.drop(w, position, stack, velocity: motion, pickupDelay: 10),
    );
  }

  // -- DirectBeltInput ------------------------------------------------------------------------

  /// `canInsertFrom`.
  bool canInsertFrom(Direction side) {
    if (speed == 0) return false;
    final state = beltState;
    if (!state.isBelt) return false;
    if (state.beltSlope == BeltSlope.sideways ||
        state.beltSlope == BeltSlope.vertical)
      return false;
    return movementFacing != side.opposite;
  }

  /// `isOccupied`.
  bool isOccupied(Direction side) {
    final controller = controllerBE;
    if (controller == null) return true;
    final inv = controller.getInventory();
    if (inv == null) return true;
    if (speed == 0) return true;
    if (movementFacing == side.opposite) return true;
    if (!inv.canInsertAtFromSide(index, side)) return true;
    return false;
  }

  @override
  bool get canSupportBeltFunnels => false;

  @override
  bool canInsertFromSide(Direction side) => canInsertFrom(side);

  @override
  FutureOr<ItemValue> handleInsertion(
    TransportedItemStack transportedStack,
    Direction side, {
    bool simulate = false,
  }) {
    final inserted = transportedStack.stack;
    if (!canTransportObjects(beltState)) return inserted;
    final controller = controllerBE;
    if (controller == null) return inserted;
    final inv = controller.getInventory();
    if (inv == null) return inserted;

    // A brass tunnel above the belt would distribute the item; the tunnel's own insertion path
    // (its `DirectBeltInput`) handles that when the tunnel block is ported.

    if (isOccupied(side)) return inserted;
    if (simulate) return ItemValue.empty;

    final t = transportedStack.copy();
    t.beltPosition = index + .5 - directionAwareBeltMovementSpeed.sign / 16;
    final facing = movementFacing;
    if (!side.axis.isVertical) {
      if (facing != side) {
        var offset = side.axisDirection.step * .675;
        if (side.axis == Axis.x) offset *= -1;
        t.sideOffset = offset;
      } else {
        // Smoother transition from belt to belt.
        final extra =
            t.prevBeltPosition != 0 &&
                segmentAt(p.relative(facing.opposite)) != null
            ? .26
            : 0.0;
        t.beltPosition = directionAwareBeltMovementSpeed > 0
            ? index - extra
            : index + 1 + extra;
      }
    }

    t.prevSideOffset = t.sideOffset;
    t.insertedAt = index;
    t.insertedFrom = side;
    t.prevBeltPosition = t.beltPosition;

    flapTunnel(this, index, side.opposite, true);
    inv.addItem(t);
    markDirty();
    sendData();
    return ItemValue.empty;
  }

  // -- TransportedItemStackHandler ------------------------------------------------------------

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    ItemProcessor processFunction,
  ) {
    final controller = controllerBE;
    controller?.getInventory()?.applyToEachWithin(
      index + .5,
      maxDistanceFromCenter,
      processFunction,
    );
  }

  @override
  void handleProcessingOnAllItems(ItemProcessor processFunction) =>
      handleCenteredProcessingOnAllItems(.51, processFunction);

  @override
  void handleProcessingOnItem(
    TransportedItemStack item,
    TransportedResult result,
  ) => handleCenteredProcessingOnAllItems(
    .51,
    (t) => identical(t, item) ? result : null,
  );

  @override
  Vec3 getWorldPositionOf(TransportedItemStack transported) {
    final controller = controllerBE;
    if (controller == null) return (0.0, 0.0, 0.0);
    return beltVectorForOffset(
      controller.p,
      controller.beltState,
      controller.beltLength,
      transported.beltPosition,
    );
  }

  // -- Casing, colour and cover ---------------------------------------------------------------

  /// `setCasingType`.
  void setCasingType(String type) {
    if (casing == type) return;
    final shouldHaveCasing = type != BeltCasing.none;
    if (beltState.flag('casing') != shouldHaveCasing) {
      final updated = beltState.setFlag('casing', shouldHaveCasing);
      setStateAsync(KState(updated.key, updated.props));
    }
    casing = type;
    markDirty();
    sendData();
  }

  /// `applyColor`: sets the dye of every segment of the chain.
  bool applyColor(String? colorName) {
    if (colorName == null) {
      if (dye == null) return false;
    } else if (dye == colorName) {
      return false;
    }
    final w = world;
    if (w == null) return true;
    final chain = getBeltChain(HostBlockGetter(w), controllerPos);
    for (final at in chain) {
      final belt = segmentAt(at);
      if (belt == null) continue;
      belt.dye = colorName;
      belt.markDirty();
      belt.sendData();
    }
    return true;
  }

  /// `setCovered`.
  void setCovered(bool value) {
    if (covered == value) return;
    covered = value;
    notifyUpdate();
  }

  /// `updateCoverProperty`: only horizontal, cased belts track the block above.
  void updateCoverProperty() {
    final state = beltState;
    if (!state.isBelt) return;
    if (!state.flag('casing') || state.beltSlope != BeltSlope.horizontal)
      return;
    final w = world;
    if (w == null) return;
    setCovered(isBlockCoveringBelt(HostBlockGetter(w), p.above));
  }

  // -- Entity interaction ---------------------------------------------------------------------

  /// `entityInside` for a non-item entity: remember it as a belt passenger.
  void entityEntered(int entityId, Pos at) {
    final info = passengers[entityId];
    if (info != null) {
      if (info.ticksSinceLastCollision != 0 || at == p)
        info.refresh(at, blockState);
    } else {
      passengers[entityId] = TransportedEntityInfo(at, blockState);
    }
  }

  /// `entityInside` for an item entity: try to take its stack onto the belt.
  Future<void> absorbItemEntity(Entity entity) async {
    final w = world;
    if (w == null) return;
    final itemEntity = entity.asItem();
    if (itemEntity == null) return;
    try {
      final hostStack = itemEntity.getStack();
      final value = await ItemCodec.read(hostStack);
      hostStack.dispose();
      if (value.isEmpty) return;
      if (entity.getVelocity().$2 > 0) return;
      if (tunnelOnSegment(index) != null) return;
      final handler = itemHandler;
      if (handler == null) return;
      final remainder = await handler.insert(0, value);
      if (remainder.isEmpty) {
        entity.remove();
      } else if (remainder.count != value.count) {
        final rest = await ItemCodec.write(remainder);
        if (rest != null) await itemEntity.setStack(stack: rest);
      }
    } finally {
      itemEntity.dispose();
    }
  }

  // -- NBT ------------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final c = controller;
    if (c != null) NbtHelper.writeBlockPos(tag, 'Controller', c);
    tag.putBool('IsController', isController);
    tag.putInt('Length', beltLength);
    tag.putInt('Index', index);
    tag.putString('Casing', casing);
    tag.putBool('Covered', covered);
    final d = dye;
    if (d != null) tag.putString('Dye', d);
    if (isController) {
      final inv = getInventory();
      if (inv != null)
        tag.putCompound(
          'Inventory',
          _writeInventory(inv, clientPacket: clientPacket),
        );
    }
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket && isController) {
      runtime.log.info('DBG clientTag $p $tag');
    }
  }

  NbtCompound _writeInventory(BeltInventory inv, {required bool clientPacket}) {
    inv.flush();
    final nbt = NbtCompound();
    nbt.putList('Items', [
      for (final t in inv.items)
        _transportedToNbt(t, clientPacket: clientPacket),
    ]);
    final lazy = inv.lazyClientItem;
    if (lazy != null)
      nbt.putCompound(
        'LazyItem',
        _transportedToNbt(lazy, clientPacket: clientPacket),
      );
    nbt.putBool('PositiveOrder', inv.beltMovementPositive);
    return nbt;
  }

  NbtCompound _transportedToNbt(
    TransportedItemStack t, {
    required bool clientPacket,
  }) {
    final nbt = NbtCompound()
      ..putCompound(
        'Item',
        ItemCodec.toTag(t.stack, clientPacket: clientPacket),
      )
      ..putFloat('Pos', t.beltPosition)
      ..putFloat('PrevPos', t.prevBeltPosition)
      ..putFloat('Offset', t.sideOffset)
      ..putFloat('PrevOffset', t.prevSideOffset)
      ..putInt('InSegment', t.insertedAt)
      ..putInt('Angle', t.angle)
      ..putInt('InDirection', t.insertedFrom.index);
    if (t.processedBy != null) {
      nbt
        ..putString('FanProcessingType', t.processedBy!)
        ..putInt('FanProcessingTime', t.processingTime);
    }
    if (t.locked) nbt.putBool('Locked', true);
    if (t.lockedExternally) nbt.putBool('LockedExternally', true);
    return nbt;
  }

  TransportedItemStack _transportedFromNbt(NbtCompound nbt) {
    final t = TransportedItemStack.raw(
      ItemCodec.fromAnyNbt(nbt.getCompound('Item')),
    );
    t.beltPosition = nbt.getDouble('Pos') ?? 0;
    t.prevBeltPosition = nbt.getDouble('PrevPos') ?? 0;
    t.sideOffset = nbt.getDouble('Offset') ?? 0;
    t.prevSideOffset = nbt.getDouble('PrevOffset') ?? 0;
    t.insertedAt = nbt.getInt('InSegment') ?? 0;
    t.angle = nbt.getInt('Angle') ?? 0;
    t.insertedFrom = Direction.from3DDataValue(nbt.getInt('InDirection') ?? 0);
    t.locked = nbt.getBool('Locked') ?? false;
    t.lockedExternally = nbt.getBool('LockedExternally') ?? false;
    final fan = nbt.getString('FanProcessingType');
    if (fan != null) {
      t.processedBy = fan;
      t.processingTime = nbt.getInt('FanProcessingTime') ?? 0;
    }
    return t;
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);

    if (tag.getBool('IsController') ?? false) controller = p;
    dye = tag.getString('Dye');

    if (!wasMoved) {
      if (!isController) {
        controller = tag.getIntArray('Controller') != null
            ? NbtHelper.readBlockPos(tag, 'Controller')
            : null;
      }
      index = tag.getInt('Index') ?? 0;
      beltLength = tag.getInt('Length') ?? 0;
    }

    if (isController) {
      final inv = getInventory();
      final inventoryTag = tag.getCompound('Inventory');
      if (inv != null && inventoryTag != null) {
        inv.items.clear();
        for (final e in inventoryTag.getList('Items') ?? const <Object>[]) {
          if (e is NbtCompound) inv.items.add(_transportedFromNbt(e));
        }
        final lazy = inventoryTag.getCompound('LazyItem');
        inv.lazyClientItem = lazy == null ? null : _transportedFromNbt(lazy);
        inv.beltMovementPositive =
            inventoryTag.getBool('PositiveOrder') ?? false;
      }
    }

    casing = _casingName(tag.getString('Casing'));
    covered = tag.getBool('Covered') ?? false;
  }

  static String _casingName(String? name) => switch (name) {
    'ANDESITE' => BeltCasing.andesite,
    'BRASS' => BeltCasing.brass,
    _ => BeltCasing.none,
  };

  // -- Belt init ------------------------------------------------------------------------------

  /// `BeltBlock.initBelt`: finds the controller of the chain [start] belongs to and initialises
  /// every segment. A chain of fewer than two segments is broken.
  static void initBelt(BeltBlockEntity start) {
    final w = start.world;
    if (w == null) return;
    final getter = HostBlockGetter(w);
    if (!getter.stateAt(start.p).isBelt) return;

    final resolution = resolveBeltChain(getter, start.p);
    switch (resolution.status) {
      case BeltChainStatus.unloaded:
        return;
      case BeltChainStatus.broken:
        _destroy(start.worldId, resolution.controller);
        return;
      case BeltChainStatus.ok:
        break;
    }

    final currentPos = resolution.controller;
    final chain = resolution.chain;
    var index = 0;
    for (final beltPos in chain) {
      final be = start.store.at(start.worldId, beltPos.toBlockPos());
      final currentState = getter.stateAt(beltPos);
      if (be is BeltBlockEntity && currentState.isBelt) {
        be
          ..controller = currentPos
          ..beltLength = chain.length
          ..index = index;
        be.attachKinetics();
        be.markDirty();
        be.sendData();
        if (be.isController && !canTransportObjects(currentState)) {
          unawaited(be.getInventory()?.ejectAll());
        }
      } else {
        _destroy(start.worldId, currentPos);
        return;
      }
      index++;
    }
  }
}

/// `BeltHelper.getPositionForOffset` (renamed to avoid clashing with the method of the entity).
Pos beltPositionForOffset(
  Pos controller,
  BState state,
  int beltLength,
  int offset,
) => positionForOffset(controller, state, beltLength, offset);

/// `BeltHelper.getVectorForOffset` (renamed to avoid clashing with the method of the entity).
Vec3 beltVectorForOffset(
  Pos controller,
  BState state,
  int beltLength,
  double offset,
) => vectorForOffset(controller, state, beltLength, offset);

/// `Level.destroyBlock(pos, true)` of the belt chain.
void _destroy(String worldId, Pos pos) {
  if (ConveyanceRuntime.loaded) ConveyanceRuntime.i.destroyBlock(worldId, pos);
}

bool _isFunnel(String key) =>
    key == 'create:andesite_funnel' ||
    key == 'create:brass_funnel' ||
    key == 'create:andesite_belt_funnel' ||
    key == 'create:brass_belt_funnel';

bool _isBeltFunnel(String key) =>
    key == 'create:andesite_belt_funnel' || key == 'create:brass_belt_funnel';

/// A belt funnel above a segment: its state, and its block entity when it is a [FunnelPort].
final class _FunnelPort implements BeltFunnelPort {
  final BState state;
  @override
  final FunnelPort? entity;

  _FunnelPort(this.state, this.entity);

  @override
  Direction get facing => state.dir('facing') ?? Direction.north;

  @override
  String get shape => state['shape'] ?? 'retracted';

  @override
  bool get powered => state.flag('powered');
}

/// A crushing wheel controller above a segment without a Dart block entity: it still stops the
/// item at the controller, as the Java handler does when the block entity is missing.
final class _CrusherPort implements BeltCrusherPort {
  final BState state;

  _CrusherPort(this.state);

  @override
  Direction get facing => state.dir('facing') ?? Direction.north;

  @override
  bool get hasEntity => false;

  @override
  Future<ItemValue> insert(ItemValue stack) async => stack;
}

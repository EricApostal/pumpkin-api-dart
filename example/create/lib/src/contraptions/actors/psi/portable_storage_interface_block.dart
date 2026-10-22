// `PortableStorageInterfaceBlock` and its block entities: the interface that connects a contraption
// to a stationary interface next to it and lets the contraption's items or fluids cross over.
//
// The host has no way to expose a dynamic item/fluid handler on a block entity (the storage that
// belongs to the contraption), so the connected storage is kept on the block entity. The fluid
// interface implements `FluidCapable` with an `InterfaceFluidHandler` over it, which is what lets
// pipes connect to it and pull from the contraption.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart' show manifestBlock;
import '../../../common/common.dart';
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
import '../../core/nbt_map.dart';
import '../../../fluids/fluid_host.dart' show FluidCapable;
import '../../../fluids/fluid_stack.dart';
import '../../../fluids/fluid_storage.dart';
import '../../../fluids/potion_data.dart';
import '../../core/contraption.dart';
import '../../storage/stacks.dart';
import '../actor_runtime.dart';
import '../actor_shapes.dart';

/// `PortableStorageInterfaceBlockEntity.ANIMATION`.
const int psiAnimation = 4;

/// `PortableStorageInterfaceBlockEntity`: the timer that keeps a contraption waiting while it
/// transfers.
abstract class PortableStorageInterfaceBlockEntity extends CreateBlockEntity {
  PortableStorageInterfaceBlockEntity(super.worldId, super.pos);

  /// `transferTimer`.
  int transferTimer = 0;

  /// `distance`.
  double distance = 0;

  /// `connectionAnimation`: the client animation value.
  double connectionAnimation = 0;

  /// `powered`.
  bool powered = false;

  /// `connectedEntity`: the contraption this interface serves.
  ContraptionEntityHandle? connectedEntity;

  /// `keepAlive`.
  int keepAlive = 0;

  /// `getTransferTimeout` (`logistics.psiTimeout`).
  int get transferTimeout => actors?.psiTimeout ?? 60;

  /// `startTransferringTo`.
  void startTransferringTo(Contraption? contraption, double distance) {
    final entity = contraption?.entity;
    if (identical(connectedEntity, entity)) return;
    this.distance = math.min(2, distance);
    connectedEntity = entity;
    startConnecting();
    sendData();
  }

  /// `stopTransferring`.
  void stopTransferring() {
    connectedEntity = null;
    final w = world;
    if (w != null)
      unawaited(w.updateNeighbors(pos: this.pos, sourceBlock: typeKey));
  }

  /// `canTransfer`.
  bool canTransfer() => connectedEntity != null && isConnected();

  @override
  void initialize() {
    super.initialize();
    unawaited(_refreshPowered(send: false));
  }

  /// `neighbourChanged`.
  void neighbourChanged() => unawaited(_refreshPowered(send: true));

  Future<void> _refreshPowered({required bool send}) async {
    final w = world;
    if (w == null) return;
    final isBlockPowered = await w.hasNeighborSignal(pos: this.pos);
    if (isBlockPowered == powered) return;
    powered = isBlockPowered;
    if (powered) stopTransferring();
    if (send) sendData();
  }

  @override
  void tick() {
    super.tick();
    final wasConnected = isConnected();
    const animation = psiAnimation;
    final timeUnit = transferTimeout;

    if (keepAlive > 0) {
      keepAlive--;
      if (keepAlive == 0) {
        stopTransferring();
        transferTimer = animation - 1;
        sendData();
        return;
      }
    }

    transferTimer = math.min(transferTimer, animation * 2 + timeUnit);

    final timerCanDecrement =
        transferTimer > animation || transferTimer > 0 && keepAlive == 0;
    if (timerCanDecrement) {
      transferTimer--;
      if (transferTimer == animation - 1) sendData();
      if (transferTimer <= 0 || powered) stopTransferring();
    }

    if (wasConnected != isConnected()) markDirty();
  }

  bool isPowered() => powered;

  bool isTransferring() => transferTimer > psiAnimation;

  bool isConnected() =>
      transferTimer >= psiAnimation &&
      transferTimer <= transferTimeout + psiAnimation;

  /// `getConnectionDistance`.
  double getConnectionDistance() => distance;

  /// `getExtensionDistance`.
  double getExtensionDistance([double partialTicks = 1]) =>
      connectionAnimation * connectionAnimation * distance / 2;

  void startConnecting() => transferTimer = 6 + psiAnimation * 2;

  /// `onContentTransferred`.
  void onContentTransferred() {
    transferTimer = transferTimeout + psiAnimation;
    sendData();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    transferTimer = tag.getInt('Timer') ?? 0;
    distance = tag.getDouble('Distance') ?? 0;
    powered = tag.getBool('Powered') ?? false;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('Timer', transferTimer);
    tag.putFloat('Distance', distance);
    tag.putBool('Powered', powered);
  }
}

/// `PortableItemInterfaceBlockEntity`: the items of the connected contraption.
final class PortableItemInterfaceBlockEntity
    extends PortableStorageInterfaceBlockEntity {
  static const String type = 'create:portable_storage_interface';

  PortableItemInterfaceBlockEntity(super.worldId, super.pos);

  /// `capability`: the contraption's item storage while connected, `null` otherwise.
  ItemSlots? contraptionStorage;

  @override
  void startTransferringTo(Contraption? contraption, double distance) {
    contraptionStorage = contraption?.storage.allItems;
    super.startTransferringTo(contraption, distance);
  }

  @override
  void stopTransferring() {
    contraptionStorage = null;
    super.stopTransferring();
  }
}

/// `PortableFluidInterfaceBlockEntity`: the fluids of the connected contraption.
final class PortableFluidInterfaceBlockEntity
    extends PortableStorageInterfaceBlockEntity
    implements FluidCapable {
  static const String type = 'create:portable_fluid_interface';

  PortableFluidInterfaceBlockEntity(super.worldId, super.pos);

  /// `capability`: the contraption's fluid storage while connected, `null` otherwise.
  FluidTanks? contraptionFluids;

  @override
  void startTransferringTo(Contraption? contraption, double distance) {
    contraptionFluids = contraption?.storage.fluids;
    _handler = _InterfaceFluidHandler(this);
    super.startTransferringTo(contraption, distance);
  }

  @override
  void stopTransferring() {
    contraptionFluids = null;
    _handler = _InterfaceFluidHandler(this);
    super.stopTransferring();
  }

  _InterfaceFluidHandler? _handler;

  /// `Capabilities.Fluid.BLOCK`: the pipes pull the contraption's fluids through this handler.
  @override
  FluidStorage get fluidHandler => _handler ??= _InterfaceFluidHandler(this);
}

/// `InterfaceFluidHandler`: passes the connected contraption's tanks through, and keeps the
/// interface engaged for as long as a transfer is committed.
final class _InterfaceFluidHandler implements KeepAliveFluidStorage {
  final PortableFluidInterfaceBlockEntity _interface;

  _InterfaceFluidHandler(this._interface);

  FluidTanks? get _tanks => _interface.canTransfer() ? _interface.contraptionFluids : null;

  /// The module's stack of a contraption stack.
  static FStack _toFStack(StoredFluid fluid) {
    if (fluid.isEmpty) return FStack.empty;
    final components = fluid.components;
    final data = components == null || components.isEmpty
        ? null
        : PotionFluidData.fromComponents(components.map)?.encode();
    return FStack(fluid.fluid, fluid.amount, data);
  }

  /// The contraption stack of the module's stack.
  static StoredFluid _toStored(FStack stack) {
    if (stack.isEmpty) return StoredFluid.empty;
    final potion = PotionFluidData.decode(stack.data);
    final components = potion == null ? null : NbtMap(potion.toComponents());
    return StoredFluid(stack.fluid, stack.amount, components);
  }

  @override
  int get tanks => _tanks?.tanks ?? 0;

  @override
  FStack fluidInTank(int tank) {
    final t = _tanks;
    if (t == null || tank < 0 || tank >= t.tanks) return FStack.empty;
    return _toFStack(t.fluidInTank(tank));
  }

  @override
  int tankCapacity(int tank) {
    final t = _tanks;
    if (t == null || tank < 0 || tank >= t.tanks) return 0;
    return t.tankCapacity(tank);
  }

  @override
  bool isFluidValid(int tank, FStack stack) {
    final t = _tanks;
    if (t == null || tank < 0 || tank >= t.tanks) return false;
    return t.isFluidValid(tank, _toStored(stack));
  }

  @override
  int fill(FStack resource, {required bool simulate}) {
    if (!_interface.isConnected()) return 0;
    final t = _tanks;
    if (t == null) return 0;
    final filled = t.fill(_toStored(resource), simulate: simulate);
    if (filled > 0 && !simulate) keepAlive();
    return filled;
  }

  @override
  FStack drainFluid(FStack resource, {required bool simulate}) {
    if (!_interface.canTransfer()) return FStack.empty;
    final t = _tanks;
    if (t == null) return FStack.empty;
    final drained = t.drainFluid(_toStored(resource), simulate: simulate);
    if (!drained.isEmpty && !simulate) keepAlive();
    return _toFStack(drained);
  }

  @override
  FStack drain(int maxDrain, {required bool simulate}) {
    if (!_interface.canTransfer()) return FStack.empty;
    final t = _tanks;
    if (t == null) return FStack.empty;
    final drained = t.drain(maxDrain, simulate: simulate);
    if (!drained.isEmpty && !simulate) keepAlive();
    return _toFStack(drained);
  }

  /// `InterfaceFluidHandler.keepAlive`: `onContentTransferred()`.
  @override
  void keepAlive() => _interface.onContentTransferred();
}

/// `PortableStorageInterfaceBlock` for items ([fluids] false) or fluids.
CreateBlock buildPortableStorageInterfaceBlock({required bool fluids}) {
  final key = fluids
      ? 'portable_fluid_interface'
      : 'portable_storage_interface';
  final box = [actorBox(0, 0, 0, 16, 14, 16)];
  return manifestBlock(
    key,
    blockEntityType: fluids
        ? PortableFluidInterfaceBlockEntity.type
        : PortableItemInterfaceBlockEntity.type,
    // `PortableStorageInterfaceBlock.getStateForPlacement` (bytecode of the client's
    // jar): `facing = getNearestLookingDirection()`, flipped when the player sneaks,
    // then `FACING = facing.getOpposite()`. With the promotion
    // (`getNearestLookingDirection()` is the clicked face's opposite) that is the
    // clicked face for a normal click and its opposite while sneaking.
    placement: const [
      PlacementRule.clickedFace('facing', whenSneaking: false),
      PlacementRule.clickedFace('facing', opposite: true, whenSneaking: true),
    ],
    collisionShape: const BlockShape.boxes([BlockBox(0, 0, 0, 1, 1, 1)]),
    selectionShape: BlockShape.boxes(box),
    shapeRules: psiShapeRules(box),
    behavior: BlockBehavior(
      onNeighborUpdate: (server, e) {
        final be = actors?.blockEntities
            .typed<PortableStorageInterfaceBlockEntity>(
              e.targetWorld.getId(),
              e.pos,
            );
        be?.neighbourChanged();
      },
      onComparatorOutput: (server, e) {
        final be = actors?.blockEntities
            .typed<PortableStorageInterfaceBlockEntity>(
              e.targetWorld.getId(),
              e.pos,
            );
        return be != null && be.isConnected() ? 15 : 0;
      },
    ),
  );
}

/// `PORTABLE_STORAGE_INTERFACE.forDirectional()`: the shape turned to the facing.
List<ShapeRule> psiShapeRules(List<BlockBox> boxes) => [
  for (final d in Direction.values)
    ShapeRule(
      when: {'facing': d.serializedName},
      collisionShape: BlockShape.boxes(
        rotateActorBoxes(const [BlockBox(0, 0, 0, 1, 1, 1)], Direction.up, d),
      ),
      selectionShape: BlockShape.boxes(
        rotateActorBoxes(boxes, Direction.up, d),
      ),
    ),
];

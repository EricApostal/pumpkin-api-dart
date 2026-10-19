// `PortableStorageInterfaceBlock` and its block entities: the interface that connects a contraption
// to a stationary interface next to it and lets the contraption's items or fluids cross over.
//
// The host has no way to expose a dynamic item/fluid handler on a block entity (the storage that
// belongs to the contraption), so the connected storage is kept on the block entity for the actor
// and for other plugin code. Pipes from the host cannot pull through it.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart' show manifestBlock;
import '../../../common/common.dart';
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
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
    extends PortableStorageInterfaceBlockEntity {
  static const String type = 'create:portable_fluid_interface';

  PortableFluidInterfaceBlockEntity(super.worldId, super.pos);

  /// `capability`: the contraption's fluid storage while connected, `null` otherwise.
  FluidTanks? contraptionFluids;

  @override
  void startTransferringTo(Contraption? contraption, double distance) {
    contraptionFluids = contraption?.storage.fluids;
    super.startTransferringTo(contraption, distance);
  }

  @override
  void stopTransferring() {
    contraptionFluids = null;
    super.stopTransferring();
  }
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
    placement: const [PlacementRule.lookingDirection('facing', opposite: true)],
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

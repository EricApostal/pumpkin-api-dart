// `GlobalStation` (pure): the graph side of a train station: its name, the train that is at or on
// its way to it, and the postboxes connected to it.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/pos.dart';
import '../entity/carriage.dart';
import '../entity/train.dart';
import '../graph/dimension_palette.dart';
import '../graph/track_node.dart';
import '../manager/create.dart';
import '../signal/single_block_entity_edge_point.dart';
import '../signal/track_edge_point.dart';
import '../util/ctag.dart';
import 'global_package_port.dart';
import 'mail_transfer.dart';

class GlobalStation extends SingleBlockEntityEdgePoint {
  /// Installed by the module that owns packages and postboxes (see [MailTransferHooks]).
  static MailTransferHooks? mailHooks;

  String name = 'Track Station';
  WeakReference<Train>? nearestTrain;
  bool assembling = false;

  Map<Pos, GlobalPackagePort> connectedPorts = {};

  GlobalStation();

  @override
  void blockEntityAdded(Object blockEntity, bool front) {
    super.blockEntityAdded(blockEntity, front);
    final info = EdgePointHooks.describe(blockEntity);
    assembling = info.properties['assembling'] == 'true';
  }

  @override
  void read(CTag nbt, bool migration, DimensionPalette dimensions) {
    super.read(nbt, migration, dimensions);
    name = nbt.getString('Name');
    assembling = nbt.getBoolean('Assembling');
    nearestTrain = null;

    connectedPorts.clear();
    for (final c in nbt.getCompoundList('Ports')) {
      final port = GlobalPackagePort();
      port.address = c.getString('Address');
      port.offlineBuffer.deserializeNBT(c.getCompound('OfflineBuffer'));
      port.primed = c.getBoolean('Primed');
      connectedPorts[c.getBlockPos('Pos')] = port;
    }
  }

  @override
  void readBuffer(PacketReader buffer, DimensionPalette dimensions) {
    super.readBuffer(buffer, dimensions);
    name = buffer.readString();
    assembling = buffer.readBool();
    if (buffer.readBool()) blockEntityPos = buffer.readBlockPos();
  }

  @override
  void write(CTag nbt, DimensionPalette dimensions) {
    super.write(nbt, dimensions);
    nbt.putString('Name', name);
    nbt.putBoolean('Assembling', assembling);

    nbt.putCompoundList('Ports', [
      for (final e in connectedPorts.entries)
        CTag()
          ..putString('Address', e.value.address)
          ..putCompound('OfflineBuffer', e.value.offlineBuffer.serializeNBT())
          ..putBoolean('Primed', e.value.primed)
          ..putBlockPos('Pos', e.key),
    ]);
  }

  @override
  void writeBuffer(PacketWriter buffer, DimensionPalette dimensions) {
    super.writeBuffer(buffer, dimensions);
    buffer.writeString(name);
    buffer.writeBool(assembling);
    final pos = blockEntityPos;
    buffer.writeBool(pos != null);
    if (pos != null) buffer.writeBlockPos(pos);
  }

  bool canApproachFrom(TrackNode side) => isPrimary(side) && !assembling;

  @override
  bool canNavigateVia(TrackNode side) => super.canNavigateVia(side) && !assembling;

  void reserveFor(Train train) {
    final nearestTrain = getNearestTrain();
    if (nearestTrain == null || nearestTrain.navigation.distanceToDestination > train.navigation.distanceToDestination) {
      this.nearestTrain = WeakReference<Train>(train);
    }
  }

  void cancelReservation(Train train) {
    if (identical(nearestTrain?.target, train)) nearestTrain = null;
  }

  void trainDeparted(Train train) {
    cancelReservation(train);
  }

  Train? getPresentTrain() {
    final nearestTrain = getNearestTrain();
    if (nearestTrain == null || !identical(nearestTrain.getCurrentStation(), this)) return null;
    return nearestTrain;
  }

  Train? getImminentTrain() {
    final nearestTrain = getNearestTrain();
    if (nearestTrain == null) return nearestTrain;
    if (identical(nearestTrain.getCurrentStation(), this)) return nearestTrain;
    if (!nearestTrain.navigation.isActive()) return null;
    if (nearestTrain.navigation.distanceToDestination > 30) return null;
    return nearestTrain;
  }

  Train? getNearestTrain() => nearestTrain?.target;

  /// `runMailTransfer()`: moves packages between the present train and the connected postboxes.
  void runMailTransfer() {
    final train = getPresentTrain();
    if (train == null || connectedPorts.isEmpty) return;
    final hooks = mailHooks;
    if (hooks == null) return;

    final worldId = getBlockEntityDimension();

    for (final Carriage carriage in train.carriages) {
      final carriageInventory = hooks.carriageInventory(carriage);
      if (carriageInventory == null) continue;

      // Import from station
      for (final entry in connectedPorts.entries) {
        final port = entry.value;
        final pos = entry.key;

        PackageInventory postboxInventory = port.offlineBuffer;
        final box = hooks.loadedPostbox(worldId, pos);
        if (box != null) postboxInventory = box.inventory;

        for (var slot = 0; slot < postboxInventory.getSlots(); slot++) {
          final stack = postboxInventory.getStackInSlot(slot);
          if (stack == null || !hooks.isPackage(stack)) continue;
          if (hooks.matchAddress(stack, port.address)) continue;

          final result = carriageInventory.insertItemStacked(stack.copy());
          box?.packageEvent(stack, 'package_sent');
          if (result != null) continue;

          postboxInventory.setStackInSlot(slot, null);

          if (box == null) {
            port.primed = true;
          } else {
            box.spawnParticles();
          }

          Create.RAILWAYS.markTracksDirty();
        }
      }

      // Export to station
      for (var slot = 0; slot < carriageInventory.getSlots(); slot++) {
        final stack = carriageInventory.getStackInSlot(slot);
        if (stack == null || !hooks.isPackage(stack)) continue;

        for (final entry in connectedPorts.entries) {
          final port = entry.value;
          final pos = entry.key;

          if (!hooks.matchAddress(stack, port.address)) continue;

          PackageInventory postboxInventory = port.offlineBuffer;
          final box = hooks.loadedPostbox(worldId, pos);
          if (box != null) postboxInventory = box.inventory;

          final result = postboxInventory.insertItemStacked(stack.copy());
          box?.packageEvent(stack, 'package_received');
          if (result != null) continue;

          carriageInventory.setStackInSlot(slot, null);

          if (box == null) {
            port.primed = true;
          } else {
            box.spawnParticles();
          }

          Create.RAILWAYS.markTracksDirty();

          break;
        }
      }
    }
  }
}

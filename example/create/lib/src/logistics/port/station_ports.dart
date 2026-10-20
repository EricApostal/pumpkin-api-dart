// `StationBlockEntity.attachPackagePort` / `removePackagePort` and the postbox' offline buffer:
// a station keeps a copy of the contents of every postbox connected to it
// (`GlobalStation.connectedPorts`), so mail can be moved while the postbox' chunk is unloaded.
import '../../api/trains.dart' show GlobalStation, StationPackagePorts;
import '../../common/host_bridge.dart';
import '../../trains/station/global_package_port.dart' show GlobalPackagePort;
import '../../trains/station/mail_transfer.dart' show PackageInventory;
import '../../trains/util/ctag.dart';
import '../model/inventory.dart';
import '../model/stack_tags.dart' show stackFromCTag, stackToCTag;
import 'package_port_block_entity.dart';

/// A postbox' eighteen package slots as the station's mail transfer sees them.
final class PostboxPackageInventory implements PackageInventory {
  final PostboxBlockEntity be;

  PostboxPackageInventory(this.be);

  MemoryInv get _buffer => be.packages;

  @override
  int getSlots() => _buffer.slots;

  @override
  CTag? getStackInSlot(int slot) => stackToCTag(_buffer.at(slot));

  @override
  void setStackInSlot(int slot, CTag? stack) =>
      _buffer.set(slot, stackFromCTag(stack));

  @override
  CTag? insertItemStacked(CTag stack) {
    final rest = _buffer.insertStackedNow(stackFromCTag(stack));
    return rest.isEmpty ? null : stackToCTag(rest);
  }
}

/// `PostboxBlockEntity.saveOfflineBuffer()`: copies the buffer into the station's offline buffer.
void savePostboxOfflineBuffer(PostboxBlockEntity be) {
  final station = be.trackedStation;
  if (station is! GlobalStation) return;
  final port = station.connectedPorts[be.pos.toPos()];
  if (port == null) return;
  port.saveOfflineBuffer(PostboxPackageInventory(be));
}

/// `StationBlockEntity.attachPackagePort(ppbe)` / `removePackagePort(ppbe)` for postboxes. The
/// trains module looks this up as a service.
final class PostboxStationPorts implements StationPackagePorts {
  @override
  void attach(GlobalStation station, Object portBlockEntity) {
    if (portBlockEntity is! PostboxBlockEntity) return;
    portBlockEntity.trackedStation = station;

    final pos = portBlockEntity.pos.toPos();
    final existing = station.connectedPorts[pos];
    if (existing == null) {
      station.connectedPorts[pos] = GlobalPackagePort()
        ..address = portBlockEntity.addressFilter;
    } else {
      // A station that is loaded again restores what it kept for the unloaded postbox.
      existing.restoreOfflineBuffer(PostboxPackageInventory(portBlockEntity));
    }
  }

  @override
  void remove(GlobalStation station, Object portBlockEntity) {
    if (portBlockEntity is! PostboxBlockEntity) return;
    station.connectedPorts.remove(portBlockEntity.pos.toPos());
    portBlockEntity.trackedStation = null;
  }
}

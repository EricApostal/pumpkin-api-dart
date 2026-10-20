// `FetchPackagesInstruction`'s port loop over the packages of the postboxes connected to a station
// (`FetchPackagesInstruction.java:124-140`), pure. The trains module asks through
// `SchedulePortInventories` (`TrainHost.ports`); the postbox is this module's, so the provider
// lives here and the host part (`port/package_port_part.dart`) only supplies the block entity
// lookup.
import '../../common/pos.dart';
import '../../trains/schedule/schedule_level.dart' show SchedulePortInventories;
import '../../trains/station/global_package_port.dart' show GlobalPackagePort;
import '../../trains/station/mail_transfer.dart' show PackageInventory;
import '../model/package.dart' show PackageItem;
import '../model/stack_tags.dart' show stackFromCTag;

/// The package inventories of the ports of a station, from the loaded postbox when the chunk is
/// loaded and from the port's offline buffer otherwise.
final class PortPackageInventories implements SchedulePortInventories {
  const PortPackageInventories({
    required this.inventoryAt,
    required this.hasDimension,
  });

  /// The package inventory of the port at [pos] of a dimension when its chunk is loaded and a
  /// postbox is there (`dimLevel.getBlockEntity(pos) instanceof PostboxBlockEntity`), else `null`
  /// (the caller falls back to the port's offline buffer).
  final PackageInventory? Function(String dimension, Pos pos) inventoryAt;

  /// `server.getLevel(dimension) != null`.
  final bool Function(String dimension) hasDimension;

  @override
  List<String>? packageAddresses(
    String dimension,
    Pos pos,
    GlobalPackagePort port,
  ) {
    // A station whose dimension has no loaded level is skipped by the instruction.
    if (!hasDimension(dimension)) return null;
    final inventory = inventoryAt(dimension, pos) ?? port.offlineBuffer;

    final addresses = <String>[];
    for (var slot = 0; slot < inventory.getSlots(); slot++) {
      final stack = inventory.getStackInSlot(slot);
      if (stack == null) continue;
      final box = stackFromCTag(stack);
      if (!PackageItem.isPackage(box)) continue;
      addresses.add(PackageItem.getAddress(box));
    }
    return addresses;
  }
}
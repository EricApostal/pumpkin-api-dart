// The `MailTransferHooks` of the logistics module: packages (`PackageItem`), the postboxes of a
// station and the item storage of a carriage's contraption. `GlobalStation.runMailTransfer()`
// reaches both through the small interfaces of `trains/station/mail_transfer.dart`; without these
// hooks it returns at its first check and a train at a station moves no packages.
//
// Java: `GlobalStation.runMailTransfer()` (`content/trains/station/GlobalStation.java:163-250`),
// which imports `PostboxBlockEntity` and reads the carriages' `Carriage.storage.getAllItems()`
// directly.
import '../../api/trains.dart' show GlobalStation;
import '../../common/host_bridge.dart' show PosToHost;
import '../../common/pos.dart';
import '../../contraptions/storage/storage_manager.dart' show MountedStorageManager;
import '../../trains/entity/carriage.dart' show Carriage;
import '../../trains/station/global_package_port.dart' show OfflineBuffer;
import '../../trains/station/mail_transfer.dart'
    show MailTransferHooks, PackageInventory, PostboxHandle;
import '../../trains/util/ctag.dart';
import '../host/runtime.dart' show LgRuntime;
import '../model/package.dart' show PackageItem;
import '../model/stack_tags.dart' show stackFromCTag;
import 'carriage_packages.dart' show CarriagePackageInventory;
import 'package_port_block_entity.dart' show PostboxBlockEntity;
import 'station_ports.dart' show PostboxPackageInventory;

/// The hooks the logistics module installs as [GlobalStation.mailHooks] (`PortPart.onLoad`).
final class PortMailTransferHooks implements MailTransferHooks {
  /// The module's runtime: the postbox lookup and the loaded-dimension check read it.
  final LgRuntime rt;

  PortMailTransferHooks(this.rt);

  @override
  bool isPackage(CTag stack) => PackageItem.isPackage(stackFromCTag(stack));

  @override
  bool matchAddress(CTag stack, String address) =>
      PackageItem.matchBoxAddress(stackFromCTag(stack), address);

  @override
  PackageInventory? carriageInventory(Object carriage) {
    if (carriage is! Carriage) return null;
    final storage = carriage.storage;
    // `carriage.storage.getAllItems()`: the combined handler of the carriage contraption is the
    // `MountedStorageManager` behind a `CarriageStorage` (`TrainCargoManager`); a carriage whose
    // contraption is not assembled has only the read-only `CarriageStorage` view. `allItems`
    // throws before the views are built, which is a carriage mid-assembly.
    if (storage is! MountedStorageManager) return null;
    final manager = storage as MountedStorageManager;
    if (!manager.isInitialized) return null;
    return CarriagePackageInventory(manager.allItems, maxStackSize);
  }

  @override
  PostboxHandle? loadedPostbox(String worldId, Pos pos) {
    // `level != null && level.isLoaded(pos) && level.getBlockEntity(pos) instanceof
    // PostboxBlockEntity`. The store only holds loaded block entities.
    if (rt.world(worldId) == null) return null;
    final postbox = rt.store.typed<PostboxBlockEntity>(worldId, pos.toBlockPos());
    return postbox == null ? null : _PostboxHandle(postbox);
  }

  @override
  int maxStackSize(CTag stack) => OfflineBuffer.stackLimit(stack);
}

/// A loaded `PostboxBlockEntity` (the `box` of `runMailTransfer`).
final class _PostboxHandle implements PostboxHandle {
  final PostboxBlockEntity be;

  @override
  late final PackageInventory inventory = PostboxPackageInventory(be);

  _PostboxHandle(this.be);

  /// `box.computerBehaviour.prepareComputerEvent(new PackageEvent(stack, type))`: the postbox has
  /// no computer behaviour here (Java's is a `ComputerBehaviour` that does nothing without
  /// CC:Tweaked), so the event has no listener.
  @override
  void packageEvent(CTag stack, String type) {}

  @override
  void spawnParticles() => be.spawnParticles();
}
// What the mail transfer of a [GlobalStation] needs from the logistics module (packages, postboxes)
// and from the carriages' storage, as small interfaces over saved item stacks (pure). The module that
// owns the postbox provides a [MailTransferHooks] service; without it no mail is moved.
import '../../common/pos.dart';
import '../util/ctag.dart';

/// `CreateItemHandlerModifiable` of packages: item stacks as their saved compounds (`{id, count,
/// components}`), `null` for an empty slot.
abstract interface class PackageInventory {
  int getSlots();

  CTag? getStackInSlot(int slot);

  void setStackInSlot(int slot, CTag? stack);

  /// `TransferUtil.insertItemStacked(handler, stack, false)`: inserts [stack] where it fits and
  /// returns what is left over (`null` when everything was inserted).
  CTag? insertItemStacked(CTag stack);
}

/// A loaded `PostboxBlockEntity`.
abstract interface class PostboxHandle {
  PackageInventory get inventory;

  /// `computerBehaviour.prepareComputerEvent(new PackageEvent(stack, type))`.
  void packageEvent(CTag stack, String type);

  /// `spawnParticles()`.
  void spawnParticles();
}

abstract interface class MailTransferHooks {
  /// `PackageItem.isPackage(stack)`.
  bool isPackage(CTag stack);

  /// `PackageItem.matchAddress(stack, address)`.
  bool matchAddress(CTag stack, String address);

  /// `carriage.storage.getAllItems()` of the carriage (a `Carriage` of the entity package), `null`
  /// when it has no item storage.
  PackageInventory? carriageInventory(Object carriage);

  /// The postbox at [pos] when its chunk is loaded and it is one, else `null`.
  ///
  /// [dimension] is the station's dimension key (`GlobalStation.getBlockEntityDimension()`,
  /// `minecraft:overworld`); the implementation resolves it to the world it reads the block
  /// entity store with.
  PostboxHandle? loadedPostbox(String dimension, Pos pos);

  /// The stack limit of an item (the offline buffer's merge rule).
  int maxStackSize(CTag stack);
}

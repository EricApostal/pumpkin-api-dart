// What the schedule logic needs from the world and from other modules (pure interfaces).
//
// Java passes a `Level` into `ScheduleRuntime.tick`, `ScheduleWaitCondition.tickCompletion`,
// `ScheduleInstruction.start` and `getWaitingStatus`. The conditions only ask a few questions of
// it (the overworld clock, whether the station is loaded / powered, the filter matching of the
// threshold conditions, the redstone link networks), so the Dart port hands them a
// [ScheduleLevel]: pure, synchronous, and implemented on the host by `HostScheduleLevel`
// (`schedule_host.dart`). Tests use a fake.
//
// The cargo of a carriage (`Carriage.storage`, a `TrainCargoManager` in Java) is seen through
// [TrainCargo]; the contraptions / entity side makes `Carriage.storage` implement it.
import '../../common/pos.dart';
import '../../redstone/link/link_network.dart' show RedstoneLinkNetworkHandler;
import '../station/global_package_port.dart';
import '../util/ctag.dart';
import 'glob_match.dart';

/// An item stack of a carriage inventory, as the conditions read it.
final class CargoItem {
  /// The item registry key (`minecraft:iron_ingot`); `minecraft:air` for an empty slot.
  final String id;
  final int count;
  final int maxStackSize;

  /// `PackageItem.isPackage(stack)`.
  final bool isPackage;

  /// `PackageItem.getAddress(stack)` for packages, else the empty string.
  final String packageAddress;

  /// The stack in the NBT form `ItemStack.CODEC` gives it (`{id, count, components}`), for filters.
  final CTag? tag;

  const CargoItem(
    this.id,
    this.count, {
    this.maxStackSize = 64,
    this.isPackage = false,
    this.packageAddress = '',
    this.tag,
  });

  static const CargoItem empty = CargoItem('minecraft:air', 0);

  bool get isEmpty => count <= 0 || id == 'minecraft:air';

  @override
  String toString() => isEmpty ? 'CargoItem.empty' : 'CargoItem($id x$count)';
}

/// A fluid in a tank of a carriage.
final class CargoFluid {
  final String id;

  /// Amount in millibuckets (`FluidStack.getAmount()`: 1000 per bucket).
  final int amount;

  const CargoFluid(this.id, this.amount);

  bool get isEmpty => amount <= 0 || id == 'minecraft:empty';
}

/// `TrainCargoManager` as the schedule sees it: the item slots and fluid tanks of one carriage and
/// its idle tracker.
abstract interface class TrainCargo {
  /// `getAllItems()`: one entry per slot (empty slots are [CargoItem.empty]).
  List<CargoItem> getAllItems();

  /// `getFluids()`: one entry per tank.
  List<CargoFluid> getFluids();

  /// `getVersion()`: changes whenever the contents changed.
  int getVersion();

  /// `getTicksSinceLastExchange()`.
  int getTicksSinceLastExchange();

  /// `resetIdleCargoTracker()`.
  void resetIdleCargoTracker();

  /// `tickIdleCargoTracker()`.
  void tickIdleCargoTracker();
}

/// `FilterItemStack.test` (logistics): whether a stack passes the filter described by a serialised
/// filter item (`FilterItemStack.serializeNBT`, an empty tag for no filter).
abstract interface class ScheduleFilters {
  /// `filter.test(level, itemStack)` (matchNBT false for the top level filter).
  bool testItem(CTag filter, CargoItem stack);

  /// `filter.test(level, fluidStack)`.
  bool testFluid(CTag filter, CargoFluid stack);
}

/// A filter that lets everything pass when empty and otherwise compares the item key
/// (a plain item filter). Used when the logistics module provides no [ScheduleFilters].
final class PlainScheduleFilters implements ScheduleFilters {
  const PlainScheduleFilters();

  @override
  bool testItem(CTag filter, CargoItem stack) {
    if (filter.isEmpty) return true;
    return filter.getString('id') == stack.id;
  }

  @override
  bool testFluid(CTag filter, CargoFluid stack) {
    if (filter.isEmpty) return true;
    if (stack.isEmpty) return false;
    return filter.getString('id') == stack.id;
  }
}

/// The package inventories of the ports of a station (`GlobalPackagePort.offlineBuffer`, or the
/// `PostboxBlockEntity.inventory` when the postbox is loaded).
abstract interface class SchedulePortInventories {
  /// The addresses of the packages in the inventory of the port at [pos] in [dimension]
  /// (loaded postbox first, else the port's offline buffer). `null` when [dimension] has no
  /// loaded level (the instruction skips such a station).
  List<String>? packageAddresses(String dimension, Pos pos, GlobalPackagePort port);
}

/// The questions the schedule asks of "the level".
abstract interface class ScheduleLevel {
  /// `level.getOverworldClockTime()`: the day time of the overworld in ticks.
  int get overworldClockTime;

  /// `level.getServer() != null`.
  bool get hasServer;

  /// `server.getLevel(dimension) != null`.
  bool hasDimension(String dimension);

  /// `serverLevel.isLoaded(pos)`.
  bool isLoaded(String dimension, Pos pos);

  /// `serverLevel.hasNeighborSignal(pos)`.
  bool hasNeighborSignal(String dimension, Pos pos);

  /// `serverLevel.isPositionEntityTicking(pos)`.
  bool isPositionEntityTicking(String dimension, Pos pos);

  /// The filter matching of the item and fluid threshold conditions.
  ScheduleFilters get filters;

  /// The package ports of stations.
  SchedulePortInventories get ports;

  /// `Create.REDSTONE_LINK_NETWORK_HANDLER`, `null` when the redstone module is not loaded.
  RedstoneLinkNetworkHandler? get redstoneLinks;
}

/// `PackageItem.matchAddress(boxAddress, address)`.
bool matchPackageAddress(String boxAddress, String address) {
  if (address.trim().isEmpty) return boxAddress.trim().isEmpty;
  if (address == '*' || boxAddress == '*') return true;
  if (address == boxAddress) return true;
  return javaMatches(globToRegexOrEmpty(boxAddress), address) || javaMatches(globToRegexOrEmpty(address), boxAddress);
}

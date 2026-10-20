// `TrainCargoManager`: the cargo of a carriage. It is the mounted storage of the carriage
// contraption (Java: `CarriageContraption` starts with one and the train takes it over after
// assembly), plus the idle tracker and version the schedule conditions read.
//
// Java: `content/contraptions/minecart/TrainCargoManager`.
import '../../core/nbt.dart';
import '../../logistics/model/package.dart' show PackageStyles;
import '../../trains/entity/carriage_storage.dart';
import '../../trains/schedule/schedule_level.dart';
import '../../trains/util/ctag.dart';
import '../core/nbt_map.dart';
import 'stacks.dart';
import 'storage_manager.dart';

/// The `create:package_address` component of a saved stack.
const String _packageAddressComponent = 'create:package_address';

/// Vanilla furnace fuels. The host has no reader for the `minecraft:cooking_fuel` component, so
/// the common fuels are listed (`BlazeBurnerBlock.regularFuels` keeps the same table for the
/// burner; it cannot be imported here because it is host coupled).
const Map<String, int> _furnaceFuels = {
  'minecraft:coal': 1600,
  'minecraft:charcoal': 1600,
  'minecraft:coal_block': 16000,
  'minecraft:blaze_rod': 2400,
  'minecraft:lava_bucket': 20000,
  'minecraft:dried_kelp_block': 4000,
  'minecraft:stick': 100,
  'minecraft:bamboo': 50,
  'minecraft:crafting_table': 300,
  'minecraft:bookshelf': 300,
  'minecraft:chest': 300,
  'minecraft:ladder': 300,
};

int? _burnTimeOf(String item) {
  final direct = _furnaceFuels[item];
  if (direct != null) return direct;
  if (!item.startsWith('minecraft:')) return null;
  if (item.endsWith('_planks') ||
      item.endsWith('_log') ||
      item.endsWith('_wood') ||
      item.endsWith('_stem') ||
      item.endsWith('_hyphae') ||
      item.endsWith('_fence') ||
      item.endsWith('_fence_gate') ||
      item.endsWith('_stairs')) {
    return 300;
  }
  if (item.endsWith('_slab')) return 150;
  if (item.endsWith('_sapling') ||
      item.endsWith('_wool') ||
      item.endsWith('_carpet')) {
    return 100;
  }
  return null;
}

/// The crafting remainder of a fuel item (a lava bucket gives its bucket back).
String? _craftingRemainderOf(String item) =>
    item == 'minecraft:lava_bucket' ? 'minecraft:bucket' : null;

final class TrainCargoManager extends MountedStorageManager
    implements CarriageStorage {
  int _ticksSinceLastExchange = 0;
  int _version = 0;

  /// The content the last version was counted for, to notice a change without the change
  /// journals Java wraps its item and fluid handlers in.
  List<CargoItem>? _lastItems;
  List<CargoFluid>? _lastFluids;

  /// The views are built from the mounted storages; before the first block was mounted the
  /// builder maps are still open, so an empty read must not seal them for the assembly that is
  /// about to mount blocks. A manager without blocks therefore reads as empty directly.
  bool get _ready => isInitialized;

  @override
  List<CargoItem> getAllItems() {
    if (!_ready) return const [];
    final slots = allItems;
    return [for (var i = 0; i < slots.slots; i++) _cargoItem(slots.stackInSlot(i))];
  }

  @override
  List<CargoFluid> getFluids() {
    if (!_ready) return const [];
    final tanks = fluids;
    return [
      for (var i = 0; i < tanks.tanks; i++)
        CargoFluid(tanks.fluidInTank(i).fluid, tanks.fluidInTank(i).amount),
    ];
  }

  static CargoItem _cargoItem(StoredStack stack) {
    if (stack.isEmpty) return CargoItem.empty;
    final isPackage = PackageStyles.styleOf(stack.item) != null;
    return CargoItem(
      stack.item,
      stack.count,
      maxStackSize: stack.maxStackSize,
      isPackage: isPackage,
      packageAddress: isPackage ? _addressOf(stack) : '',
      tag: CTag.fromNbt(stack.toNbt().toValue()),
    );
  }

  /// `PackageItem.getAddress(stack)`: the `create:package_address` component as text.
  static String _addressOf(StoredStack stack) {
    final value = stack.components?.map[_packageAddressComponent];
    if (value == null) return '';
    if (value.kind == NbtKind.string) return value.value as String;
    // A logical component is saved as its UTF-8 bytes.
    if (value.kind == NbtKind.byteArray) {
      try {
        return String.fromCharCodes(value.value as List<int>);
      } on Object {
        return '';
      }
    }
    return '';
  }

  @override
  int getVersion() {
    final items = getAllItems();
    final fluids = getFluids();
    if (!_sameItems(items, _lastItems) || !_sameFluids(fluids, _lastFluids)) {
      _version++;
      _lastItems = items;
      _lastFluids = fluids;
      // `changeDetected()`.
      _ticksSinceLastExchange = 0;
    }
    return _version;
  }

  static bool _sameItems(List<CargoItem> a, List<CargoItem>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id || x.count != y.count) return false;
      if (!nbtEquals(x.tag?.toNbt(), y.tag?.toNbt())) return false;
    }
    return true;
  }

  static bool _sameFluids(List<CargoFluid> a, List<CargoFluid>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].amount != b[i].amount) return false;
    }
    return true;
  }

  @override
  int getTicksSinceLastExchange() => _ticksSinceLastExchange;

  @override
  void resetIdleCargoTracker() => _ticksSinceLastExchange = 0;

  @override
  void tickIdleCargoTracker() => _ticksSinceLastExchange++;

  /// `Train.burnFuel`: one fuel item of the first slot with a burn time. The host has no reader
  /// for the vanilla `minecraft:cooking_fuel` component, so the same table the blaze burner uses
  /// stands in for it.
  @override
  int extractFuel() {
    if (!_ready) return 0;
    final slots = fuelItems;
    if (slots == null) return 0;
    for (var slot = 0; slot < slots.slots; slot++) {
      final stack = slots.stackInSlot(slot);
      if (stack.isEmpty) continue;
      final burnTime = _burnTimeOf(stack.item);
      if (burnTime == null || burnTime <= 0) continue;
      final taken = slots.extractItem(slot, 1);
      if (taken.isEmpty) continue;
      final remainder = _craftingRemainderOf(taken.item);
      if (remainder != null) {
        ItemSlotsHelper.insert(slots, StoredStack(remainder, 1));
      }
      return burnTime * taken.count;
    }
    return 0;
  }

  @override
  void writeCargo(CTag tag, bool spawnPacket) {
    final nbt = NbtMap.of(tag.toNbt());
    super.write(nbt, clientPacket: spawnPacket);
    nbt.putInt('TicksSinceLastExchange', _ticksSinceLastExchange);
    for (final entry in nbt.map.entries) {
      tag.entries[entry.key] = entry.value;
    }
  }

  @override
  void readCargo(CTag tag, bool spawnPacket) {
    final nbt = NbtMap.of(tag.toNbt());
    super.read(nbt, clientPacket: spawnPacket);
    _ticksSinceLastExchange = nbt.getInt('TicksSinceLastExchange', 0);
    _lastItems = null;
    _lastFluids = null;
  }
}

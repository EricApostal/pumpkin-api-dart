// Mounted storage (pure): the inventories and tanks a contraption carries. A storage is made from
// the block entity data of a block when the contraption assembles (`mount`), lives in the
// contraption, and is written back into the block entity data when the contraption disassembles
// (`unmount`). The types are looked up by block; other modules register theirs.
import '../../api/block_state.dart';
import '../../core/nbt.dart';
import '../../common/common.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import 'stacks.dart';

// -- Items ------------------------------------------------------------------------------------------------

/// `MountedItemStorageType`: creates the storage of a block and reads it back from NBT.
abstract class MountedItemStorageType {
  /// `create:simple`.
  final String id;

  const MountedItemStorageType(this.id);

  /// `MountedItemStorageType.mount`: the storage of the block, `null` if it has none.
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be);

  /// Reads a storage of this type from the compound saved by [MountedItemStorage.encode].
  MountedItemStorage decode(NbtMap tag);

  /// Whether storages of this type are hidden from the combined contraption inventory
  /// (`create:internal`).
  bool get isInternal => false;

  /// Whether the storage must not provide fuel (`create:fuel_blacklist`).
  bool get isFuelBlacklisted => false;
}

/// `MountedItemStorage`: the items of one block of a contraption.
abstract class MountedItemStorage implements ItemSlots {
  final MountedItemStorageType type;

  MountedItemStorage(this.type);

  /// Writes the fields of this storage next to `type` (`value`, ...).
  void writeFields(NbtMap tag);

  /// The storage as `MountedItemStorage.CODEC` saves it: `{type, ...fields}`.
  NbtMap encode() {
    final t = NbtMap()..putString('type', type.id);
    writeFields(t);
    return t;
  }

  /// `unmount`: puts the items back into the saved block entity data [be] of the block that
  /// comes back to the world; returns the data to place (may be [be] itself or a new compound).
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be);

  /// Whether a player can open this storage (`handleInteraction` opens a menu).
  bool get canOpen => true;

  /// The title of the menu, a block translation.
  String menuBlockName(StructureBlockInfo info) => info.state.key;

  /// The sound played when the menu opens, `null` for none.
  String? get openingSound => 'minecraft:block.barrel.open';

  /// The sound played when the menu closes.
  String? get closingSound => null;

  /// Number of menu rows, 0 if it cannot be shown (storages that are not 1-6 rows of 9 slots).
  int get menuRows => slots > 0 && slots % 9 == 0 && slots <= 54 ? slots ~/ 9 : 0;
}

/// `SyncedMountedStorage`: a storage whose changes are sent to clients.
mixin SyncedMountedStorage {
  bool dirty = false;

  bool get isDirty => dirty;

  void markClean() => dirty = false;
}

/// `WrapperMountedItemStorage`: a storage backed by an [ItemStackHandler].
abstract class WrapperMountedItemStorage extends MountedItemStorage {
  final ItemStackHandler wrapped;

  WrapperMountedItemStorage(super.type, this.wrapped);

  @override
  int get slots => wrapped.slots;

  @override
  StoredStack stackInSlot(int slot) => wrapped.stackInSlot(slot);

  @override
  void setStackInSlot(int slot, StoredStack stack) => wrapped.setStackInSlot(slot, stack);

  @override
  StoredStack insertItem(int slot, StoredStack stack, {bool simulate = false}) =>
      wrapped.insertItem(slot, stack, simulate: simulate);

  @override
  StoredStack extractItem(int slot, int amount, {bool simulate = false}) =>
      wrapped.extractItem(slot, amount, simulate: simulate);

  @override
  int slotLimit(int slot) => wrapped.slotLimit(slot);

  @override
  bool isItemValid(int slot, StoredStack stack) => wrapped.isItemValid(slot, stack);

  @override
  void writeFields(NbtMap tag) => tag.putCompound('value', wrapped.serialize());
}

/// The number of slots of a vanilla container block.
int vanillaContainerSize(String blockKey) {
  final p = blockKey.contains(':') ? blockKey.substring(blockKey.indexOf(':') + 1) : blockKey;
  if (p == 'hopper' || p == 'brewing_stand') return 5;
  if (p == 'dispenser' || p == 'dropper' || p == 'crafter') return 9;
  if (p == 'furnace' || p == 'blast_furnace' || p == 'smoker') return 3;
  if (p == 'chiseled_bookshelf') return 6;
  if (p == 'decorated_pot' || p == 'lectern' || p == 'jukebox') return 1;
  return 27;
}

/// A vanilla container saves its items as `Items: [{Slot, id, count}]`.
ItemStackHandler _handlerFromVanillaItems(NbtMap be, int size) {
  final h = ItemStackHandler(size);
  for (final v in be.getList('Items')) {
    final t = NbtMap.of(v);
    final slot = t.getInt('Slot', -1);
    if (slot >= 0 && slot < size) h.stacks[slot] = StoredStack.fromNbt(t);
  }
  return h;
}

void _writeVanillaItems(NbtMap be, ItemSlots from) {
  final items = <NbtValue>[];
  for (var i = 0; i < from.slots; i++) {
    final s = from.stackInSlot(i);
    if (s.isEmpty) continue;
    items.add((s.toNbt()..putByte('Slot', i)).toValue());
  }
  be.putList('Items', items);
}

/// `SimpleMountedStorage`: the items of a vanilla container block entity (`Items`).
class SimpleMountedStorage extends WrapperMountedItemStorage {
  SimpleMountedStorage(super.type, super.wrapped);

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) {
    if (be == null) return null;
    final size = vanillaContainerSize(info.state.key);
    if (size != slots) return be;
    _writeVanillaItems(be, this);
    return be;
  }
}

/// `ChestMountedStorage`: opens the combined menu of a double chest.
class ChestMountedStorage extends SimpleMountedStorage {
  ChestMountedStorage(super.type, super.wrapped);

  @override
  String? get openingSound => 'minecraft:block.chest.open';

  @override
  String? get closingSound => 'minecraft:block.chest.close';
}

/// `DispenserMountedStorage`: a 9x9 menu, silent.
class DispenserMountedStorage extends SimpleMountedStorage {
  DispenserMountedStorage(super.type, super.wrapped);

  @override
  String? get openingSound => null;
}

/// The mounted storage of block entities that keep an item handler in the `Inventory` compound
/// (`FallbackMountedStorage`: modded and Create block entities with a plain handler).
class FallbackMountedStorage extends WrapperMountedItemStorage {
  FallbackMountedStorage(super.type, super.wrapped);

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) {
    if (be == null) return null;
    final inv = be.getCompoundOrNull('Inventory');
    if (inv == null || inv.getInt('Size', slots) != slots) return be;
    be.putCompound('Inventory', wrapped.serialize());
    return be;
  }
}

/// The type of vanilla containers read from `Items` (`create:simple`).
class SimpleMountedStorageType extends MountedItemStorageType {
  const SimpleMountedStorageType([super.id = 'create:simple']);

  SimpleMountedStorage create(ItemStackHandler h) => SimpleMountedStorage(this, h);

  @override
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be) {
    if (be == null) return null;
    return create(_handlerFromVanillaItems(be.saved, vanillaContainerSize(state.key)));
  }

  @override
  MountedItemStorage decode(NbtMap tag) => create(ItemStackHandler.fromNbt(tag.getCompound('value')));
}

/// `create:chest`.
class ChestMountedStorageType extends SimpleMountedStorageType {
  const ChestMountedStorageType() : super('create:chest');

  @override
  SimpleMountedStorage create(ItemStackHandler h) => ChestMountedStorage(this, h);
}

/// `create:dispenser` (dispensers and droppers).
class DispenserMountedStorageType extends SimpleMountedStorageType {
  const DispenserMountedStorageType() : super('create:dispenser');

  @override
  SimpleMountedStorage create(ItemStackHandler h) => DispenserMountedStorage(this, h);

  @override
  bool get isInternal => true;
}

/// `create:fallback`.
class FallbackMountedStorageType extends MountedItemStorageType {
  const FallbackMountedStorageType() : super('create:fallback');

  @override
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be) {
    if (be == null) return null;
    final inv = be.saved.getCompoundOrNull('Inventory');
    if (inv == null || !inv.contains('Items') || !inv.contains('Size')) return null;
    return FallbackMountedStorage(this, ItemStackHandler.fromNbt(inv));
  }

  @override
  MountedItemStorage decode(NbtMap tag) => FallbackMountedStorage(this, ItemStackHandler.fromNbt(tag.getCompound('value')));
}

/// The vault's storage (`create:vault`): the `Inventory` of the controller block entity.
class VaultMountedStorage extends WrapperMountedItemStorage {
  VaultMountedStorage(super.type, super.wrapped);

  @override
  bool get canOpen => false;

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) {
    if (be == null) return null;
    // `ItemVaultBlockEntity.applyInventoryToBlock`: the slots are copied one by one.
    final size = be.getCompoundOrNull('Inventory')?.getInt('Size', slots) ?? slots;
    final out = ItemStackHandler(size);
    for (var i = 0; i < size; i++) {
      out.stacks[i] = i < slots ? stackInSlot(i) : StoredStack.empty;
    }
    be.putCompound('Inventory', out.serialize());
    return be;
  }
}

class VaultMountedStorageType extends MountedItemStorageType {
  const VaultMountedStorageType() : super('create:vault');

  @override
  bool get isFuelBlacklisted => true;

  @override
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be) {
    if (be == null) return null;
    final inv = be.saved.getCompoundOrNull('Inventory');
    if (inv == null) return null;
    return VaultMountedStorage(this, ItemStackHandler.fromNbt(inv));
  }

  @override
  MountedItemStorage decode(NbtMap tag) => VaultMountedStorage(this, ItemStackHandler.fromNbt(tag.getCompound('value')));
}

/// The toolbox storage (`create:toolbox`): the `Inventory` compound (stacks and filters) of the toolbox.
class ToolboxMountedStorage extends WrapperMountedItemStorage {
  /// The rest of the saved inventory (compartment filters) that is kept as it was.
  final NbtMap extras;

  ToolboxMountedStorage(super.type, super.wrapped, this.extras);

  @override
  bool get canOpen => false;

  @override
  void writeFields(NbtMap tag) {
    final v = wrapped.serialize();
    for (final e in extras.map.entries) {
      v[e.key] = copyValue(e.value);
    }
    tag.putCompound('value', v);
  }

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) {
    if (be == null) return null;
    final inv = be.getCompoundOrNull('Inventory') ?? NbtMap();
    final size = inv.getInt('Size', slots);
    final out = ItemStackHandler(size);
    for (var i = 0; i < size && i < slots; i++) {
      out.stacks[i] = stackInSlot(i);
    }
    final v = out.serialize();
    for (final e in extras.map.entries) {
      v[e.key] = copyValue(e.value);
    }
    be.putCompound('Inventory', v);
    return be;
  }
}

class ToolboxMountedStorageType extends MountedItemStorageType {
  const ToolboxMountedStorageType() : super('create:toolbox');

  static const _handlerKeys = {'Size', 'Items'};

  ToolboxMountedStorage _from(NbtMap inv) {
    final extras = NbtMap({
      for (final e in inv.map.entries)
        if (!_handlerKeys.contains(e.key)) e.key: copyValue(e.value),
    });
    return ToolboxMountedStorage(this, ItemStackHandler.fromNbt(inv), extras);
  }

  @override
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be) {
    final inv = be?.saved.getCompoundOrNull('Inventory');
    return inv == null ? null : _from(inv);
  }

  @override
  MountedItemStorage decode(NbtMap tag) => _from(tag.getCompound('value'));
}

/// The depot storage (`create:depot`): one slot, the held item.
class DepotMountedStorage extends WrapperMountedItemStorage with SyncedMountedStorage {
  DepotMountedStorage(MountedItemStorageType type, StoredStack held) : super(type, ItemStackHandler.of([held])) {
    wrapped.onChange = (_) => dirty = true;
  }

  StoredStack get item => stackInSlot(0);

  set item(StoredStack s) => setStackInSlot(0, s);

  @override
  bool get canOpen => false;

  @override
  void writeFields(NbtMap tag) => tag.putCompound('value', item.isEmpty ? NbtMap() : item.toNbt());

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) {
    if (be == null) return null;
    // `DepotBlockEntity.setHeldItem`: a new transported stack that keeps the old angle.
    final held = be.getCompoundOrNull('HeldItem');
    if (item.isEmpty) {
      be.remove('HeldItem');
      return be;
    }
    final t = held ?? (NbtMap()
      ..putFloat('Pos', 0)
      ..putFloat('PrevPos', 0)
      ..putFloat('Offset', 0)
      ..putFloat('PrevOffset', 0)
      ..putInt('InSegment', 0)
      ..putInt('Angle', 0)
      ..putInt('InDirection', 0));
    t.putCompound('Item', item.toNbt());
    be.putCompound('HeldItem', t);
    return be;
  }
}

class DepotMountedStorageType extends MountedItemStorageType {
  const DepotMountedStorageType() : super('create:depot');

  @override
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be) {
    if (be == null) return null;
    final held = be.saved.getCompoundOrNull('HeldItem');
    return DepotMountedStorage(this, held == null ? StoredStack.empty : StoredStack.fromNbt(held.getCompoundOrNull('Item')));
  }

  @override
  MountedItemStorage decode(NbtMap tag) {
    final v = tag.getCompound('value');
    return DepotMountedStorage(this, v.isEmpty ? StoredStack.empty : StoredStack.fromNbt(v));
  }
}

/// The creative crate storage (`create:creative_crate`): endlessly supplies its stack.
class CreativeCrateMountedStorage extends MountedItemStorage {
  final StoredStack suppliedStack;
  late final StoredStack _cached = suppliedStack.copyWithCount(suppliedStack.maxStackSize);

  CreativeCrateMountedStorage(super.type, this.suppliedStack);

  @override
  int get slots => 2;

  @override
  StoredStack stackInSlot(int slot) => slot == 0 ? _cached : StoredStack.empty;

  @override
  void setStackInSlot(int slot, StoredStack stack) {}

  @override
  StoredStack insertItem(int slot, StoredStack stack, {bool simulate = false}) => StoredStack.empty;

  @override
  StoredStack extractItem(int slot, int amount, {bool simulate = false}) {
    if (slot == 0 && suppliedStack.isNotEmpty) {
      final count = amount < suppliedStack.maxStackSize ? amount : suppliedStack.maxStackSize;
      return suppliedStack.copyWithCount(count);
    }
    return StoredStack.empty;
  }

  @override
  int slotLimit(int slot) => 64;

  @override
  bool isItemValid(int slot, StoredStack stack) => true;

  @override
  bool get canOpen => false;

  @override
  void writeFields(NbtMap tag) => tag.putCompound('value', suppliedStack.isEmpty ? NbtMap() : suppliedStack.toNbt());

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) => be;
}

class CreativeCrateMountedStorageType extends MountedItemStorageType {
  const CreativeCrateMountedStorageType() : super('create:creative_crate');

  @override
  MountedItemStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be) {
    if (be == null) return null;
    // `CreativeCrateBlockEntity`: the supplied stack is the filter of the filtering behaviour.
    final filter = be.saved.getCompoundOrNull('Filter');
    final stack = filter == null ? StoredStack.empty : StoredStack.fromNbt(filter);
    return CreativeCrateMountedStorage(this, stack);
  }

  @override
  MountedItemStorage decode(NbtMap tag) {
    final v = tag.getCompound('value');
    return CreativeCrateMountedStorage(this, v.isEmpty ? StoredStack.empty : StoredStack.fromNbt(v));
  }
}

// -- Fluids -----------------------------------------------------------------------------------------------

/// `MountedFluidStorageType`.
abstract class MountedFluidStorageType {
  final String id;

  const MountedFluidStorageType(this.id);

  MountedFluidStorage? mount(ContraptionLevel level, BState state, Pos pos, CapturedBlockEntity? be, ContraptionSettings settings);

  MountedFluidStorage decode(NbtMap tag);
}

/// `MountedFluidStorage`.
abstract class MountedFluidStorage implements FluidTanks {
  final MountedFluidStorageType type;

  MountedFluidStorage(this.type);

  void writeFields(NbtMap tag);

  NbtMap encode() {
    final t = NbtMap()..putString('type', type.id);
    writeFields(t);
    return t;
  }

  /// `unmount`: puts the fluid back into the saved data of the block entity.
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be);
}

/// `FluidTankMountedStorage`: the content of a fluid tank (the controller block entity).
class FluidTankMountedStorage extends MountedFluidStorage with SyncedMountedStorage {
  final SingleFluidTank tank;

  FluidTankMountedStorage(MountedFluidStorageType type, int capacity, StoredFluid fluid)
    : tank = SingleFluidTank(capacity, fluid),
      super(type) {
    tank.onChange = () => dirty = true;
  }

  StoredFluid get fluid => tank.fluid;

  int get capacity => tank.capacity;

  @override
  int get tanks => 1;

  @override
  StoredFluid fluidInTank(int t) => tank.fluidInTank(t);

  @override
  int tankCapacity(int t) => tank.tankCapacity(t);

  @override
  bool isFluidValid(int t, StoredFluid f) => tank.isFluidValid(t, f);

  @override
  int fill(StoredFluid f, {bool simulate = false}) => tank.fill(f, simulate: simulate);

  @override
  StoredFluid drain(int max, {bool simulate = false}) => tank.drain(max, simulate: simulate);

  @override
  StoredFluid drainFluid(StoredFluid f, {bool simulate = false}) => tank.drainFluid(f, simulate: simulate);

  @override
  void writeFields(NbtMap tag) {
    tag.putInt('capacity', capacity);
    tag.putCompound('fluid', fluid.isEmpty ? NbtMap() : fluid.toNbt());
  }

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) {
    if (be == null || !isControllerNbt(be)) return be;
    // The capacity stays as it is; only the fluid changes.
    be.putCompound('TankContent', fluid.isEmpty ? NbtMap() : fluid.toNbt());
    return be;
  }
}

/// A multiblock controller does not store a `Controller` position.
bool isControllerNbt(NbtMap be) => !be.contains('Controller');

class FluidTankMountedStorageType extends MountedFluidStorageType {
  const FluidTankMountedStorageType() : super('create:fluid_tank');

  @override
  MountedFluidStorage? mount(
    ContraptionLevel level,
    BState state,
    Pos pos,
    CapturedBlockEntity? be,
    ContraptionSettings settings,
  ) {
    if (be == null || !isControllerNbt(be.saved)) return null;
    final width = be.saved.getInt('Size');
    final height = be.saved.getInt('Height');
    final capacity = width * width * height * settings.fluidTankCapacity * 1000;
    final content = be.saved.getCompoundOrNull('TankContent');
    return FluidTankMountedStorage(this, capacity, content == null ? StoredFluid.empty : StoredFluid.fromNbt(content));
  }

  @override
  MountedFluidStorage decode(NbtMap tag) {
    final fluid = tag.getCompoundOrNull('fluid');
    return FluidTankMountedStorage(this, tag.getInt('capacity'), fluid == null ? StoredFluid.empty : StoredFluid.fromNbt(fluid));
  }
}

/// `CreativeFluidTankMountedStorage`: endlessly supplies its fluid.
class CreativeFluidTankMountedStorage extends MountedFluidStorage {
  final int capacity;
  final StoredFluid contained;

  CreativeFluidTankMountedStorage(super.type, this.capacity, this.contained);

  @override
  int get tanks => 1;

  @override
  StoredFluid fluidInTank(int tank) => contained.isEmpty ? StoredFluid.empty : contained.copyWithAmount(capacity);

  @override
  int tankCapacity(int tank) => capacity;

  @override
  bool isFluidValid(int tank, StoredFluid fluid) => contained.isEmpty || contained.isFluidEqual(fluid);

  @override
  int fill(StoredFluid fluid, {bool simulate = false}) => contained.isEmpty ? 0 : fluid.amount;

  @override
  StoredFluid drain(int maxAmount, {bool simulate = false}) =>
      contained.isEmpty ? StoredFluid.empty : contained.copyWithAmount(maxAmount < capacity ? maxAmount : capacity);

  @override
  StoredFluid drainFluid(StoredFluid fluid, {bool simulate = false}) =>
      contained.isEmpty || !contained.isFluidEqual(fluid) ? StoredFluid.empty : drain(fluid.amount);

  @override
  void writeFields(NbtMap tag) {
    tag.putCompound(
      'value',
      NbtMap()
        ..putInt('capacity', capacity)
        ..putCompound('fluid', contained.isEmpty ? NbtMap() : contained.toNbt()),
    );
  }

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) => be;
}

class CreativeFluidTankMountedStorageType extends MountedFluidStorageType {
  const CreativeFluidTankMountedStorageType() : super('create:creative_fluid_tank');

  @override
  MountedFluidStorage? mount(
    ContraptionLevel level,
    BState state,
    Pos pos,
    CapturedBlockEntity? be,
    ContraptionSettings settings,
  ) {
    if (be == null || !isControllerNbt(be.saved)) return null;
    final width = be.saved.getInt('Size');
    final height = be.saved.getInt('Height');
    final capacity = width * width * height * settings.fluidTankCapacity * 1000;
    // `CreativeFluidTankBlockEntity`: the tank content is the supplied fluid.
    final content = be.saved.getCompoundOrNull('TankContent');
    return CreativeFluidTankMountedStorage(this, capacity, content == null ? StoredFluid.empty : StoredFluid.fromNbt(content));
  }

  @override
  MountedFluidStorage decode(NbtMap tag) {
    final v = tag.getCompound('value');
    final fluid = v.getCompoundOrNull('fluid');
    return CreativeFluidTankMountedStorage(this, v.getInt('capacity'), fluid == null ? StoredFluid.empty : StoredFluid.fromNbt(fluid));
  }
}

// -- The registry -------------------------------------------------------------------------------------------

/// The mounted storage types and which block uses which (`MountedItemStorageType.REGISTRY`,
/// `MountedFluidStorageType.REGISTRY`, `AllMountedStorageTypes`).
abstract final class MountedStorages {
  static final Map<String, MountedItemStorageType> itemTypes = {};
  static final Map<String, MountedFluidStorageType> fluidTypes = {};
  static final _itemByBlock = <String, MountedItemStorageType>{};
  static final _itemByTag = <(String, MountedItemStorageType)>[];
  static final _fluidByBlock = <String, MountedFluidStorageType>{};

  /// The block tag of blocks that must never use the fallback (`create:fallback_mounted_storage_blacklist`).
  static String fallbackBlacklistTag = 'create:fallback_mounted_storage_blacklist';

  static const MountedItemStorageType fallback = FallbackMountedStorageType();
  static const MountedItemStorageType simple = SimpleMountedStorageType();
  static const MountedItemStorageType chest = ChestMountedStorageType();
  static const MountedItemStorageType dispenser = DispenserMountedStorageType();
  static const MountedItemStorageType vault = VaultMountedStorageType();
  static const MountedItemStorageType toolbox = ToolboxMountedStorageType();
  static const MountedItemStorageType depot = DepotMountedStorageType();
  static const MountedItemStorageType creativeCrate = CreativeCrateMountedStorageType();
  static const MountedFluidStorageType fluidTank = FluidTankMountedStorageType();
  static const MountedFluidStorageType creativeFluidTank = CreativeFluidTankMountedStorageType();

  static bool _installed = false;

  /// Registers Create's own types and the blocks that use them. Safe to call twice.
  static void installDefaults() {
    if (_installed) return;
    _installed = true;
    for (final t in [fallback, simple, chest, dispenser, vault, toolbox, depot, creativeCrate]) {
      registerItemType(t);
    }
    registerFluidType(fluidTank);
    registerFluidType(creativeFluidTank);
    // Associations of the types that belong to vanilla blocks and tags
    // (AllMountedStorageTypes: SIMPLE and CHEST by tag, DISPENSER by block).
    associateItemTag('create:simple_mounted_storage', simple);
    associateItemTag('create:chest_mounted_storage', chest);
    associateItem('minecraft:dispenser', dispenser);
    associateItem('minecraft:dropper', dispenser);
    // The blocks of the other modules (`BlockBuilder.transform(mountedItemStorage(...))`).
    associateItem('create:item_vault', vault);
    associateItem('create:creative_crate', creativeCrate);
    associateItem('create:depot', depot);
    associateItem('create:weighted_ejector', depot);
    for (final c in dyeColors) {
      associateItem('create:${c}_toolbox', toolbox);
    }
    associateItem('create:toolbox', toolbox);
    associateFluid('create:fluid_tank', fluidTank);
    associateFluid('create:creative_fluid_tank', creativeFluidTank);
  }

  static void registerItemType(MountedItemStorageType type) => itemTypes[type.id] = type;

  static void registerFluidType(MountedFluidStorageType type) => fluidTypes[type.id] = type;

  /// Uses [type] for the block [blockKey].
  static void associateItem(String blockKey, MountedItemStorageType type) => _itemByBlock[blockKey] = type;

  /// Uses [type] for all blocks of [tag].
  static void associateItemTag(String tag, MountedItemStorageType type) => _itemByTag.add((tag, type));

  static void associateFluid(String blockKey, MountedFluidStorageType type) => _fluidByBlock[blockKey] = type;

  /// The item type of a block state: its registration, then the fallback.
  static MountedItemStorageType? itemTypeOf(BState state, ContraptionLevel level) {
    final byBlock = _itemByBlock[state.key];
    if (byBlock != null) return byBlock;
    for (final (tag, type) in _itemByTag) {
      if (level.stateHasTag(state, tag)) return type;
    }
    return level.stateHasTag(state, fallbackBlacklistTag) ? null : fallback;
  }

  static MountedFluidStorageType? fluidTypeOf(BState state) => _fluidByBlock[state.key];

  /// Reads a saved item storage (`MountedItemStorage.CODEC`).
  static MountedItemStorage? decodeItem(NbtMap tag) {
    final type = itemTypes[tag.getString('type')];
    return type?.decode(tag);
  }

  static MountedFluidStorage? decodeFluid(NbtMap tag) {
    final type = fluidTypes[tag.getString('type')];
    return type?.decode(tag);
  }
}

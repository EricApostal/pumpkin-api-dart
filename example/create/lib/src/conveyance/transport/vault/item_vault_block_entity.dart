// `ItemVaultBlockEntity` (server behaviour): the vault's multiblock (up to 3x3 blocks wide and
// three times as long), its inventory (one `vaultCapacity`-slot handler per block, seen as one
// combined inventory), and the comparator output.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../fluids/connectivity.dart';
import '../../../fluids/fluid_stack.dart';
import '../../../fluids/fluid_storage.dart';
import '../../items/inventory.dart';
import '../../items/item_codec.dart';
import '../../runtime.dart';
import '../transport_inventory_api.dart';
import '../transport_support.dart';

/// `ItemVaultBlockEntity`: one part of a vault multiblock.
class ItemVaultBlockEntity extends CreateBlockEntity
    implements MultiPart, ItemInventoryProvider {
  late final ListInventory inventory;
  Pos? _controller;

  /// `getLastKnownPos`: the part's own position, tracked so a moved (pushed) vault splits.
  Pos? _lastKnownPos;
  bool _updateConnectivity = false;
  int radius = 1;
  int length = 1;
  Object? _extraData;

  ItemVaultBlockEntity(super.worldId, super.pos) {
    inventory = ListInventory(
      ConveyanceRuntime.i.vaultCapacity,
      onChanged: (_) {
        markDirty();
        sendData();
      },
    );
  }

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  BState get state => rt.stateAt(worldId, this.pos.toPos());

  // -- MultiPart -------------------------------------------------------------------------------

  @override
  String get partType => 'create:item_vault';

  @override
  Pos get partPos => this.pos.toPos();

  @override
  bool get isRemoved => removed;

  @override
  bool get isController => _controller == null || _controller == partPos;

  @override
  Pos get controller => isController ? partPos : _controller!;

  @override
  MultiPart? get controllerPart {
    final be = rt.beAt(worldId, controller);
    return be is MultiPart ? be as MultiPart : null;
  }

  @override
  void setController(Pos pos) {
    if (_controller == pos) return;
    _controller = pos;
    markDirty();
    sendData();
  }

  @override
  void removeController(bool keepContents) {
    _updateConnectivity = true;
    _controller = null;
    radius = 1;
    length = 1;
    if (!keepContents) inventory.clear();
    final blockState = state;
    if (isVaultState(blockState) && blockState.flag('large')) {
      final world = rt.worldOf(worldId);
      if (world != null) {
        rt.fire(
          'Updating the vault state',
          () => writeState(world, partPos, blockState.setFlag('large', false)),
        );
      }
    }
    markDirty();
    sendData();
  }

  @override
  void preventConnectivityUpdate() => _updateConnectivity = false;

  @override
  void notifyMultiUpdated() {
    final blockState = state;
    final world = rt.worldOf(worldId);
    if (world != null && isVaultState(blockState)) {
      rt.fire(
        'Updating the vault state',
        () =>
            writeState(world, partPos, blockState.setFlag('large', radius > 2)),
      );
    }
    markDirty();
    sendData();
  }

  @override
  Object? get extraData => _extraData;

  @override
  set extraData(Object? data) => _extraData = data;

  @override
  Object? modifyExtraData(Object? data) => data;

  @override
  Axis get mainConnectionAxis => state.axisOf('axis') ?? Axis.x;

  @override
  int getMaxLength(Axis longAxis, int width) =>
      longAxis == Axis.y ? maxWidth : width * 3;

  @override
  int get maxWidth => 3;

  @override
  int get height => length;

  @override
  set height(int value) => length = value;

  @override
  int get width => radius;

  @override
  set width(int value) => radius = value;

  // The vault has no tanks; `ConnectivityHandler` only asks when `hasTank` is true.
  @override
  bool get hasTank => false;

  @override
  int getTankSize(int tank) => 0;

  @override
  void setTankSize(int tank, int blocks) {}

  @override
  FluidTank? getTank(int tank) => null;

  @override
  FStack getFluid(int tank) => FStack.empty;

  // -- Lifecycle -------------------------------------------------------------------------------

  @override
  void initialize() {
    super.initialize();
    updateConnectivity();
  }

  @override
  void tick() {
    super.tick();

    // `tick`: a part that is no longer where it was has to split and re-form.
    if (_lastKnownPos == null) {
      _lastKnownPos = partPos;
    } else if (_lastKnownPos != partPos) {
      removeController(true);
      _lastKnownPos = partPos;
      return;
    }

    if (_updateConnectivity) updateConnectivity();
  }

  void updateConnectivity() {
    _updateConnectivity = false;
    if (!isController) return;
    ConnectivityHandler.formMulti(_VaultWorld(worldId), this);
  }

  @override
  void onRemoved() {
    super.onRemoved();
    ConnectivityHandler.splitMulti(_VaultWorld(worldId), this);
    final world = this.world;
    if (world != null) {
      for (var i = 0; i < inventory.slots; i++) {
        final stack = inventory.getStack(i);
        if (stack.isNotEmpty) {
          rt.fire(
            'Dropping the vault contents',
            () => dropItemAt(world, partPos, stack),
          );
        }
      }
    }
  }

  // -- Inventory -------------------------------------------------------------------------------

  @override
  ItemInventory? itemInventory(Direction? side) {
    final controller = isController
        ? this
        : rt.typedAt<ItemVaultBlockEntity>(worldId, this.controller);
    return controller?._combinedInventory();
  }

  ItemInventory _combinedInventory() {
    final parts = <ItemInventory>[];
    final axis = mainConnectionAxis;
    for (var y = 0; y < length; y++) {
      for (var x = 0; x < radius; x++) {
        for (var z = 0; z < radius; z++) {
          final p = _partPosition(axis, partPos, y, x, z);
          final be = rt.typedAt<ItemVaultBlockEntity>(worldId, p);
          parts.add(be?.inventory ?? ListInventory(rt.vaultCapacity));
        }
      }
    }
    return CombinedInventory(parts);
  }

  static Pos _partPosition(
    Axis axis,
    Pos origin,
    int yOffset,
    int xOffset,
    int zOffset,
  ) => switch (axis) {
    Axis.x => origin.offset(yOffset, xOffset, zOffset),
    Axis.y => origin.offset(xOffset, yOffset, zOffset),
    Axis.z => origin.offset(xOffset, zOffset, yOffset),
  };

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    if (_updateConnectivity) tag.putBool('Uninitialized', true);
    final last = _lastKnownPos;
    if (last != null)
      tag.putIntArray('LastKnownPos', [last.$1, last.$2, last.$3]);
    if (!isController)
      tag.putIntArray('Controller', [
        controller.$1,
        controller.$2,
        controller.$3,
      ]);
    if (isController) {
      tag
        ..putInt('Size', radius)
        ..putInt('Length', length);
    }
    super.write(tag, clientPacket: clientPacket);
    if (!clientPacket) {
      tag
        ..putString('StorageType', 'CombinedInv')
        ..putCompound('Inventory', _writeInventory());
    }
  }

  NbtCompound _writeInventory() {
    final items = <Object>[];
    for (var i = 0; i < inventory.slots; i++) {
      final stack = inventory.getStack(i);
      if (stack.isEmpty) continue;
      items.add(
        (ItemCodec.toNbt(stack)
          ..putString('id', stack.key)
          ..putInt('count', stack.count)
          ..putInt('Slot', i)),
      );
    }
    return NbtCompound()
      ..putInt('Size', inventory.slots)
      ..putList('Items', items);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    // `compound.contains("Uninitialized")`, not its value: the marker only exists when set.
    _updateConnectivity = tag.containsKey('Uninitialized');
    _lastKnownPos = null;
    final lk = tag.getIntArray('LastKnownPos');
    if (lk != null && lk.length >= 3) _lastKnownPos = (lk[0], lk[1], lk[2]);
    _controller = null;
    final c = tag.getIntArray('Controller');
    if (c != null && c.length >= 3) _controller = (c[0], c[1], c[2]);
    if (isController) {
      radius = tag.getInt('Size') ?? 0;
      length = tag.getInt('Length') ?? 0;
    }
    if (clientPacket) return;
    _readInventory(tag.getCompound('Inventory'));
  }

  void _readInventory(NbtCompound? inv) {
    if (inv == null) return;
    final size = inv.getInt('Size') ?? inventory.slots;
    inventory.resize(size);
    for (final e in inv.getList('Items') ?? const <Object>[]) {
      if (e is! NbtCompound) continue;
      final slot = e.getInt('Slot') ?? -1;
      if (slot < 0 || slot >= inventory.slots) continue;
      inventory.setStack(slot, ItemCodec.fromAnyNbt(e));
    }
  }
}

/// The world view `ConnectivityHandler` needs for the vault parts.
MultiPartWorld vaultMultiWorld(String worldId) => _VaultWorld(worldId);

final class _VaultWorld implements MultiPartWorld {
  final String worldId;

  _VaultWorld(this.worldId);

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  @override
  MultiPart? partAt(String type, Pos pos) {
    final be = rt.beAt(worldId, pos);
    if (be is MultiPart &&
        (be as MultiPart).partType == type &&
        !(be as MultiPart).isRemoved)
      return be as MultiPart;
    return null;
  }

  @override
  MultiPart? anyPartAt(Pos pos) {
    final be = rt.beAt(worldId, pos);
    return be is MultiPart ? be as MultiPart : null;
  }

  @override
  void invalidateCapabilities(Pos pos) {}
}

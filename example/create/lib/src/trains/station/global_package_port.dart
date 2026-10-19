// `GlobalPackagePort` (pure): a postbox connected to a station, remembered by the graph so that mail
// can be moved while the postbox' chunk is unloaded (the offline buffer).
import '../manager/create.dart';
import '../util/ctag.dart';
import 'mail_transfer.dart';

/// `CreateItemStackHandler(18)` over saved item stacks.
class OfflineBuffer implements PackageInventory {
  /// `maxStackSize` of the stacks (set by the owner of the package items).
  static int Function(CTag stack) stackLimit = (_) => 64;

  final List<CTag?> stacks;

  OfflineBuffer([int size = 18]) : stacks = List<CTag?>.filled(size, null);

  @override
  int getSlots() => stacks.length;

  @override
  CTag? getStackInSlot(int slot) => stacks[slot];

  @override
  void setStackInSlot(int slot, CTag? stack) {
    stacks[slot] = stack == null || stack.getInt('count') <= 0 ? null : stack;
  }

  static bool _sameItem(CTag a, CTag b) {
    final ca = a.copy()..putInt('count', 1);
    final cb = b.copy()..putInt('count', 1);
    return _equalTags(ca, cb);
  }

  static bool _equalTags(CTag a, CTag b) => a.toJson().toString() == b.toJson().toString();

  @override
  CTag? insertItemStacked(CTag stack) {
    var remaining = stack.getInt('count');
    final limit = stackLimit(stack);
    // merge into existing stacks first
    for (var i = 0; i < stacks.length && remaining > 0; i++) {
      final existing = stacks[i];
      if (existing == null || !_sameItem(existing, stack)) continue;
      final space = limit - existing.getInt('count');
      if (space <= 0) continue;
      final moved = remaining < space ? remaining : space;
      existing.putInt('count', existing.getInt('count') + moved);
      remaining -= moved;
    }
    // then into empty slots
    for (var i = 0; i < stacks.length && remaining > 0; i++) {
      if (stacks[i] != null) continue;
      final moved = remaining < limit ? remaining : limit;
      final copy = stack.copy()..putInt('count', moved);
      stacks[i] = copy;
      remaining -= moved;
    }
    if (remaining <= 0) return null;
    return stack.copy()..putInt('count', remaining);
  }

  /// `serializeNBT()`: `{Size, Items: [{Slot, ...stack}]}`.
  CTag serializeNBT() {
    final items = <CTag>[];
    for (var i = 0; i < stacks.length; i++) {
      final s = stacks[i];
      if (s == null) continue;
      items.add(s.copy()..putInt('Slot', i));
    }
    return CTag()
      ..putInt('Size', stacks.length)
      ..putCompoundList('Items', items);
  }

  /// `deserializeNBT(tag)`.
  void deserializeNBT(CTag tag) {
    final size = tag.contains('Size') ? tag.getInt('Size') : stacks.length;
    if (size != stacks.length) {
      stacks
        ..clear()
        ..addAll(List<CTag?>.filled(size, null));
    }
    for (var i = 0; i < stacks.length; i++) {
      stacks[i] = null;
    }
    for (final item in tag.getCompoundList('Items')) {
      final slot = item.getInt('Slot');
      if (slot < 0 || slot >= stacks.length) continue;
      final stack = item.copy()..remove('Slot');
      if (stack.getInt('count') > 0) stacks[slot] = stack;
    }
  }
}

class GlobalPackagePort {
  String address = '';
  OfflineBuffer offlineBuffer = OfflineBuffer(18);
  bool primed = false;
  bool _restoring = false;

  void restoreOfflineBuffer(PackageInventory inventory) {
    if (!primed) return;

    _restoring = true;

    for (var slot = 0; slot < offlineBuffer.getSlots(); slot++) {
      inventory.setStackInSlot(slot, offlineBuffer.getStackInSlot(slot));
    }

    _restoring = false;
    primed = false;
  }

  /// Called whenever the connected postbox' inventory changes.
  void saveOfflineBuffer(PackageInventory inventory) {
    // Each time restoreOfflineBuffer changes a slot, the inventory calls this method. We must filter
    // out those calls to prevent overwriting later slots which haven't been restored yet.
    if (_restoring) return;

    for (var slot = 0; slot < inventory.getSlots(); slot++) {
      offlineBuffer.setStackInSlot(slot, inventory.getStackInSlot(slot));
    }

    Create.RAILWAYS.markTracksDirty();
  }
}

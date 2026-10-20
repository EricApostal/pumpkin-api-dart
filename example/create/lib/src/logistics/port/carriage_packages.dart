// The item storage of a train carriage as saved package stacks: the [PackageInventory]
// `GlobalStation.runMailTransfer()` asks for through `MailTransferHooks.carriageInventory`, and the
// conversion between a contraption's `StoredStack` and this module's [LStack].
//
// A contraption keeps the components of a stack as Java's codec compound (`StoredStack.toNbt`),
// which cannot be turned into the network bytes an [LStack] keeps (the gap is spelled out at
// `common/stack_tag.dart`). The lossless copy the plugin writes next to them
// (`minecraft:custom_data` under [privateDataKey], the pair `host/stack_io.dart` writes for the
// host's item stacks) is read back here. A stack without that copy — one the Create mod itself
// wrote — keeps its package address, whose codec form is plain text
// (`AllDataComponents.PACKAGE_ADDRESS` is `Codec.STRING`), and nothing of its contents: there is no
// pure decoder for the other package components' codec forms.
//
// Pure (no host bindings), so the conversions are testable on the Dart VM.
import 'dart:convert';
import 'dart:math' as math;

import '../../contraptions/core/nbt_map.dart';
import '../../contraptions/storage/stacks.dart' show ItemSlots, StoredStack;
import '../../core/nbt.dart' show NbtKind, NbtValue, NetworkNbt;
import '../../trains/station/global_package_port.dart' show OfflineBuffer;
import '../../trains/station/mail_transfer.dart' show PackageInventory;
import '../../trains/util/ctag.dart';
import '../model/package.dart' show PackageComponents, PackageItem;
import '../model/stack.dart';
import '../model/stack_tags.dart'
    show customDataComponent, privateDataKey, stackFromCTag, stackToCTag;

/// The `minecraft:max_damage` component: an item that has one does not stack.
const String _maxDamageComponent = 'minecraft:max_damage';

/// The stack limit of [stack]: the offline buffer's item rule (`OfflineBuffer.stackLimit`, which
/// the Create manifest answers, so the package items are max stack 1) capped by the contraption's
/// own limits ([ItemStackLimits] through `StoredStack.maxStackSize`). The contraption's resolver is
/// the host's and knows nothing of the packages; without the manifest side a package would merge
/// into a count, which Java's max stack 1 forbids.
int carriageStackLimit(StoredStack stack) => math.min(
  stack.maxStackSize,
  OfflineBuffer.stackLimit(CTag()..putString('id', stack.item)),
);

/// The module's [LStack] of a carriage slot.
LStack carriageLStack(StoredStack stack) {
  if (stack.isEmpty) return LStack.empty;
  final comps = <String, String>{};
  _readAddress(stack.components, comps);
  _readPrivateComponents(stack.components, comps);
  final components = stack.components;
  return LStack(
    stack.item,
    stack.count,
    maxStack: carriageStackLimit(stack),
    damageable: components != null && components.contains(_maxDamageComponent),
    comps: Map.fromEntries(
      comps.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  );
}

/// The `StoredStack` of [stack] for a carriage slot.
StoredStack carriageStoredStack(LStack stack) {
  if (stack.isEmpty) return StoredStack.empty;
  if (stack.comps.isEmpty) return StoredStack(stack.key, stack.count);
  return StoredStack(stack.key, stack.count, _componentsOf(stack));
}

/// The codec-form components of [stack]: the private copy of everything an [LStack] carries, next
/// to the address a Create client reads.
NbtMap _componentsOf(LStack stack) {
  final out = NbtMap();
  if (PackageItem.hasAddress(stack)) {
    out.putString(PackageComponents.address, PackageItem.getAddress(stack));
  }
  var custom = <String, NbtValue>{};
  final existing = stack.compBytes(customDataComponent);
  if (existing != null) {
    try {
      custom = Map<String, NbtValue>.of(
        NetworkNbt.decode(existing)?.asCompound ?? const {},
      );
    } on Object {
      // a custom_data value that is no compound is replaced by the private copy alone
      custom = {};
    }
  }
  final comps = Map<String, String>.of(stack.comps)
    ..remove(customDataComponent);
  custom[privateDataKey] = NbtValue.string(jsonEncode(comps));
  out.putCompound(customDataComponent, NbtMap(custom));
  return out;
}

/// Reads the private copy (`host/stack_io.dart` writes it) of the saved components of a stack into
/// [comps], and keeps the `minecraft:custom_data` component left next to it: the private key is
/// removed from that component, what remains is the stack's own custom data — the same reading
/// `StackIo._restorePrivate` does on a host stack.
void _readPrivateComponents(NbtMap? components, Map<String, String> comps) {
  final data = components?[customDataComponent];
  if (data == null || data.kind != NbtKind.compound) return;
  final map = Map<String, NbtValue>.of(data.asCompound);
  final private = map.remove(privateDataKey);
  if (map.isNotEmpty) {
    comps[customDataComponent] = base64Encode(
      NetworkNbt.encode(NbtValue.compound(map)),
    );
  }
  if (private == null || private.kind != NbtKind.string) return;
  try {
    final decoded = jsonDecode(private.value as String);
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is String) comps['${entry.key}'] = value;
    }
  } on Object {
    // an unreadable copy reads as no copy
  }
}

/// `PackageItem.getAddress` of a package written by the Create mod itself: its address is a plain
/// text component, so it survives the codec form. A world the plugin wrote keeps the address in the
/// private copy instead.
void _readAddress(NbtMap? components, Map<String, String> comps) {
  final value = components?[PackageComponents.address];
  if (value == null || value.kind != NbtKind.string) return;
  final address = value.value as String;
  if (address.isEmpty) return;
  comps[PackageComponents.address] = base64Encode(utf8.encode(address));
}

/// The items of a carriage contraption as saved stacks (`carriage.storage.getAllItems()` of
/// `GlobalStation.runMailTransfer`), backed by the combined handler of the mounted storages.
final class CarriagePackageInventory implements PackageInventory {
  /// The contraption's item storage (`MountedStorageManager.getAllItems`).
  final ItemSlots slots;

  /// The stack limit of an item (`MailTransferHooks.maxStackSize`).
  final int Function(CTag stack) maxStackSize;

  CarriagePackageInventory(this.slots, this.maxStackSize);

  @override
  int getSlots() => slots.slots;

  @override
  CTag? getStackInSlot(int slot) {
    final stack = slots.stackInSlot(slot);
    return stack.isEmpty ? null : stackToCTag(carriageLStack(stack));
  }

  @override
  void setStackInSlot(int slot, CTag? stack) =>
      slots.setStackInSlot(slot, carriageStoredStack(stackFromCTag(stack)));

  /// `TransferUtil.insertItemStacked(handler, stack, false)`: the slots that already hold the
  /// stack first, then the empty ones. The limit is the item's own ([maxStackSize]), not the
  /// contraption's item resolver's, which does not know the package items.
  @override
  CTag? insertItemStacked(CTag stack) {
    final incoming = carriageStoredStack(stackFromCTag(stack));
    if (incoming.isEmpty) return null;
    final limit = maxStackSize(stack);
    var remaining = incoming.count;
    for (var pass = 0; pass < 2 && remaining > 0; pass++) {
      for (var slot = 0; slot < slots.slots && remaining > 0; slot++) {
        final held = slots.stackInSlot(slot);
        if (pass == 0 && held.isEmpty) continue;
        if (pass == 1 && held.isNotEmpty) continue;
        if (!slots.isItemValid(slot, incoming)) continue;
        if (held.isNotEmpty && !held.sameItemSameComponents(incoming)) continue;
        final space = math.min(limit, slots.slotLimit(slot)) - held.count;
        if (space <= 0) continue;
        final moved = math.min(remaining, space);
        slots.setStackInSlot(
          slot,
          held.isEmpty ? incoming.copyWithCount(moved) : held.grow(moved),
        );
        remaining -= moved;
      }
    }
    if (remaining <= 0) return null;
    return stackToCTag(carriageLStack(incoming.copyWithCount(remaining)));
  }
}
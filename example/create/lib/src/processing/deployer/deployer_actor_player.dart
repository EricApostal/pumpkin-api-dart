// The fake player of a deployer on a contraption: created on demand per movement context, kept in
// `context.temporaryData`, restored from the captured block entity data and written back when the
// contraption stops.
//
// `content/kinetics/deployer/DeployerMovementBehaviour.java` (`getPlayer`,
// `stopMoving`), `DeployerMovingInteraction.java`. Contraption data is a pure `NbtMap`, so the
// stacks are written with the same fields as `StackNbt` but on `NbtMap`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../common/stack_tag.dart';
import '../../contraptions/core/movement.dart';
import '../../contraptions/core/nbt_map.dart';
import '../../core/nbt.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart' show dropPStack;
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'deployer_types.dart';

/// The filter stack the deployer was assembled with (`context.getFilterFromBE()`).
PStack actorFilterOf(MovementContext context) =>
    _stackFromMap(context.blockEntityData?.getCompoundOrNull('Filter'));

/// The deployer mode the captured block entity had.
DeployerMode actorModeOf(MovementContext context) =>
    DeployerMode.fromJavaName(context.blockEntityData?.getString('Mode'));

/// `DeployerMovementBehaviour.getPlayer`: the fake player of [context], created and restored on
/// first use.
Player? actorPlayer(MovementContext context, World world) {
  final existing = context.temporaryData;
  if (existing is Player) return existing;

  final owner = _ownerUuid(context.blockEntityData);
  Player player;
  try {
    player = FakePlayers.create(world, 'Deployer', id: owner).keep();
  } on Object {
    player = FakePlayers.create(
      world,
      'Deployer@${context.localPos.$1},${context.localPos.$2},${context.localPos.$3}',
    ).keep();
  }
  context.temporaryData = player;

  final inventory = player.getInventory();
  inventory.setSelectedSlot(slot: 0);

  final saved = context.blockEntityData?.getList('Inventory');
  if (saved != null && saved.isNotEmpty) {
    unawaited(_loadInventory(player, _readActorInventory(saved)));
  }
  final held = context.data.getCompoundOrNull('HeldItem');
  if (held != null) {
    final stack = _stackFromMap(held);
    if (stack.isNotEmpty) unawaited(setActorHand(player, stack));
  }
  context.blockEntityData?.remove('Inventory');
  return player;
}

Future<void> _loadInventory(Player player, List<PStack> stacks) async {
  final inventory = player.getInventory().storage;
  for (
    var slot = 0;
    slot < stacks.length && slot < inventory.getSize();
    slot++
  ) {
    final stack = stacks[slot];
    if (stack.isEmpty) continue;
    final item = await HostStacks.write(stack);
    if (item == null) continue;
    await inventory.setItem(slot: slot, item: item);
  }
}

/// The item in the main hand of [player].
Future<PStack> readActorHand(Player player) async {
  final item = player.getItemInHand(hand: Hand.right);
  if (item == null) return PStack.empty;
  final stack = await HostStacks.read(item);
  item.dispose();
  return stack;
}

/// `player.setItemInHand(MAIN_HAND, stack)`.
Future<void> setActorHand(Player player, PStack stack) async {
  final item = await HostStacks.write(stack);
  await player.setItemInHand(hand: Hand.right, stack: item);
}

/// `DeployerMovementBehaviour.stopMoving`: saves the inventory into the captured data and
/// releases the fake player.
Future<void> saveActorPlayer(MovementContext context, Player player) async {
  final inventory = List<PStack>.filled(36, PStack.empty);
  final storage = player.getInventory().storage;
  for (
    var slot = 0;
    slot < inventory.length && slot < storage.getSize();
    slot++
  ) {
    final item = storage.getItem(slot: slot);
    if (item == null) continue;
    inventory[slot] = await HostStacks.read(item);
    item.dispose();
  }
  context.blockEntityData?.putList(
    'Inventory',
    _writeActorInventory(inventory),
  );
  // The inventory is saved: the fake player is released without dropping its contents.
  await storage.clear();
  await releaseActorPlayer(context);
}

/// The uuid in the captured data: `Owner` is the four-int `UUIDUtil.CODEC` form in Java; the
/// canonical string of earlier versions is still accepted.
Uuid? actorOwnerUuid(NbtMap? data) => _ownerUuid(data);

/// The `Owner` of the captured deployer, as the host uuid text (`checkForTrackPlacementAdvancement`
/// reads it for `SELF_DEPLOYING`).
String? actorOwnerId(NbtMap? data) => _ownerUuid(data)?.asString;

Uuid? _ownerUuid(NbtMap? data) {
  if (data == null) return null;
  final value = data.getIntArray('Owner');
  if (value.length >= 4) {
    return Uuid(
      high: (value[0] << 32) | (value[1] & 0xFFFFFFFF),
      low: (value[2] << 32) | (value[3] & 0xFFFFFFFF),
    );
  }
  final text = data.getString('Owner');
  return text.isEmpty ? null : Uuids.tryParse(text);
}

/// Releases the fake player of [context] (and any still held by it).
Future<void> releaseActorPlayer(MovementContext context) async {
  final player = context.temporaryData;
  if (player is! Player) return;
  context.temporaryData = null;
  final world = ProcessingRuntime.instance.worlds.byId(context.worldId);
  if (world != null) {
    final storage = player.getInventory().storage;
    for (var slot = 0; slot < storage.getSize(); slot++) {
      final item = storage.getItem(slot: slot);
      if (item == null) continue;
      final stack = await HostStacks.read(item);
      item.dispose();
      if (stack.isEmpty) continue;
      await storage.setItem(slot: slot, item: null);
      await dropPStack(world, player.getPosition(), stack);
    }
  }
  try {
    FakePlayers.remove(player);
  } on Object {
    // already gone
  }
  try {
    player.dispose();
  } on Object {
    // already released
  }
}

/// Writes the main hand into `context.data` (the actor's saved data).
void saveActorHeld(MovementContext context, PStack held) {
  context.data.putCompound('HeldItem', actorStackNbt(held));
}

/// A stack as the pure NBT of the contraption data (`StackNbt.write` on `NbtMap`).
NbtMap actorStackNbt(PStack stack) => _stackToMap(stack);

/// `StackNbt.write` on a pure [NbtMap] (the contraption data format): the Java
/// `ItemStack.CODEC` shape with the plugin's extras (`common/stack_tag.dart`).
NbtMap _stackToMap(PStack stack) => NbtMap.of(
  JavaStackTag.write(
    id: stack.key,
    count: stack.count,
    comps: stack.comps,
    maxStack: stack.maxStack == 64 ? null : stack.maxStack,
  ),
);

/// `StackNbt.read` on a pure [NbtMap].
PStack _stackFromMap(NbtMap? map) {
  if (map == null) return PStack.empty;
  final t = JavaStackTag.read(map.toValue());
  if (t == null) return PStack.empty;
  return PStack(t.id, t.count, maxStack: t.maxStack ?? 64, comps: t.comps);
}

/// The vanilla `Inventory` list of the fake player: one `{Slot, ...stack}` entry per non-empty
/// slot (`DeployerBlockEntity.write`).
List<NbtValue> _writeActorInventory(List<PStack> stacks) {
  final items = <NbtValue>[];
  for (var slot = 0; slot < stacks.length; slot++) {
    if (stacks[slot].isEmpty) continue;
    items.add((_stackToMap(stacks[slot])..putByte('Slot', slot)).toValue());
  }
  return items;
}

/// Reads the `Inventory` list (`DeployerBlockEntity.read`).
List<PStack> _readActorInventory(List<NbtValue> list, [int size = 36]) {
  final out = List<PStack>.filled(size, PStack.empty);
  for (final value in list) {
    final entry = NbtMap.of(value);
    final slot = entry.getInt('Slot', -1);
    if (slot >= 0 && slot < size) out[slot] = _stackFromMap(entry);
  }
  return out;
}

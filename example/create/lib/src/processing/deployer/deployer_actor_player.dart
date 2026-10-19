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

  final owner = context.blockEntityData?.getString('Owner');
  Player player;
  try {
    player = FakePlayers.create(
      world,
      'Deployer',
      id: owner == null ? null : Uuids.tryParse(owner),
    ).keep();
  } on Object {
    player = FakePlayers.create(
      world,
      'Deployer@${context.localPos.$1},${context.localPos.$2},${context.localPos.$3}',
    ).keep();
  }
  context.temporaryData = player;

  final inventory = player.getInventory();
  inventory.setSelectedSlot(slot: 0);

  final saved = context.blockEntityData?.getCompoundOrNull('Inventory');
  if (saved != null) {
    unawaited(_loadInventory(player, _readInventory(saved)));
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
  context.blockEntityData?.putCompound('Inventory', _writeInventory(inventory));
  // The inventory is saved: the fake player is released without dropping its contents.
  await storage.clear();
  await releaseActorPlayer(context);
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

/// `StackNbt.write` on a pure [NbtMap] (the contraption data format).
NbtMap _stackToMap(PStack stack) {
  final map = NbtMap()
    ..putString('id', stack.key)
    ..putInt('count', stack.count);
  if (stack.maxStack != 64) map.putInt('Max', stack.maxStack);
  if (stack.comps.isNotEmpty) {
    map.putList('Comps', [
      for (final (name, bytes) in stack.comps)
        _componentMap(name, bytes).toValue(),
    ]);
  }
  return map;
}

/// One component entry of a saved stack.
NbtMap _componentMap(String name, List<int> bytes) {
  final map = NbtMap()..putString('N', name);
  map['V'] = NbtValue.byteArray(bytes);
  return map;
}

/// `StackNbt.read` on a pure [NbtMap].
PStack _stackFromMap(NbtMap? map) {
  if (map == null) return PStack.empty;
  final key = map.getString('id');
  final count = map.getInt('count');
  if (key.isEmpty || count <= 0) return PStack.empty;
  final comps = <(String, List<int>)>[];
  for (final value in map.getList('Comps')) {
    final entry = NbtMap.of(value);
    final name = entry.getString('N');
    final bytes = entry.getIntArray('V');
    if (name.isNotEmpty && bytes.isNotEmpty) comps.add((name, bytes));
  }
  comps.sort((a, b) => a.$1.compareTo(b.$1));
  return PStack(key, count, maxStack: map.getInt('Max', 64), comps: comps);
}

/// `StackNbt.writeList` on a pure [NbtMap].
NbtMap _writeInventory(List<PStack> stacks) {
  final items = <NbtValue>[];
  for (var slot = 0; slot < stacks.length; slot++) {
    if (stacks[slot].isEmpty) continue;
    final map = _stackToMap(stacks[slot])..putInt('Slot', slot);
    items.add(map.toValue());
  }
  return NbtMap()
    ..putList('Items', items)
    ..putInt('Size', stacks.length);
}

/// `StackNbt.readList` on a pure [NbtMap].
List<PStack> _readInventory(NbtMap map, [int size = 36]) {
  final out = List<PStack>.filled(size, PStack.empty);
  for (final value in map.getList('Items')) {
    final entry = NbtMap.of(value);
    final slot = entry.getInt('Slot', -1);
    if (slot >= 0 && slot < size) out[slot] = _stackFromMap(entry);
  }
  return out;
}

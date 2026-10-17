// The turtle commands: what `turtle.forward()`, `turtle.dig()`, ... do once
// the brain runs them. One function per Java `Turtle*Command`
// (shared/turtle/core, mc-26.3), written against [TurtleWorld]; the messages
// and the order of the checks are the Java ones.
//
// Differences that come from the host and not from this file are listed in
// docs/host-requirements.md ("Turtles"): block drops are approximated
// (`vanilla_data.dart`), nothing can be dropped as an item entity or picked up
// from one, entities in the way are only checked by the adapter, placing
// blocks gives the default state (plus facing/axis), crafting does not exist.
import 'brain.dart';
import 'direction.dart';
import 'stack.dart';
import 'upgrades.dart';
import 'vanilla_data.dart';
import 'world.dart';

/// `MoveDirection`.
enum Move { forward, back, up, down }

/// `InteractDirection`.
enum Interact { forward, up, down }

/// `TurtleVerb`.
enum ToolVerb { dig, attack }

Dir _moveDir(TurtleBrain t, Move move) => switch (move) {
  Move.forward => t.facing,
  Move.back => t.facing.opposite,
  Move.up => Dir.up,
  Move.down => Dir.down,
};

Dir _interactDir(TurtleBrain t, Interact direction) => switch (direction) {
  Interact.forward => t.facing,
  Interact.up => Dir.up,
  Interact.down => Dir.down,
};

const TurtleResult _failed = TurtleResult.fail();

abstract final class TurtleCommands {
  // -- Movement -------------------------------------------------------------------

  /// `TurtleMoveCommand`.
  static TurtleCommand move(Move move) => (t, w) async {
    final direction = _moveDir(t, move);
    final target = t.pos.relative(direction);
    final refused = w.whyCannotEnter(target);
    if (refused != null) return TurtleResult.fail(refused);

    if (!w.blockAt(target).canEnter) return const TurtleResult.fail('Movement obstructed');
    final obstruction = w.entityObstruction(target);
    if (obstruction != null) return TurtleResult.fail(obstruction);

    if (t.isFuelNeeded && t.fuelLevel < 1) return const TurtleResult.fail('Out of fuel');

    if (!await w.moveTurtle(target)) return const TurtleResult.fail('Movement failed');
    t.consumeFuel(1);
    t.playAnimation(switch (move) {
      Move.forward => TurtleAnimation.moveForward,
      Move.back => TurtleAnimation.moveBack,
      Move.up => TurtleAnimation.moveUp,
      Move.down => TurtleAnimation.moveDown,
    });
    return const TurtleResult.ok();
  };

  /// `TurtleTurnCommand`.
  static TurtleCommand turn({required bool left}) => (t, w) async {
    final next = left ? t.facing.counterClockwise : t.facing.clockwise;
    await w.setFacing(next);
    t.facing = next;
    t.saveDirty = true;
    t.playAnimation(left ? TurtleAnimation.turnLeft : TurtleAnimation.turnRight);
    return const TurtleResult.ok();
  };

  // -- Tools ---------------------------------------------------------------------

  /// `TurtleToolCommand`: tries the tools on the sides (both, or [only]).
  static TurtleCommand tool(ToolVerb verb, Interact direction, TurtleSide? only) => (t, w) async {
    TurtleResult? firstFailure;
    for (final side in TurtleSide.values) {
      if (only != null && only != side) continue;
      final instance = t.upgradeOn(side);
      if (instance == null || !instance.upgrade.isTool) continue;
      final dir = _interactDir(t, direction);
      final result = verb == ToolVerb.dig ? await _dig(t, w, instance.upgrade, dir) : await _attack(t, w, instance.upgrade, dir);
      if (result.success) {
        t.playAnimation(side == TurtleSide.left ? TurtleAnimation.swingLeftTool : TurtleAnimation.swingRightTool);
        return result;
      }
      firstFailure ??= result;
    }
    return firstFailure ?? TurtleResult.fail('No tool to ${verb.name} with');
  };

  // -- Items ---------------------------------------------------------------------

  /// `TurtlePlaceCommand` (the part that places blocks).
  static TurtleCommand place(Interact direction) => (t, w) async {
    final stack = t.inventory[t.selectedSlot];
    if (stack == null) return const TurtleResult.fail('No items to place');
    final dir = _interactDir(t, direction);
    final target = t.pos.relative(dir);
    final block = w.blockAt(target);
    if (!block.canEnter) return const TurtleResult.fail('Cannot place block here');
    final obstruction = w.entityObstruction(target);
    if (obstruction != null) return const TurtleResult.fail('Cannot place block here');
    if (!await w.placeBlock(target, stack.item, dir)) return const TurtleResult.fail('Cannot place item here');
    stack.count -= 1;
    if (stack.count <= 0) t.inventory[t.selectedSlot] = null;
    t.saveDirty = true;
    t.playAnimation(TurtleAnimation.wait);
    return const TurtleResult.ok();
  };

  /// `TurtleDropCommand`: into the inventory in that direction.
  static TurtleCommand drop(Interact direction, int quantity) => (t, w) async {
    if (quantity == 0) {
      t.playAnimation(TurtleAnimation.wait);
      return const TurtleResult.ok();
    }
    final stack = t.inventory[t.selectedSlot];
    if (stack == null) return const TurtleResult.fail('No items to drop');
    final dir = _interactDir(t, direction);
    final container = await w.containerAt(t.pos.relative(dir));
    if (container == null) {
      // A real turtle drops an item entity here; the host cannot spawn one.
      return const TurtleResult.fail('Cannot drop items into the world on this server');
    }
    final amount = stack.count < quantity ? stack.count : quantity;
    final moved = amount - ((await _insert(container, stack.copy(count: amount), w))?.count ?? 0);
    if (moved <= 0) return const TurtleResult.fail('No space for items');
    stack.count -= moved;
    if (stack.count <= 0) t.inventory[t.selectedSlot] = null;
    t.saveDirty = true;
    t.playAnimation(TurtleAnimation.wait);
    return const TurtleResult.ok();
  };

  /// `TurtleSuckCommand`: from the inventory in that direction.
  static TurtleCommand suck(Interact direction, int quantity) => (t, w) async {
    if (quantity == 0) {
      t.playAnimation(TurtleAnimation.wait);
      return const TurtleResult.ok();
    }
    final dir = _interactDir(t, direction);
    final container = await w.containerAt(t.pos.relative(dir));
    // Loose items on the ground are not reachable (no item entity API).
    if (container == null) return const TurtleResult.fail('No items to take');
    var left = quantity;
    var any = false;
    var full = false;
    for (var slot = 0; slot < container.size && left > 0; slot++) {
      final stack = container.stackAt(slot);
      if (stack == null) continue;
      any = true;
      final take = stack.count < left ? stack.count : left;
      final remainder = t.inventory.storeFromOffset(stack.copy(count: take), t.selectedSlot);
      final moved = take - (remainder?.count ?? 0);
      if (moved <= 0) {
        full = true;
        continue;
      }
      stack.count -= moved;
      await container.setStack(slot, stack.count <= 0 ? null : stack);
      left -= moved;
      t.saveDirty = true;
    }
    if (left == quantity) {
      return TurtleResult.fail(any && full ? 'No space for items' : 'No items to take');
    }
    t.playAnimation(TurtleAnimation.wait);
    return const TurtleResult.ok();
  };

  /// `TurtleDetectCommand`.
  static TurtleCommand detect(Interact direction) => (t, w) {
    final block = w.blockAt(t.pos.relative(_interactDir(t, direction)));
    return block.isAir ? _failed : const TurtleResult.ok();
  };

  /// `TurtleInspectCommand`: the block's name and state.
  static TurtleCommand inspect(Interact direction) => (t, w) {
    final block = w.blockAt(t.pos.relative(_interactDir(t, direction)));
    if (block.isAir) return const TurtleResult.fail('No block to inspect');
    final state = <String, Object?>{};
    for (final entry in block.properties.entries) {
      state[entry.key] = _propertyValue(entry.value);
    }
    return TurtleResult.ok([
      {'name': block.name, 'state': state, 'tags': <String, Object?>{}},
    ]);
  };

  /// `TurtleCompareCommand`: the block against the selected item.
  static TurtleCommand compare(Interact direction) => (t, w) {
    final selected = t.inventory[t.selectedSlot];
    final block = w.blockAt(t.pos.relative(_interactDir(t, direction)));
    // An empty slot and air are both "minecraft:air" to the Java command.
    final lookAt = block.isAir ? 'minecraft:air' : (block.itemKey ?? block.name);
    return (selected?.item ?? 'minecraft:air') == lookAt ? const TurtleResult.ok() : _failed;
  };

  /// `TurtleCompareToCommand`.
  static TurtleCommand compareTo(int slot) => (t, w) {
    final selected = t.inventory[t.selectedSlot];
    final other = t.inventory[slot];
    if (selected == null || other == null) return selected == null && other == null ? const TurtleResult.ok() : _failed;
    return selected.sameItem(other) ? const TurtleResult.ok() : _failed;
  };

  /// `TurtleTransferToCommand`.
  static TurtleCommand transferTo(int slot, int quantity) => (t, w) {
    final taken = t.inventory.remove(t.selectedSlot, quantity);
    if (taken == null) {
      t.playAnimation(TurtleAnimation.wait);
      return const TurtleResult.ok();
    }
    final remainder = t.inventory.storeIntoSlot(taken, slot);
    if (remainder != null) {
      // Put the remainder back.
      t.inventory.storeIntoSlot(remainder, t.selectedSlot);
    }
    t.saveDirty = true;
    if (remainder == null || remainder.count != taken.count) {
      t.playAnimation(TurtleAnimation.wait);
      return const TurtleResult.ok();
    }
    return const TurtleResult.fail('No space for items');
  };

  /// `TurtleRefuelCommand` with the furnace handler.
  static TurtleCommand refuel(int limit) => (t, w) {
    final stack = t.inventory[t.selectedSlot];
    if (stack == null) return const TurtleResult.fail('No items to combust');
    final perItem = fuelPerItem(stack.item);
    if (perItem <= 0) return const TurtleResult.fail('Items not combustible');
    if (limit == 0) return const TurtleResult.ok();
    final spaceLeft = t.fuelLimit - t.fuelLevel;
    final itemLimit = (spaceLeft / perItem).ceil();
    var count = limit < itemLimit ? limit : itemLimit;
    if (count > stack.count) count = stack.count;
    if (count <= 0) return const TurtleResult.ok();
    final remainderItem = fuelRemainder(stack.item);
    stack.count -= count;
    if (stack.count <= 0) t.inventory[t.selectedSlot] = null;
    if (remainderItem != null) t.storeItems(TurtleStack(remainderItem, count));
    t.addFuel(perItem * count);
    t.saveDirty = true;
    t.playAnimation(TurtleAnimation.wait);
    return const TurtleResult.ok();
  };

  /// `TurtleEquipCommand`.
  static TurtleCommand equip(TurtleSide side) => (t, w) {
    final old = t.upgradeOn(side);
    UpgradeInstance? next;
    final stack = t.inventory[t.selectedSlot];
    if (stack != null) {
      final upgrade = t.upgradeTable.forItem(stack);
      if (upgrade == null) return const TurtleResult.fail('Not a valid upgrade');
      next = UpgradeInstance(upgrade);
    }
    // The replaced upgrade goes back into the inventory: check there is room
    // first, the host cannot drop what does not fit.
    if (old != null) {
      final copy = cloneSlots(t.inventory);
      if (next != null) copy.remove(t.selectedSlot, 1);
      if (copy.storeFromOffset(TurtleStack(old.upgrade.item, 1), t.selectedSlot) != null) {
        return const TurtleResult.fail('No space for items');
      }
    }
    if (next != null) t.inventory.remove(t.selectedSlot, 1);
    if (old != null) t.storeItems(TurtleStack(old.upgrade.item, 1));
    t.setUpgrade(side, next);
    if (next != null || old != null) t.playAnimation(TurtleAnimation.wait);
    return const TurtleResult.ok();
  };

  /// `select`: queued like every command.
  static TurtleCommand select(int slot) => (t, w) {
    t.selectSlot(slot);
    return const TurtleResult.ok();
  };
}

// -- Helpers ---------------------------------------------------------------------------

/// Block state properties as Lua values: booleans and integers keep their type.
Object? _propertyValue(String value) {
  if (value == 'true') return true;
  if (value == 'false') return false;
  final number = int.tryParse(value);
  return number ?? value;
}

/// Puts [stack] into [container] (merging first into the slot order, like an
/// item handler); returns the rest, null if all of it fit.
Future<TurtleStack?> _insert(ContainerView container, TurtleStack stack, ItemInfo info) async {
  final max = info.maxStack(stack.item);
  if (max <= 0) return stack;
  var left = stack.count;
  for (var slot = 0; slot < container.size && left > 0; slot++) {
    final current = container.stackAt(slot);
    if (current == null) {
      final put = left < max ? left : max;
      await container.setStack(slot, stack.copy(count: put));
      left -= put;
    } else if (current.count < max && current.sameItem(stack)) {
      final room = max - current.count;
      final put = left < room ? left : room;
      current.count += put;
      await container.setStack(slot, current);
      left -= put;
    }
  }
  return left <= 0 ? null : stack.copy(count: left);
}

const Set<String> _gameMasterBlocks = {
  'command_block',
  'chain_command_block',
  'repeating_command_block',
  'structure_block',
  'jigsaw',
  'barrier',
  'light',
  'test_block',
  'test_instance_block',
};

bool _isGameMaster(String name) => _gameMasterBlocks.contains(name.startsWith('minecraft:') ? name.substring(10) : name);

/// `TurtleTool.dig`.
Future<TurtleResult> _dig(TurtleBrain t, TurtleWorld w, TurtleUpgrade tool, Dir direction) async {
  // Hoes and shovels act on the block instead of breaking it (`useTool`).
  if (await _useTool(t, w, tool, direction)) return const TurtleResult.ok();

  final target = t.pos.relative(direction);
  final block = w.blockAt(target);
  if (block.isAir || block.isLiquid) return const TurtleResult.fail('Nothing to dig here');

  // A computer or turtle holds data the host cannot hand over as an item entity
  // (its id, its inventory): breaking it here would lose them.
  if (block.name.startsWith('computercraft:computer') || block.name.startsWith('computercraft:turtle')) {
    return const TurtleResult.fail('Cannot break unbreakable block');
  }

  // `checkBlockBreakable`.
  if (block.hardness < 0 || _isGameMaster(block.name)) {
    return const TurtleResult.fail('Cannot break unbreakable block');
  }
  final tag = tool.breakable;
  final breakable = tag == null || turtleToolBreaks(tag, block) || block.hardness == 0 || turtleAlwaysBreakable(block);
  if (!breakable) return const TurtleResult.fail('Cannot break block with this tool');

  // The drops go into the inventory; whatever does not fit would be dropped
  // into the world by a real turtle, which the host cannot do, so the block
  // is not broken at all.
  final drops = blockDrops(block);
  final copy = cloneSlots(t.inventory);
  for (final drop in drops) {
    if (copy.storeFromOffset(drop, t.selectedSlot) != null) return const TurtleResult.fail('No space for items');
  }
  await w.removeBlock(target);
  for (final drop in drops) {
    t.storeItems(drop);
  }
  return const TurtleResult.ok();
}

/// `TurtleTool.useTool`: hoeing and flattening, the "right click" of a tool.
Future<bool> _useTool(TurtleBrain t, TurtleWorld w, TurtleUpgrade tool, Dir direction) async {
  final item = tool.item;
  final isHoe = item.endsWith('_hoe');
  final isShovel = item.endsWith('_shovel');
  if (!isHoe && !isShovel) return false;
  var position = t.pos.relative(direction);
  var block = w.blockAt(position);
  // Allow digging one extra block below the turtle, as you cannot till dirt or
  // flatten grass if there is a block above.
  if (direction == Dir.down && block.isAir) {
    position = position.relative(direction);
    block = w.blockAt(position);
  }
  if (block.isAir) return false;
  final name = block.name.startsWith('minecraft:') ? block.name.substring(10) : block.name;
  final airAbove = w.blockAt(position.relative(Dir.up)).isAir;
  if (isHoe) {
    if (name == 'coarse_dirt' || name == 'rooted_dirt') return await w.replaceBlock(position, 'minecraft:dirt');
    if (airAbove && (name == 'grass_block' || name == 'dirt' || name == 'dirt_path')) {
      return await w.replaceBlock(position, 'minecraft:farmland');
    }
    return false;
  }
  if (airAbove && name == 'grass_block') return await w.replaceBlock(position, 'minecraft:dirt_path');
  return false;
}

/// `TurtleTool.attack`: the damage is the player's attack damage with the
/// tool times the spec's `damageMultiplier`.
Future<TurtleResult> _attack(TurtleBrain t, TurtleWorld w, TurtleUpgrade tool, Dir direction) async {
  final damage = toolAttackDamage(tool.item) * tool.damageMultiplier;
  if (damage <= 0) return const TurtleResult.fail('Nothing to attack here');
  return await w.attack(t.pos.relative(direction), damage)
      ? const TurtleResult.ok()
      : const TurtleResult.fail('Nothing to attack here');
}

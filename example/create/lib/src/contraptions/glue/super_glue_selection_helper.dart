// `SuperGlueSelectionHelper` (server side): the connected group of blocks a glue selection would
// hold together, and taking charges from the player's glue.
//
// Java: `content/contraptions/glue/SuperGlueSelectionHelper`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../../common/nbt_convert.dart';
import '../core/level.dart';
import '../../core/nbt.dart';
import '../core/nbt_map.dart';
import '../core/movement_checks.dart';
import 'super_glue_entity.dart';

/// The namespace and key of the glue charges in the item's custom data. The host item API has no
/// durability access, so the remaining charges of a `create:super_glue` stack are kept in its
/// custom data (the item is registered with `minecraft:max_damage` 99 for the client).
const String glueDataNamespace = 'create';
const String glueDataKey = 'glue_charges';

/// `SuperGlueItem` durability (`AllItems.SUPER_GLUE` has 99 uses).
const int glueMaxCharges = 99;

/// `SuperGlueSelectionHelper.searchGlueGroup`: the blocks reachable from [startPos] inside the box
/// spanned with [endPos], following glue, sticky sides and block attachments.
Set<Pos>? searchGlueGroup(
  ContraptionLevel level,
  Pos startPos,
  Pos endPos, {
  required bool includeOther,
}) {
  final box = glueSpan(startPos, endPos);
  final glues = includeOther
      ? level.gluesIn(box.inflate(16))
      : const <GlueRef>[];

  final frontier = <Pos>[startPos];
  final visited = <Pos>{startPos};
  final attached = <Pos>{};

  while (frontier.isNotEmpty) {
    final current = frontier.removeAt(0);
    attached.add(current);

    for (final direction in Direction.values) {
      final offset = current.relative(direction);
      final gluePresent = includeOther && isGlued(glues, current, direction);
      final alreadySticky =
          includeOther &&
          (isSideSticky(level.stateAt(current), direction) ||
              isSideSticky(level.stateAt(offset), direction.opposite));

      if (!alreadySticky && !gluePresent && !box.contains(offset.center))
        continue;
      if (!BlockMovementChecks.isMovementNecessary(
        level.stateAt(offset),
        level,
        offset,
      ))
        continue;
      if (!isValidGlueFace(level, current, direction) ||
          !isValidGlueFace(level, offset, direction.opposite)) {
        continue;
      }

      if (visited.add(offset)) frontier.add(offset);
    }
  }

  if (attached.length < 2 && attached.contains(endPos)) return null;
  return attached;
}

/// `SuperGlueSelectionHelper.collectGlueFromInventory`: takes [requiredAmount] charges from the
/// player's glue stacks. With [simulate] nothing is changed.
Future<bool> collectGlueFromInventory(
  Player player,
  int requiredAmount, {
  required bool simulate,
}) async {
  if (requiredAmount == 0) return true;
  if (player.getGamemode() == GameMode.creative) return true;

  final playerInventory = player.getInventory();
  final inventory = playerInventory.asInventory();
  var remaining = requiredAmount;
  final size = inventory.getSize();
  final selected = playerInventory.getSelectedSlot();
  // The selected slot first, then the rest, like `getNonEquipmentItems()`.
  final order = [
    selected,
    for (var i = 0; i < size; i++)
      if (i != selected) i,
  ];

  for (final slot in order) {
    final stack = inventory.getItem(slot: slot);
    if (stack == null) continue;
    final String key;
    try {
      key = await stack.getRegistryKey();
    } catch (_) {
      continue;
    }
    if (key != 'create:super_glue') continue;

    final charges = await _chargesOf(stack);
    final used = remaining < charges ? remaining : charges;
    remaining -= used;
    if (!simulate && used > 0) {
      final left = charges - used;
      if (left <= 0) {
        await inventory.setItem(slot: slot, item: null);
      } else {
        _setCharges(stack, left);
        await inventory.setItem(slot: slot, item: stack);
      }
    }
    if (remaining <= 0) return true;
  }

  return false;
}

/// The remaining charges of a glue stack (the custom data, or the full durability).
Future<int> _chargesOf(ItemStack stack) async {
  try {
    final tree = await stack.getCustomData(
      namespace: glueDataNamespace,
      key: glueDataKey,
    );
    if (tree == null) return glueMaxCharges;
    final value = treeToValue(tree);
    if (value.kind != NbtKind.compound) return glueMaxCharges;
    final charges = NbtMap.of(value).getInt('Charges', glueMaxCharges);
    return charges.clamp(0, glueMaxCharges);
  } on Object {
    return glueMaxCharges;
  }
}

void _setCharges(ItemStack stack, int charges) {
  try {
    stack.setCustomData(
      namespace: glueDataNamespace,
      key: glueDataKey,
      value: valueToTree((NbtMap()..putInt('Charges', charges)).toValue()),
    );
  } on Object {
    // a stack that cannot carry data is left at its default
  }
}

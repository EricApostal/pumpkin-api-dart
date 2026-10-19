// `BasinMovementBehaviour`: a basin on a contraption dumps its items when it is turned upside
// down. Ported from `content/processing/basin/BasinMovementBehaviour.java`.
//
// The basin's saved inventories are the `InputItems` (9 slots) and `OutputItems` (8 slots, as in
// the Java movement behaviour) handlers of the block entity data.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart' hide pos;
import '../../contraptions/core/movement.dart';
import '../../contraptions/core/nbt_map.dart';
import '../../core/nbt.dart' show NbtKind, NbtValue;
import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';

/// The basin as a contraption actor.
class BasinMovementBehaviour extends MovementBehaviour {
  const BasinMovementBehaviour();

  static const String inputKey = 'InputItems';
  static const String outputKey = 'OutputItems';
  static const int inputSlots = 9;

  /// Java's `new CreateItemStackHandler(8)` for the outputs of the actor.
  static const int outputSlots = 8;

  /// `getOrReadInventory`: the input and output handlers saved in [context].
  Map<String, List<PStack>> getOrReadInventory(MovementContext context) {
    final data = context.blockEntityData;
    return {
      inputKey: _readItems(data?.getCompoundOrNull(inputKey), inputSlots),
      outputKey: _readItems(data?.getCompoundOrNull(outputKey), outputSlots),
    };
  }

  @override
  void tick(MovementContext context) {
    super.tick(context);
    final temporary = context.temporaryData;
    if (temporary != null && temporary is! bool) return;
    if (temporary == false) return;

    final facingVec = context.rotation((0.0, 1.0, 0.0)).normalized;
    if (Direction.nearest(facingVec.$1, facingVec.$2, facingVec.$3) !=
        Direction.down) {
      return;
    }
    _dump(context, facingVec);
  }

  /// `dump`: every held item becomes an item entity moving in [facingVec].
  void _dump(MovementContext context, Vec3 facingVec) {
    final data = context.blockEntityData;
    if (data == null) {
      context.temporaryData = false;
      return;
    }
    final position = context.position;
    final world = ProcessingRuntime.instance.worlds.byId(context.worldId);
    // Without a world or a position the items cannot leave the contraption; keep them for the
    // next tick instead of clearing the handlers.
    if (position == null || world == null) return;

    for (final entry in getOrReadInventory(context).entries) {
      for (final stack in entry.value) {
        if (stack.isEmpty) continue;
        unawaited(_drop(world, position, stack, facingVec));
      }
      data.putCompound(
        entry.key,
        _writeItems(List<PStack>.filled(entry.value.length, PStack.empty)),
      );
    }

    context.temporaryData = false;
  }

  static Future<void> _drop(
    World world,
    Vec3 position,
    PStack stack,
    Vec3 facingVec,
  ) async {
    final item = await HostStacks.write(stack);
    if (item == null) return;
    await world.dropItem(
      position,
      item,
      velocity: (facingVec.$1 * .05, facingVec.$2 * .05, facingVec.$3 * .05),
    );
  }

  /// `CreateItemStackHandler.serializeNBT` in the format [StackNbt.writeList] uses.
  static NbtMap _writeItems(List<PStack> stacks) {
    final items = <NbtValue>[];
    for (var slot = 0; slot < stacks.length; slot++) {
      final stack = stacks[slot];
      if (stack.isEmpty) continue;
      final entry = NbtMap()
        ..putString('id', stack.key)
        ..putInt('count', stack.count)
        ..putInt('Slot', slot);
      if (stack.maxStack != 64) entry.putInt('Max', stack.maxStack);
      if (stack.comps.isNotEmpty) {
        entry.putList('Comps', [
          for (final (name, bytes) in stack.comps)
            (NbtMap()
                  ..putString('N', name)
                  ..map['V'] = NbtValue.byteArray(bytes))
                .toValue(),
        ]);
      }
      items.add(entry.toValue());
    }
    return NbtMap()
      ..putList('Items', items)
      ..putInt('Size', stacks.length);
  }

  static List<PStack> _readItems(NbtMap? tag, int size) {
    final out = List<PStack>.filled(size, PStack.empty);
    if (tag == null) return out;
    for (final value in tag.getList('Items')) {
      if (value.kind != NbtKind.compound) continue;
      final entry = NbtMap.of(value);
      final slot = entry.getInt('Slot', -1);
      if (slot < 0 || slot >= size) continue;
      out[slot] = _readStack(entry);
    }
    return out;
  }

  static PStack _readStack(NbtMap entry) {
    final key = entry.getString('id');
    final count = entry.getInt('count');
    if (key.isEmpty || count <= 0) return PStack.empty;

    final comps = <(String, List<int>)>[];
    for (final value in entry.getList('Comps')) {
      if (value.kind != NbtKind.compound) continue;
      final comp = NbtMap.of(value);
      final name = comp.getString('N');
      if (name.isEmpty) continue;
      final bytes = comp.getIntArray('V');
      if (bytes.isEmpty) continue;
      comps.add((name, bytes));
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return PStack(key, count, maxStack: entry.getInt('Max', 64), comps: comps);
  }
}

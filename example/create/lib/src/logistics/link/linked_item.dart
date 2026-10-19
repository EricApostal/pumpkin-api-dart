// `LogisticallyLinkedBlockItem` (pure): the item form of the stock link, stock ticker, redstone
// requester and factory gauge. Like Java, the network is stored in the vanilla
// `minecraft:block_entity_data` component as `Freq` (a UUID). The host does not resolve block
// entity types for that component, so it writes a VarInt type id (always 0) before the NBT; the
// client only reads the compound (see `LogisticallyLinkedClientHandler`).
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/nbt.dart';
import '../model/stack.dart';

/// The vanilla component that marks a stack as tuned.
const String blockEntityDataComponent = 'minecraft:block_entity_data';

/// The four panel slots of a factory gauge item's block entity data (`CreateLang.asId(slot)`).
const List<String> factoryPanelSlotKeys = [
  'top_left',
  'top_right',
  'bottom_left',
  'bottom_right',
];

/// `LogisticallyLinkedBlockItem`'s stack helpers.
abstract final class LinkedItem {
  /// `isTuned(stack)`: `stack.has(DataComponents.BLOCK_ENTITY_DATA)`.
  static bool isTuned(LStack stack) => stack.hasComp(blockEntityDataComponent);

  /// `networkFromStack(stack)`: the `Freq` UUID, `null` when the stack is not tuned.
  static String? networkFromStack(LStack stack) {
    final data = _blockEntityData(stack);
    if (data == null) return null;
    return _readFreq(data);
  }

  /// `assignFrequency(stack, player, frequency)`.
  static LStack assignFrequency(LStack stack, String frequency) {
    final data = _blockEntityData(stack) ?? const <String, NbtValue>{};
    final next = Map<String, NbtValue>.of(data);
    next['Freq'] = NbtValue.intArray(uuidToIntArray(frequency));
    return _withBlockEntityData(stack, next);
  }

  /// `stack.remove(DataComponents.BLOCK_ENTITY_DATA)`.
  static LStack clearTuning(LStack stack) =>
      stack.withComp(blockEntityDataComponent, null);

  /// `FactoryPanelBlockItem.fixCtrlCopiedStack`: a stack that was ctrl-copied from a placed gauge
  /// carries the frequency in one of the four panel slot compounds instead of at the top level.
  /// Returns [stack] unchanged when it is not tuned or already has a top level `Freq`.
  static LStack fixCtrlCopiedStack(
    LStack stack, {
    required String fallbackFrequency,
  }) {
    if (!isTuned(stack) || networkFromStack(stack) != null) return stack;
    final data = _blockEntityData(stack) ?? const <String, NbtValue>{};
    var frequency = fallbackFrequency;
    for (final key in factoryPanelSlotKeys) {
      final panel = data[key];
      if (panel == null || panel.kind != NbtKind.compound) continue;
      final freq = _readFreq(panel.asCompound);
      if (freq != null) {
        frequency = freq;
        break;
      }
    }
    return _withBlockEntityData(stack, {
      'Freq': NbtValue.intArray(uuidToIntArray(frequency)),
    });
  }

  /// The compound of the `minecraft:block_entity_data` component, `null` when absent or unreadable.
  static Map<String, NbtValue>? _blockEntityData(LStack stack) {
    final bytes = stack.compBytes(blockEntityDataComponent);
    if (bytes == null) return null;
    try {
      final root = PacketBuffer.decode(bytes, (r) {
        r.readVarInt(); // the block entity type id; the host writes 0
        return NetworkNbt.read(r);
      });
      return root == null ? null : Map<String, NbtValue>.of(root.asCompound);
    } on Object {
      return null;
    }
  }

  static LStack _withBlockEntityData(LStack stack, Map<String, NbtValue> data) {
    final bytes = PacketBuffer.encode((w) {
      w.writeVarInt(0);
      NetworkNbt.write(w, NbtValue.compound(data));
    });
    return stack.withComp(blockEntityDataComponent, bytes);
  }

  static String? _readFreq(Map<String, NbtValue> data) {
    final freq = data['Freq'];
    if (freq == null || freq.kind != NbtKind.intArray) return null;
    final parts = freq.value as List<int>;
    if (parts.length != 4) return null;
    return uuidFromIntArray(parts);
  }
}

/// `UUIDUtil.CODEC`'s NBT form: four ints (most significant bits first).
List<int> uuidToIntArray(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) throw FormatException('Not a UUID: $uuid');
  final big = BigInt.parse(hex, radix: 16);
  const mask = 0xFFFFFFFF;
  return [
    for (var i = 3; i >= 0; i--)
      ((big >> (32 * i)) & BigInt.from(mask)).toInt(),
  ];
}

/// The inverse of [uuidToIntArray].
String uuidFromIntArray(List<int> parts) {
  var big = BigInt.zero;
  for (final part in parts) {
    big = (big << 32) | BigInt.from(part & 0xFFFFFFFF);
  }
  final hex = big.toRadixString(16).padLeft(32, '0');
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

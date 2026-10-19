// Pure data of the enchantments: the network NBT of the effect components.
import '../core/nbt.dart';

/// The value of the `minecraft:ammo_use` effect component of `create:potato_recovery` as network
/// NBT: a list with one conditional effect `set(linear(0, 33.333332))` that applies when the tool
/// is the potato cannon (`MatchTool.toolMatches(ItemPredicate.Builder.item().of(POTATO_CANNON))`).
List<int> potatoRecoveryAmmoUse() {
  NbtValue str(String s) => NbtValue.string(s);
  final effect = NbtValue.compound({
    'effect': NbtValue.compound({
      'type': str('minecraft:set'),
      'value': NbtValue.compound({
        'type': str('minecraft:linear'),
        'base': const NbtValue.float(0),
        'per_level_above_first': const NbtValue.float(33.333332),
      }),
    }),
    'requirements': NbtValue.compound({
      'condition': str('minecraft:match_tool'),
      'predicate': NbtValue.compound({'items': str('create:potato_cannon')}),
    }),
  });
  return NetworkNbt.encode(NbtValue.list([effect]));
}

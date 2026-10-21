// The linked typewriter payloads.
//
// `linked_typewriter_save` carries a `ByteBufCodecs.map` of key code to
// `KeyboardEntry` — a VarInt count, then each key and entry — followed by the
// block position and the clear flag. `entry_modify` carries two *optional*
// item stacks. `linked_typewriter_bind_item` carries the hand as an int
// ordinal (`InteractionHand.values()[h]`), not the boolean `HAND` codec the
// plunger uses.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.linked_typewriter.*
// create's barrel does not export `ItemStackData` yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/protocol/item_stack.dart' show ItemStackData;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../content/blocks/redstone/linked_typewriter/linked_typewriter_entries.dart';
import '../sim_packet.dart';

/// `simulated:key_interaction` — a key went down or up while the player was at
/// the typewriter.
final class TypewriterKeyInteractionPacket implements SimPacket {
  static const String type = 'simulated:key_interaction';

  final Pos interactionPos;
  final int key;
  final int scanCode;

  /// The GLFW action (`InputConstants.PRESS` is 1).
  final int action;

  const TypewriterKeyInteractionPacket(this.interactionPos, this.key, this.scanCode, this.action);

  /// `InputConstants.PRESS`.
  static const int press = 1;

  /// `InputConstants.RELEASE`.
  static const int release = 0;

  /// Whether this packet is a press (`action == PRESS`).
  bool get isPress => action == press;

  @override
  String get id => type;

  static final SimCodec<TypewriterKeyInteractionPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBlockPos(p.interactionPos)
      ..writeInt(p.key)
      ..writeInt(p.scanCode)
      ..writeInt(p.action),
    (r) => TypewriterKeyInteractionPacket(r.readBlockPos(), r.readInt(), r.readInt(), r.readInt()),
  );
}

/// `simulated:linked_typewriter_save` — the whole key map, or the change when
/// [clearAll] is false.
final class TypewriterKeySavePacket implements SimPacket {
  static const String type = 'simulated:linked_typewriter_save';

  /// The changed keys by key code (insertion order preserved on the wire).
  final Map<int, KeyboardEntry> changedKeys;
  final Pos pos;
  final bool clearAll;

  TypewriterKeySavePacket(Map<int, KeyboardEntry> changedKeys, this.pos, this.clearAll)
    : changedKeys = Map<int, KeyboardEntry>.unmodifiable(changedKeys);

  /// `TypewriterKeySavePacket(keys, pos, clearAll)`.
  factory TypewriterKeySavePacket.fromEntries(LinkedTypewriterEntries keys, Pos pos, bool clearAll) =>
      TypewriterKeySavePacket(keys.keyMap, pos, clearAll);

  @override
  String get id => type;

  static final SimCodec<TypewriterKeySavePacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      w.writeVarInt(p.changedKeys.length);
      p.changedKeys.forEach((key, entry) {
        w.writeInt(key);
        entry.write(w);
      });
      w
        ..writeBlockPos(p.pos)
        ..writeBool(p.clearAll);
    },
    (r) {
      final count = r.readVarInt();
      if (count < 0) throw PacketException('Negative typewriter key count $count');
      final keys = <int, KeyboardEntry>{};
      for (var i = 0; i < count; i++) {
        final key = r.readInt();
        keys[key] = KeyboardEntry.read(r);
      }
      return TypewriterKeySavePacket(keys, r.readBlockPos(), r.readBool());
    },
  );
}

/// `simulated:entry_modify` — the two ghost slots of the typewriter menu.
final class TypewriterMenuModifySlots implements SimPacket {
  static const String type = 'simulated:entry_modify';

  final ItemStackData first;
  final ItemStackData second;

  const TypewriterMenuModifySlots(this.first, this.second);

  @override
  String get id => type;

  static final SimCodec<TypewriterMenuModifySlots> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      p.first.write(w);
      p.second.write(w);
    },
    (r) => TypewriterMenuModifySlots(ItemStackData.read(r), ItemStackData.read(r)),
  );
}

/// `simulated:linked_typewriter_bind_item` — save a key into the held item.
final class TypewriterSaveKeyToItemPacket implements SimPacket {
  static const String type = 'simulated:linked_typewriter_bind_item';

  /// `InteractionHand` ordinal: 0 is the main hand, 1 the off hand.
  final int hand;

  final KeyboardEntry entry;

  const TypewriterSaveKeyToItemPacket(this.hand, this.entry);

  @override
  String get id => type;

  static final SimCodec<TypewriterSaveKeyToItemPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      w.writeInt(p.hand);
      p.entry.write(w);
    },
    (r) => TypewriterSaveKeyToItemPacket(r.readInt(), KeyboardEntry.read(r)),
  );
}

/// `simulated:typewriter_disconnect_user` — the player stepped away.
final class TypewriterDisconnectUser implements SimPacket {
  static const String type = 'simulated:typewriter_disconnect_user';

  final Pos pos;

  const TypewriterDisconnectUser(this.pos);

  @override
  String get id => type;

  static final SimCodec<TypewriterDisconnectUser> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w.writeBlockPos(p.pos),
    (r) => TypewriterDisconnectUser(r.readBlockPos()),
  );
}

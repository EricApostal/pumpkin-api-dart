// The base of the logistics block entities. Their state is a JSON map under `State` (plugin
// private, like [MappableBlockEntity]); the subclasses additionally write the Java NBT keys that a
// Create client reads (the update tag) and that Java persists.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';

abstract class LgBlockEntity extends CreateBlockEntity {
  LgBlockEntity(super.worldId, super.pos);

  @override
  bool get syncsToClient => true;

  /// The current state, read by [stateToMap] and written by [readState].
  Map<String, dynamic> get state;

  /// Loads the state of saved data (an empty map for a new entity).
  void readState(Map<String, dynamic> map);

  /// The state to save.
  Map<String, dynamic> stateToMap();

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    // The JSON is the lossless fallback for saves written before the Java NBT keys existed.
    // Reading it first lets the behaviours and the Java keys below override it.
    if (!clientPacket) {
      final json = tag.getString('State');
      if (json != null) {
        try {
          readState((jsonDecode(json) as Map).cast<String, dynamic>());
        } on Object {
          readState(const {});
        }
      }
    }
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    // The private JSON is not part of the update tag; the subclasses write the client keys.
    if (!clientPacket) tag.putString('State', jsonEncode(stateToMap()));
    super.write(tag, clientPacket: clientPacket);
  }
}

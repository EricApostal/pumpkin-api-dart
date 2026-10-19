// The base of the logistics block entities. Their state is a JSON map under `State` (plugin
// private, like [MappableBlockEntity]); the Create client visuals are out of scope, so nothing is
// synced to the client.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';

abstract class LgBlockEntity extends CreateBlockEntity {
  LgBlockEntity(super.worldId, super.pos);

  @override
  bool get syncsToClient => false;

  /// The current state, read by [stateToMap] and written by [readState].
  Map<String, dynamic> get state;

  /// Loads the state of saved data (an empty map for a new entity).
  void readState(Map<String, dynamic> map);

  /// The state to save.
  Map<String, dynamic> stateToMap();

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    final json = tag.getString('State');
    if (json == null) return;
    try {
      readState((jsonDecode(json) as Map).cast<String, dynamic>());
    } on Object {
      readState(const {});
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (!clientPacket) tag.putString('State', jsonEncode(stateToMap()));
  }
}

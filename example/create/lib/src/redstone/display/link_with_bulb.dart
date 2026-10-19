// `LinkWithBulbBlockEntity`: the base of block entities that carry a redstone link bulb
// (`DisplayLinkBlockEntity`; the packager link of the logistics module has its own state).
// The server only has to put the `Pulse` marker into the client update tag; the glow itself
// is client rendering.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' show NbtHelper;
import '../../core/block_entity.dart';

abstract class LinkWithBulbBlockEntity extends CreateBlockEntity {
  LinkWithBulbBlockEntity(super.worldId, super.pos);

  bool _sendPulse = false;

  /// `sendPulseNextSync`: the next client sync carries the `Pulse` marker.
  void sendPulseNextSync() => _sendPulse = true;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket && _sendPulse) {
      _sendPulse = false;
      NbtHelper.putMarker(tag, 'Pulse');
    }
  }
}

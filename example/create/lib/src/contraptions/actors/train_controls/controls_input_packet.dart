// `ControlsInputPacket`: the held keys a client sends while driving a train from the controls block.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';

/// `ControlsInputPacket`.
final class ControlsInputPacket {
  final List<int> activatedButtons;
  final bool press;
  final int contraptionEntityId;
  final Pos controlsPos;
  final bool stopControlling;

  const ControlsInputPacket(
    this.activatedButtons,
    this.press,
    this.contraptionEntityId,
    this.controlsPos,
    this.stopControlling,
  );

  /// `STREAM_CODEC`: a VarInt list of buttons, the press flag, the entity id (int), the controls
  /// position (packed long) and the stop flag.
  static final PayloadCodec<ControlsInputPacket> codec = PayloadCodec.buffer(
    write: (w, v) {
      w.writeList<int>(
        v.activatedButtons,
        (ww, button) => ww.writeVarInt(button),
      );
      w.writeBool(v.press);
      w.writeInt(v.contraptionEntityId);
      w.writeBlockPos(v.controlsPos);
      w.writeBool(v.stopControlling);
    },
    read: (r) => ControlsInputPacket(
      r.readList<int>((rr) => rr.readVarInt()),
      r.readBool(),
      r.readInt(),
      r.readBlockPos(),
      r.readBool(),
    ),
  );
}

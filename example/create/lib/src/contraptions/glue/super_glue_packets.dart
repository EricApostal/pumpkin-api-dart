// The glue payload handlers (`create:glue_in_area`, `create:glue_removed`, `create:glue_effect`).
// The channels are declared by the protocol module; this binds the handlers to the payload bus.
//
// Java: `content/contraptions/glue/{SuperGlueSelectionPacket,SuperGlueRemovalPacket,GlueEffectPacket}`.
import '../../api/payloads.dart';
import 'super_glue_selection_handler.dart';

/// `create:glue_in_area` and `create:glue_removed` handlers.
void bindGluePackets(PayloadBus bus) {
  bus.onServerbound('create:glue_in_area', (player, fields) {
    final from = fields['from'] as (int, int, int);
    final to = fields['to'] as (int, int, int);
    handleGlueSelection(player, from, to);
  });

  bus.onServerbound('create:glue_removed', (player, fields) {
    final entityId = fields['entityId'] as int;
    final soundSource = fields['soundSource'] as (int, int, int);
    handleGlueRemoval(player, entityId, soundSource);
  });
}

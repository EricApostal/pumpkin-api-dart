// The server side of the glue selection: `SuperGlueSelectionPacket.handle` and
// `SuperGlueRemovalPacket.handle`. The client handler (`SuperGlueSelectionHandler`, an outliner and
// hover preview) is a rendering concern and is not ported.
//
// Java: `content/contraptions/glue/{SuperGlueSelectionPacket,SuperGlueRemovalPacket}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../blocks/actuator_contract.dart';
import 'super_glue_entity.dart';
import 'super_glue_selection_helper.dart';

/// `SuperGlueSelectionPacket.handle`: glue the group between [from] and [to] if the player can
/// reach it and has a charge.
Future<void> handleGlueSelection(Player player, Pos from, Pos to) async {
  final world = player.getWorld();
  final worldId = world.getId();
  final level = ActuatorHosts.levelOf(worldId);
  final glueHost = ActuatorHosts.glue;
  if (level == null || glueHost == null) return;

  final playerPos = player.asEntity().getPosition();
  if ((to.center - playerPos).lengthSquared > 6 * 6) return;
  if (!to.closerThan(from, 25)) return;

  final group = searchGlueGroup(level, from, to, includeOther: false);
  if (group == null || !group.contains(to)) return;
  if (!await collectGlueFromInventory(player, 1, simulate: true)) return;

  await collectGlueFromInventory(player, 1, simulate: false);
  glueHost.spawn(worldId, glueSpan(from, to));
}

/// `SuperGlueRemovalPacket.handle`: remove the glue entity the player clicked.
Future<void> handleGlueRemoval(
  Player player,
  int entityId,
  Pos soundSource,
) async {
  final world = player.getWorld();
  final worldId = world.getId();
  final glueHost = ActuatorHosts.glue;
  if (glueHost == null) return;

  final glue = glueHost.glueById(worldId, entityId);
  if (glue == null) return;
  final playerPos = player.asEntity().getPosition();
  if ((glue.box.center - playerPos).lengthSquared > 32 * 32) return;
  glueHost.discard(worldId, entityId);
}

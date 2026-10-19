// The host half of `placement.dart`: the placing player's view as a [PlaceCtx] and the
// world queries of [PlaceWorld].
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import 'level.dart';
import 'placement.dart';

/// [PlaceWorld] over a host world.
final class HostPlaceWorld implements PlaceWorld {
  final Lvl lvl;

  /// Extra check of [canDetect] (other modules' observable block entities).
  final bool Function(Pos pos)? detectBlockEntity;

  const HostPlaceWorld(this.lvl, {this.detectBlockEntity});

  @override
  bool isFaceSturdy(Pos pos, Direction face) {
    final s = lvl.world.getBlockState(pos: pos.toBlockPos());
    return switch (face) {
      Direction.down => s.downSideSolid,
      Direction.up => s.upSideSolid,
      Direction.north => s.northSideSolid,
      Direction.south => s.southSideSolid,
      Direction.west => s.westSideSolid,
      Direction.east => s.eastSideSolid,
    };
  }

  @override
  bool canBeReplaced(Pos pos) => lvl.canBeReplaced(pos);

  @override
  bool canDetect(Pos pos) {
    final w = lvl.world;
    final bp = pos.toBlockPos();
    if (detectBlockEntity?.call(pos) ?? false) return true;
    // A vanilla container or tank: item or fluid handler reachable from any side.
    if (ItemHandlers.at(w, bp) != null) return true;
    if (w.fluidHandlerAt(bp) != null) return true;
    return false;
  }
}

/// The view of the player that placed a block, `null` when it was not a player (or the
/// player is gone).
PlaceCtx? placeContextOf(Server server, CustomBlockPlacedEventData e) {
  final uuid = e.player;
  if (uuid == null) return null;
  final player = server.getPlayerByUuid(id: uuid);
  if (player == null) return null;
  final pos = e.pos.toPos();
  Direction? clicked;
  try {
    final hit = player.asEntity().rayTraceBlock(maxDistance: 8, includeFluids: false);
    if (hit != null) {
      final hitPos = hit.pos.toPos();
      if (hitPos == pos || hitPos.relative(hit.face.toDirection()) == pos) clicked = hit.face.toDirection();
    }
  } on Object {
    clicked = null;
  }
  return PlaceCtx(
    pos: pos,
    yaw: player.getYaw(),
    pitch: player.getPitch(),
    sneaking: player.asEntity().isSneaking(),
    clickedFace: clicked,
  );
}

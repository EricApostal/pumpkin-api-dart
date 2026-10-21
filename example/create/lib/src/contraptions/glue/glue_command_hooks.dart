// `GlueCommandHooks`: the glue handling of `/create glue` and `/create clone`, which the
// infrastructure commands ask the contraptions module for. Without a provider both commands stop
// working (`/create glue` answers "<x> is not available" and `/create clone` silently applies no
// glue at all), so nothing can glue a structure together from the console.
//
// Java: `infrastructure/command/GlueCommand.java` and `CloneCommand.cloneGlue`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/infra.dart';
import '../../common/bounds.dart';
import '../../common/pos.dart';
import '../blocks/actuator_contract.dart';
import 'super_glue_entity.dart';

/// The `GlueCommandHooks` over a world's glue entities (`GlueEntityHost`).
final class HostGlueCommandHooks implements GlueCommandHooks {
  HostGlueCommandHooks(this.glue);

  final GlueEntityHost glue;

  /// `new SuperGlueEntity(world, SuperGlueEntity.span(from, to))` + `addFreshEntity`: one glue
  /// entity spanning the two positions, with no reach or charge check (unlike the item's own
  /// selection packet, `SuperGlueSelectionPacket.handle`).
  ///
  /// `SuperGlueEntity.playPlaceSound` is a client-side sound and stays unported.
  @override
  Future<bool> placeGlue(World world, Pos from, Pos to) async {
    glue.spawn(world.getId(), glueSpan(from, to));
    return true;
  }

  /// `CloneCommand.cloneGlue`: every glue entity overlapping the source area, cropped to it and
  /// moved by [offset] (the destination's lower corner minus the source's). The originals stay.
  @override
  Future<int> cloneGlue(World world, BlockBounds area, Pos offset) async {
    final worldId = world.getId();
    // `new AABB(minX, minY, minZ, maxX + 1, maxY + 1, maxZ + 1)` of the inclusive bounding box.
    final source = Aabb(
      area.minX.toDouble(),
      area.minY.toDouble(),
      area.minZ.toDouble(),
      (area.maxX + 1).toDouble(),
      (area.maxY + 1).toDouble(),
      (area.maxZ + 1).toDouble(),
    );
    final cropped = collectCroppedGlue(glue.gluesIn(worldId, source), source);
    final delta = offset.toVec3();
    for (final box in cropped) {
      glue.spawn(worldId, box.moveBy(delta));
    }
    return cropped.length;
  }
}
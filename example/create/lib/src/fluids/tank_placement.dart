// `FluidTankItem.tryMultiPlace`: a tank placed on the top or bottom of a wider tank places the
// whole layer, not one tank.
//
// This is the geometry only, with no host access, so it can be tested on the VM
// (`fluid_blocks.dart` imports the wasm bindings and cannot be). The block entity side - which
// tank multiblock the placed tank touches and how many tanks the player has - lives in
// `_tryTankMultiPlace` there.
import '../common/pos.dart';

/// One tank multiblock as the placement needs it: the controller's corner
/// (`FluidTankBlockEntity.getBlockPos()`) and its size (`width` / `height`).
typedef TankExtent = ({Pos controller, int width, int height});

/// `FluidTankItem.tryMultiPlace` (`FluidTankItem.java:66-121`).
///
/// [pos] is the position the tank was placed at; [below] and [above] are the tank multiblocks
/// directly underneath and over it (`null` when there is no tank there). Returns the positions of
/// the layer to place into, in Java's order and with the tanks that are already there left out, or
/// `null` when this placement does not extend a tank. An empty list means the layer is complete.
///
/// Java also requires the clicked face to be vertical (`FluidTankItem.java:70-73`). The placed
/// event does not carry the face, so the x/z footprint stands in for it: a tank put on the *side*
/// of a multiblock lands outside that multiblock's footprint, while one put on its top or bottom
/// lands inside it. When a tank is both above and below [pos] (a one-block gap between two tanks),
/// Java picks the side the face points at; without the face this prefers the tank below.
List<Pos>? tankLayerTargets({
  required Pos pos,
  required TankExtent? below,
  required TankExtent? above,
  required bool Function(Pos pos) isTank,
  required bool Function(Pos pos) canBeReplaced,
}) {
  for (final (extent, onTop) in [(below, true), (above, false)]) {
    if (extent == null) continue;
    final controller = extent.controller;
    // `if (width == 1) return;`
    if (extent.width <= 1) continue;
    // `if (startPos.getY() != pos.getY()) return;` - the placed tank is on this multiblock's
    // top (or bottom) plane.
    final start = onTop
        ? controller.aboveBy(extent.height)
        : controller.below;
    if (start.$2 != pos.$2) continue;
    // `placedOnPos = pos.relative(face.getOpposite())` is a block of this multiblock, so the
    // placed tank lies over its footprint. A side placement lies outside it.
    if (pos.$1 < controller.$1 || pos.$1 >= controller.$1 + extent.width) {
      continue;
    }
    if (pos.$3 < controller.$3 || pos.$3 >= controller.$3 + extent.width) {
      continue;
    }

    final targets = <Pos>[];
    for (var x = 0; x < extent.width; x++) {
      for (var z = 0; z < extent.width; z++) {
        final p = start.offset(x, 0, z);
        if (isTank(p)) continue;
        // `if (!blockState.canBeReplaced()) return;` - one blocked position cancels the whole
        // layer, it is not skipped.
        if (!canBeReplaced(p)) return null;
        targets.add(p);
      }
    }
    return targets;
  }
  return null;
}

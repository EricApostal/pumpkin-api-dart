// `ControlsBlock`: the train controls (and the base of the contraption controls). It sits on a
// carriage, faces the driver and is `open` while it is on a contraption.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart' show manifestBlock;
import '../../../common/common.dart';
import '../../../core/blocks.dart';
import '../actor_shapes.dart';

/// `AllShapes.CONTROLS`: selection (with the small step) and collision.
final List<BlockBox> controlsShape = [
  actorBox(0, 0, 6, 16, 16, 16),
  actorBox(0, 0, 4, 16, 2, 16),
];
final List<BlockBox> controlsCollision = [actorBox(0, 0, 6, 16, 16, 16)];

/// `ControlsBlock` of the key [key] with the given [selection] and [collision] boxes.
CreateBlock buildControlsBlock(
  String key, {
  required List<BlockBox> selection,
  required List<BlockBox> collision,
  String? blockEntityType,
  BlockBehavior? behavior,
}) {
  return manifestBlock(
    key,
    blockEntityType: blockEntityType,
    placement: const [
      // `ControlsBlock.getStateForPlacement` (javap-verified): the opposite of the player's
      // horizontal look, or the look itself when the player sneaks.
      PlacementRule.horizontalFacing('facing', opposite: true, whenSneaking: false),
      PlacementRule.horizontalFacing('facing', whenSneaking: true),
      PlacementRule.inWater('waterlogged'),
    ],
    collisionShape: BlockShape.boxes(collision),
    selectionShape: BlockShape.boxes(selection),
    shapeRules: [
      for (final d in Direction.planeHorizontal)
        ShapeRule(
          when: {'facing': d.serializedName},
          collisionShape: BlockShape.boxes(
            rotateActorBoxes(collision, Direction.north, d),
          ),
          selectionShape: BlockShape.boxes(
            rotateActorBoxes(selection, Direction.north, d),
          ),
        ),
    ],
    behavior: behavior,
  );
}

/// `ControlsBlock` (`create:controls`).
CreateBlock buildTrainControlsBlock() => buildControlsBlock(
  'controls',
  selection: controlsShape,
  collision: controlsCollision,
);

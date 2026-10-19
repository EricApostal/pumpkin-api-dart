// State-property helpers shared by the logistics blocks (pure): the connected direction of the
// face-attached blocks (`FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`).
import '../../common/direction.dart';

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection(state)`: the direction from the
/// attached block towards the block it hangs on.
Direction faceConnectedDirection(Map<String, String> properties) {
  final face = properties['face'] ?? 'floor';
  final facing =
      Direction.byName(properties['facing'] ?? 'north') ?? Direction.north;
  return switch (face) {
    'ceiling' => Direction.up,
    'floor' => Direction.down,
    _ => facing,
  };
}

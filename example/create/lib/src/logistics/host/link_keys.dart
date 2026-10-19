// The block state properties shared by the face attached logistics blocks (manifest value order).
import 'package:pumpkin_api/pumpkin_api.dart';

/// `AttachFace`: floor, wall, ceiling.
final BlockProperty attachFaceProperty = BlockProperty.enumeration('face', [
  'floor',
  'wall',
  'ceiling',
]);

/// `HorizontalDirectionalBlock.FACING` in the manifest value order.
final BlockProperty horizontalFacingProperty = BlockProperty.enumeration(
  'facing',
  ['north', 'south', 'west', 'east'],
);

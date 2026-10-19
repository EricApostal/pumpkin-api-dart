// `TrackBlockStateGenerator`: the blockstate metadata of a track block (Java: a
// `SpecialBlockStateGen`). The port does not generate models; it keeps the mapping the generator
// encodes - the model rotation and the model file of a `shape` - for tools and for anything that
// needs to know which model a track state uses.
import '../../api/block_state.dart';
import 'i_track_block.dart';
import 'track_shape.dart';

abstract final class TrackBlockStateGenerator {
  /// `getXRotation`: tracks never pitch their model.
  static int xRotation(BState state) => 0;

  /// `getYRotation`: the model rotation of the `shape` property.
  static int yRotation(BState state) => trackShapeOf(state).getModelRotation();

  /// `getModel`: `create:block/track/<model>`, or `minecraft:block/air` for the `none` shape.
  static String modelOf(BState state) {
    final shape = trackShapeOf(state);
    if (shape == TrackShape.none) return 'minecraft:block/air';
    return 'create:block/track/${shape.getModel()}';
  }
}

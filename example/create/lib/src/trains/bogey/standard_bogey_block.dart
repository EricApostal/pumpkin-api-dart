// `StandardBogeyBlock` (pure): the small and large bogeys of `create:standard`.
import '../../common/common.dart';
import '../track/track_material.dart';
import 'abstract_bogey_block.dart';
import 'bogey_sizes.dart';
import 'bogey_style.dart';

/// `StandardBogeyBlock`.
class StandardBogeyBlock extends AbstractBogeyBlock {
  StandardBogeyBlock(super.key, super.size);

  /// The two blocks of the manifest: `small_bogey` and `large_bogey`, registered and added to the
  /// standard bogey cycle (the `BuilderTransformers.bogey()` `onRegister`).
  static List<StandardBogeyBlock> registerStandardBlocks() {
    final existing = [AbstractBogeyBlock.byKey('create:small_bogey'), AbstractBogeyBlock.byKey('create:large_bogey')];
    if (existing[0] is StandardBogeyBlock && existing[1] is StandardBogeyBlock) {
      return [existing[0]! as StandardBogeyBlock, existing[1]! as StandardBogeyBlock];
    }
    final small = StandardBogeyBlock('create:small_bogey', BogeySizes.SMALL)..register();
    AbstractBogeyBlock.registerStandardBogey(small.key);
    final large = StandardBogeyBlock('create:large_bogey', BogeySizes.LARGE)..register();
    AbstractBogeyBlock.registerStandardBogey(large.key);
    return [small, large];
  }

  @override
  TrackType getTrackType(BogeyStyle style) => TrackType.STANDARD;

  @override
  double getWheelPointSpacing() => 2;

  @override
  double getWheelRadius() => (size == BogeySizes.LARGE ? 12.5 : 6.5) / 16;

  @override
  Vec3 getConnectorAnchorOffsetBase() => (0.0, 7 / 32, 1.0);

  @override
  BogeyStyle getDefaultStyle() => AllBogeyStyles.STANDARD;
}

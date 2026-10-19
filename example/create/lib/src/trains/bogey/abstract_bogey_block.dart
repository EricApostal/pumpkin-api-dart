// `AbstractBogeyBlock` (pure): the rules of a bogey block - sizes, styles, sticky surfaces, the
// upgrade between sizes / styles and the rotation cycle - over [BState]s, so they run on the Dart VM.
// The host side (block registration, the wrench / item interaction) is in `bogey_blocks.dart`; the
// block entity is `abstract_bogey_block_entity.dart`.
//
// Java -> Dart: `defaultBlockState()` -> [defaultBlockState]; `BlockState.getValue(AXIS)` ->
// `state[axisProperty]`; blocks are looked up by their key with [AbstractBogeyBlock.byKey].
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../entity/carriage.dart';
import '../entity/carriage_bogey.dart';
import '../entity/travelling_point.dart';
import '../graph/track_edge.dart';
import '../track/track_material.dart';
import 'bogey_sizes.dart';
import 'bogey_style.dart';

/// `AbstractBogeyBlock<T>`.
abstract class AbstractBogeyBlock {
  /// `AXIS`: the `axis` property (`HORIZONTAL_AXIS`).
  static const String axisProperty = 'axis';
  static const String waterloggedProperty = 'waterlogged';

  /// The registered bogey blocks by key (the lookup of `BuiltInRegistries.BLOCK`).
  static final Map<String, AbstractBogeyBlock> _byKey = {};

  /// `BOGEYS`: the block keys of the standard bogey cycle, in registration order.
  static final List<String> _bogeys = [];

  /// The block key (`create:small_bogey`).
  final String key;

  /// `size`.
  final BogeySize size;

  AbstractBogeyBlock(this.key, this.size);

  /// Registers the block under its key so styles, the wrench cycle and saved trains can find it.
  void register() => _byKey[key] = this;

  /// The bogey block with [key], or `null`.
  static AbstractBogeyBlock? byKey(String key) => _byKey[key];

  /// All registered bogey blocks.
  static Iterable<AbstractBogeyBlock> get all => _byKey.values;

  /// `registerStandardBogey(block)`: adds a block key to the standard wrench cycle.
  static void registerStandardBogey(String block) => _bogeys.add(block);

  // -- Rules to implement -----------------------------------------------------------------------

  /// `getTrackType(style)`.
  TrackType getTrackType(BogeyStyle style);

  /// `getWheelPointSpacing()`.
  double getWheelPointSpacing();

  /// `getWheelRadius()`.
  double getWheelRadius();

  /// `getConnectorAnchorOffset()`: implement, but do not call directly.
  Vec3 getConnectorAnchorOffsetBase();

  /// `getDefaultStyle()`.
  BogeyStyle getDefaultStyle();

  /// The default state of the block (`defaultBlockState()`): `axis=x, waterlogged=false`.
  BState defaultBlockState() => BState(key, const {axisProperty: 'x', waterloggedProperty: 'false'});

  // -- Rules with defaults ----------------------------------------------------------------------

  /// `isOnIncompatibleTrack(carriage, leading)`.
  bool isOnIncompatibleTrack(Carriage carriage, bool leading) {
    final TravellingPoint point = leading ? carriage.getLeadingPoint() : carriage.getTrailingPoint();
    final CarriageBogey bogey = leading ? carriage.leadingBogey() : carriage.trailingBogey();
    final TrackEdge? currentEdge = point.edge;
    if (currentEdge == null) return false;
    return currentEdge.getTrackMaterial().trackType != getTrackType(bogey.getStyle());
  }

  /// `getValidPathfindingTypes(style)`.
  Set<TrackType> getValidPathfindingTypes(BogeyStyle style) => {getTrackType(style)};

  /// `getStickySurfaces(world, pos, state)`: east and west for an `x` bogey, south and north otherwise.
  Set<Direction> getStickySurfaces(BlockGetter world, Pos pos, BState state) =>
      state.axisOf(axisProperty) == Axis.x ? stickyX : stickyZ;

  static const Set<Direction> stickyX = {Direction.east, Direction.west};
  static const Set<Direction> stickyZ = {Direction.south, Direction.north};

  /// `getConnectorAnchorOffset(upsideDown)`.
  Vec3 getConnectorAnchorOffset(bool upsideDown) => getConnectorAnchorOffsetBase();

  /// `allowsSingleBogeyCarriage()`.
  bool allowsSingleBogeyCarriage() => true;

  /// `captureBlockEntityForTrain()`: the legacy system does not capture bogey block entities.
  bool captureBlockEntityForTrain() => false;

  /// `getSize()`.
  BogeySize getSize() => size;

  /// `getBogeyUpDirection()`.
  Direction getBogeyUpDirection() => Direction.up;

  /// `isTrackAxisAlongFirstCoordinate(state)`.
  bool isTrackAxisAlongFirstCoordinate(BState state) => state.axisOf(axisProperty) == Axis.x;

  /// `getMatchingBogey(upDirection, axisAlongFirst)`.
  BState? getMatchingBogey(Direction upDirection, bool axisAlongFirst) {
    if (upDirection != Direction.up) return null;
    return defaultBlockState().setValue(axisProperty, axisAlongFirst ? 'x' : 'z');
  }

  /// `canBeUpsideDown()`.
  bool canBeUpsideDown() => false;

  /// `isUpsideDown(state)`.
  bool isUpsideDown(BState state) => false;

  /// `getVersion(base, upsideDown)`.
  BState getVersion(BState base, bool upsideDown) => base;

  /// `getBogeyBlockCycle()`: if you prefer separate blocks to the style cycle, return them here.
  List<String> getBogeyBlockCycle() => _bogeys;

  /// `propertiesToCopy()`: the state properties to copy between sizes.
  List<String> propertiesToCopy() => const [waterloggedProperty, axisProperty];

  // -- Wrench rotation and block transforms -----------------------------------------------------

  /// `getRotatedBlockState(state, targetedFace)`: the next bogey block of the cycle that has a bogey
  /// for the same up direction and track axis, with the properties of [state].
  BState getRotatedBlockState(BState state, Direction targetedFace) {
    final bogeyCycle = getBogeyBlockCycle();
    final indexOf = bogeyCycle.indexOf(state.key);
    if (indexOf == -1) return state;
    var index = (indexOf + 1) % bogeyCycle.length;
    final bogeyUpDirection = getBogeyUpDirection();
    final trackAxisAlongFirstCoordinate = isTrackAxisAlongFirstCoordinate(state);

    while (index != indexOf) {
      final newBlock = _byKey[bogeyCycle[index]];
      if (newBlock != null) {
        final matchingBogey = newBlock.getMatchingBogey(bogeyUpDirection, trackAxisAlongFirstCoordinate);
        if (matchingBogey != null) return copyProperties(state, matchingBogey);
      }
      index = (index + 1) % bogeyCycle.length;
    }
    return state;
  }

  /// `rotate(state, rotation)`: a quarter turn flips the axis.
  BState rotate(BState state, BlockRotation rotation) => switch (rotation) {
    BlockRotation.counterclockwise90 || BlockRotation.clockwise90 => _cycleAxis(state),
    _ => state,
  };

  static BState _cycleAxis(BState state) {
    final axis = state[axisProperty];
    if (axis == null) return state;
    // `BlockState.cycle(HORIZONTAL_AXIS)`: x -> z -> x
    return state.setValue(axisProperty, axis == 'x' ? 'z' : 'x');
  }

  // -- Sizes and styles -------------------------------------------------------------------------

  /// `copyProperties(source, target)`: copies [propertiesToCopy] that both states have.
  BState copyProperties(BState source, BState target) {
    for (final property in propertiesToCopy()) {
      if (source.has(property) && target.has(property)) target = target.setValue(property, source[property]!);
    }
    return target;
  }

  /// `getNextSize(sbbe)`: the state of the next larger size of [style], keeping the properties of
  /// [current] (the state of the bogey block entity).
  BState getNextSize(BogeyStyle style, BState current) {
    final nextBlock = style.getNextBlock(size).defaultBlockState();
    return copyProperties(current, nextBlock);
  }

  /// `getStateOfSize(sbbe, size)`.
  BState getStateOfSize(BogeyStyle style, BState current, BogeySize size) {
    final state = style.getBlockForSize(size).defaultBlockState();
    return copyProperties(current, state);
  }

  /// `getNextStyle(style)`: the next style of the cycle group (the same style when it is alone).
  BogeyStyle getNextStyle(BogeyStyle style) {
    final allStyles = style.getCycleGroup().values;
    if (allStyles.length <= 1) return style;
    return Iterate.cycleValue(allStyles.toList(), style);
  }
}

// `ITrackBlock` (pure): what the graph, the placement and the stations need to know about a track
// block, with the default methods of the Java interface. [TrackBlock] is the only block of Create
// that implements it; add-on tracks extend [ITrackBlock] too and call [TrackBlockRegistry.register].
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../graph/dimension_palette.dart' show overworldId;
import '../graph/track_node_location.dart';
import 'bezier_connection.dart';
import 'track_level.dart';
import 'track_material.dart';
import 'track_shape.dart';

/// The `shape` property of the track block.
const String trackShapeProperty = 'shape';

/// The `turn` property (`TrackBlock.HAS_BE`).
const String trackHasBeProperty = 'turn';

/// `state.getValue(TrackBlock.SHAPE)`.
TrackShape trackShapeOf(BState state) => TrackShape.byName(state[trackShapeProperty] ?? '') ?? TrackShape.none;

/// `state.setValue(TrackBlock.SHAPE, shape)`.
BState withTrackShape(BState state, TrackShape shape) => state.setValue(trackShapeProperty, shape.serializedName);

/// `state.getValue(TrackBlock.HAS_BE)`.
bool hasBe(BState state) => state.flag(trackHasBeProperty);

/// `state.setValue(TrackBlock.HAS_BE, value)`.
BState withHasBe(BState state, bool value) => state.setFlag(trackHasBeProperty, value);

/// Every `ITrackBlock` by block key (`block instanceof ITrackBlock`, the `create:tracks` tag).
abstract final class TrackBlockRegistry {
  static final Map<String, ITrackBlock> _byKey = {};

  static void register(String blockKey, ITrackBlock block) => _byKey[blockKey] = block;

  static void clear() => _byKey.clear();

  /// The track block with [blockKey], `null` for other blocks.
  static ITrackBlock? of(String blockKey) => _byKey[blockKey];

  /// `state.getBlock() instanceof ITrackBlock`.
  static ITrackBlock? ofState(BState state) => _byKey[state.key];

  /// `AllBlockTags.TRACKS.matches(state)`.
  static bool isTrack(BState state) => _byKey.containsKey(state.key);

  static Iterable<String> get keys => _byKey.keys;
}

abstract class ITrackBlock {
  Vec3 getUpNormal(BlockGetter world, Pos pos, BState state);

  List<Vec3> getTrackAxes(BlockGetter world, Pos pos, BState state);

  Vec3 getCurveStart(BlockGetter world, Pos pos, BState state, Vec3 axis);

  int getYOffsetAt(BlockGetter world, Pos pos, BState state, Vec3 end) => 0;

  /// Should be on bogey side.
  BState getBogeyAnchor(BlockGetter world, Pos pos, BState state);

  bool trackEquals(BState state1, BState state2);

  BState overlay(BlockGetter world, Pos pos, BState existing, BState placed) => existing;

  double getElevationAtCenter(BlockGetter world, Pos pos, BState state) => isSlope(world, pos, state) ? .5 : 0;

  /// `walkConnectedTracks(world, location, linear)`.
  static List<DiscoveredLocation> walkConnectedTracks(BlockGetter worldIn, TrackNodeLocation location, bool linear) {
    final BlockGetter world = worldIn is TrackLevel ? (worldIn.getLevel(location.dimension) ?? worldIn) : worldIn;
    final list = <DiscoveredLocation>[];
    for (final blockPos in location.allAdjacent()) {
      final blockState = world.stateAt(blockPos);
      final track = TrackBlockRegistry.ofState(blockState);
      if (track != null) list.addAll(track.getConnected(world, blockPos, blockState, linear, location));
    }
    return list;
  }

  /// `getConnected(world, pos, state, linear, connectedTo)`.
  List<DiscoveredLocation> getConnected(
    BlockGetter worldIn,
    Pos pos,
    BState state,
    bool linear,
    TrackNodeLocation? connectedTo,
  ) {
    final BlockGetter world = connectedTo != null && worldIn is TrackLevel
        ? (worldIn.getLevel(connectedTo.dimension) ?? worldIn)
        : worldIn;
    final center = atBottomCenterOf(pos) + (0.0, getElevationAtCenter(world, pos, state), 0.0);
    final list = <DiscoveredLocation>[];
    final shape = trackShapeOf(state);
    final trackAxes = getTrackAxes(world, pos, state);

    for (final axis in trackAxes) {
      Vec3 offsetFactory(double d, bool b) => axis * (b ? d : -d) + center;
      String dimensionFactory(bool b) => world is TrackLevel ? world.dimension : overworldId;
      int yOffsetFactory(Vec3 v) => getYOffsetAt(world, pos, state, v);

      addToListIfConnected(
        connectedTo,
        list,
        offsetFactory,
        (b) => shape.getNormal(),
        dimensionFactory,
        yOffsetFactory,
        axis,
        null,
        (b, v) => getMaterialSimple(world, v),
      );
    }

    return list;
  }

  /// `getMaterialSimple(world, pos)`.
  static TrackMaterial getMaterialSimple(BlockGetter? world, Vec3 pos, [TrackMaterial? defaultMaterial]) {
    defaultMaterial ??= TrackMaterial.ANDESITE;
    if (world != null) {
      final track = TrackBlockRegistry.ofState(world.stateAt(posContaining(pos)));
      if (track != null) return track.getMaterial();
    }
    return defaultMaterial;
  }

  /// `addToListIfConnected(...)`.
  static void addToListIfConnected(
    TrackNodeLocation? fromEnd,
    List<DiscoveredLocation> list,
    Vec3 Function(double d, bool b) offsetFactory,
    Vec3 Function(bool b) normalFactory,
    String Function(bool b) dimensionFactory,
    int Function(Vec3 v) yOffsetFactory,
    Vec3? axis,
    BezierConnection? viaTurn,
    TrackMaterial Function(bool b, Vec3 v) materialFactory,
  ) {
    final firstOffset = offsetFactory(0.5, true);
    final firstLocation = DiscoveredLocation.fromVec(dimensionFactory(true), firstOffset)
        .viaTurn(viaTurn)
        .materialA(materialFactory(true, offsetFactory(0.0, true)))
        .materialB(materialFactory(true, offsetFactory(1.0, true)))
        .withNormal(normalFactory(true))
        .withDirection(axis)
        .withYOffset(yOffsetFactory(firstOffset));

    final secondOffset = offsetFactory(0.5, false);
    final secondLocation = DiscoveredLocation.fromVec(dimensionFactory(false), secondOffset)
        .viaTurn(viaTurn)
        .materialA(materialFactory(false, offsetFactory(0.0, false)))
        .materialB(materialFactory(false, offsetFactory(1.0, false)))
        .withNormal(normalFactory(false))
        .withDirection(axis)
        .withYOffset(yOffsetFactory(secondOffset));

    if (firstLocation.dimension != secondLocation.dimension) {
      firstLocation.forceNode();
      secondLocation.forceNode();
    }

    var skipFirst = false;
    var skipSecond = false;

    if (fromEnd != null) {
      final equalsFirst = firstLocation == fromEnd;
      final equalsSecond = secondLocation == fromEnd;

      // not reachable from this end
      if (!equalsFirst && !equalsSecond) return;

      if (equalsFirst) skipFirst = true;
      if (equalsSecond) skipSecond = true;
    }

    if (!skipFirst) list.add(firstLocation);
    if (!skipSecond) list.add(secondLocation);
  }

  /// `isSlope(world, pos, state)`.
  bool isSlope(BlockGetter world, Pos pos, BState state) => getTrackAxes(world, pos, state)[0].y != 0;

  /// `getNearestTrackAxis(world, pos, state, lookVec)`: the axis best aligned with the look
  /// direction and which way along it the player looks.
  Pair<Vec3, AxisDirection> getNearestTrackAxis(BlockGetter world, Pos pos, BState state, Vec3 lookVec) {
    Vec3? best;
    var bestDiff = double.maxFinite;
    for (final vec3 in getTrackAxes(world, pos, state)) {
      for (final opposite in Iterate.positiveAndNegative) {
        final distanceTo = vnorm(vec3).distanceTo(lookVec * opposite);
        if (distanceTo > bestDiff) continue;
        bestDiff = distanceTo;
        best = vec3;
      }
    }
    final b = best!;
    return Pair<Vec3, AxisDirection>(
      b,
      lookVec.dot(vnorm(vmul(b, 1, 0, 1))) < 0 ? AxisDirection.positive : AxisDirection.negative,
    );
  }

  TrackMaterial getMaterial();
}

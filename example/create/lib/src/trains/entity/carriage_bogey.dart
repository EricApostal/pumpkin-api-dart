// `CarriageBogey` (pure): one bogey of a carriage with its two wheel points. The client side
// animation state of Java (wheel angle, yaw / pitch lerps, coupling anchors) is not kept: the
// real client computes it from the synced wheel locations.
import '../../common/data.dart';
import '../../common/vec_helper.dart';
import '../bogey/abstract_bogey_block.dart';
import '../bogey/bogey_sizes.dart';
import '../bogey/bogey_style.dart';
import '../graph/dimension_palette.dart';
import '../graph/track_graph.dart';
import '../manager/create.dart';
import '../util/ctag.dart';
import 'carriage.dart';
import 'travelling_point.dart';

class CarriageBogey {
  /// `AbstractBogeyBlockEntity.BOGEY_DATA_KEY` / `BOGEY_STYLE_KEY` and `UPSIDE_DOWN_KEY`.
  static const String BOGEY_DATA_KEY = 'BogeyData';
  static const String BOGEY_STYLE_KEY = 'BogeyStyle';
  static const String UPSIDE_DOWN_KEY = 'UpsideDown';

  Carriage? carriage;
  bool isLeading = false;

  CTag bogeyData;

  final AbstractBogeyBlock type;
  bool upsideDown;
  final Couple<TravellingPoint> points;

  /// Client only in Java; kept so that code written against the Java names compiles.
  Couple<Vec3?> couplingAnchors = Couple.create<Vec3?>(null, null);

  int derailAngle = Create.RANDOM.nextInt(60) - 30;

  CarriageBogey(AbstractBogeyBlock type, bool upsideDown, CTag? bogeyData, [TravellingPoint? point, TravellingPoint? point2])
    : this._(type, upsideDown, bogeyData, point ?? TravellingPoint(), point2 ?? TravellingPoint());

  CarriageBogey._(this.type, bool upsideDown, CTag? bogeyData, TravellingPoint point, TravellingPoint point2)
    : upsideDown = type.canBeUpsideDown() && upsideDown,
      bogeyData = bogeyData ?? CTag(),
      points = Couple.create(point, point2) {
    point.upsideDown = this.upsideDown;
    point2.upsideDown = this.upsideDown;
    if (bogeyData == null || bogeyData.isEmpty) this.bogeyData = createBogeyData(); // Prevent Crash When Updating
    this.bogeyData.putBoolean(UPSIDE_DOWN_KEY, upsideDown);
  }

  /// `getDimension()`: the dimension both wheels are in, `null` when unknown or in different ones.
  String? getDimension() {
    final leading = this.leading();
    final trailing = this.trailing();
    if (leading.edge == null || trailing.edge == null) return null;
    if (leading.edge!.isInterDimensional() || trailing.edge!.isInterDimensional()) return null;
    final dimension1 = leading.node1!.getLocation().dimension;
    final dimension2 = trailing.node1!.getLocation().dimension;
    if (dimension1 == dimension2) return dimension1;
    return null;
  }

  TravellingPoint leading() {
    final point = points.getFirst();
    point.upsideDown = isUpsideDown();
    return point;
  }

  TravellingPoint trailing() {
    final point = points.getSecond();
    point.upsideDown = isUpsideDown();
    return point;
  }

  double getStress() {
    if (getDimension() == null) return 0;
    final train = carriage!.train!;
    if (train.derailed) return 0;
    return type.getWheelPointSpacing() - leading().getPosition(train.graph).distanceTo(trailing().getPosition(train.graph));
  }

  Vec3? getAnchorPosition([bool flipUpsideDown = false]) {
    if (leading().edge == null) return null;
    final graph = carriage!.train!.graph;
    return (points.getFirst().getPosition(graph, flipUpsideDown) + points.getSecond().getPosition(graph, flipUpsideDown)) *
        0.5;
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    tag.putString('Type', type.key);
    tag.putCompoundList('Points', [points.getFirst().write(dimensions), points.getSecond().write(dimensions)]);
    tag.putBoolean('UpsideDown', upsideDown);
    bogeyData.putBoolean(UPSIDE_DOWN_KEY, upsideDown);
    bogeyData.putString(BOGEY_STYLE_KEY, getStyle().id);
    tag.putCompound(BOGEY_DATA_KEY, bogeyData);
    return tag;
  }

  static CarriageBogey read(CTag tag, TrackGraph? graph, DimensionPalette dimensions) {
    final location = tag.getString('Type');
    final type = AbstractBogeyBlock.byKey(location);
    if (type == null) throw StateError('Unknown bogey block `$location`');
    final upsideDown = tag.getBoolean('UpsideDown');
    final pointTags = tag.getCompoundList('Points');
    final first = TravellingPoint.read(pointTags.isNotEmpty ? pointTags[0] : CTag(), graph, dimensions);
    final second = TravellingPoint.read(pointTags.length > 1 ? pointTags[1] : CTag(), graph, dimensions);
    final data = tag.getCompound(BOGEY_DATA_KEY);
    return CarriageBogey(type, upsideDown, data, first, second);
  }

  BogeyStyle getStyle() {
    final location = bogeyData.getString(BOGEY_STYLE_KEY);
    final style = AllBogeyStyles.get(location);
    return style ?? AllBogeyStyles.standard; // just for safety
  }

  BogeySize getSize() => type.getSize();

  CTag createBogeyData() {
    final style = type.getDefaultStyle();
    final nbt = style.defaultData.copy();
    nbt.putString(BOGEY_STYLE_KEY, style.id);
    nbt.putBoolean(UPSIDE_DOWN_KEY, isUpsideDown());
    return nbt;
  }

  void setLeading() {
    isLeading = true;
  }

  bool isUpsideDown() => type.canBeUpsideDown() && upsideDown;
}

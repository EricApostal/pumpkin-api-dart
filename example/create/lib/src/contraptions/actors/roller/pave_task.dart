// `PaveTask`: the height profile a roller fills when it drives along a track.
import '../../../common/common.dart';

/// `PaveTask`.
final class PaveTask {
  Couple<double> horizontalInterval;
  final Map<(int, int), double> heightValues = {};

  PaveTask(double h1, double h2) : horizontalInterval = Couple(h1, h2);

  Couple<double> getHorizontalInterval() => horizontalInterval;

  void put(int x, int z, double y) => heightValues[(x, z)] = y;

  void putPos(Pos p) => put(p.$1, p.$3, p.$2.toDouble());

  double? get((int, int) coords) => heightValues[coords];

  Iterable<(int, int)> keys() => heightValues.keys;
}

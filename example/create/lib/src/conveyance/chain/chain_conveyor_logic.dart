// The geometry and package model of chain conveyors (pure): `ChainConveyorBlockEntity`'s
// connection stats, the packages riding a chain, and the connection validation of
// `ChainConveyorConnectionHandler.validateAndConnect`. Ported from
// `content/kinetics/chainConveyor/ChainConveyorBlockEntity.java` and
// `ChainConveyorConnectionHandler.java`.
import 'dart:math' as math;

import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../contraptions/core/nbt_map.dart';
import '../../contraptions/core/structure_transform.dart';
import '../../core/nbt.dart' show NbtKind, NbtValue;
import '../items/item_data.dart';

/// `ChainConveyorBlockEntity.ConnectionStats`.
final class ConnectionStats {
  /// The angle (degrees) at which the chain leaves the conveyor.
  final double tangentAngle;
  final double chainLength;
  final Vec3 start;
  final Vec3 end;

  const ConnectionStats(
    this.tangentAngle,
    this.chainLength,
    this.start,
    this.end,
  );
}

/// `ChainConveyorBlockEntity.ConnectedPort`: a package port (frogport) attached to the chain.
final class ConnectedPort {
  final double chainPosition;

  /// The connection the port sits on, `null` when it sits on the loop.
  final Pos? connection;

  /// The address filter of the port (`*` matches everything).
  final String filter;

  const ConnectedPort(this.chainPosition, this.connection, this.filter);
}

/// `ChainConveyorPackage`: one package on a chain. [chainPosition] is the distance along a
/// travel chain or the angle around the loop.
class ChainConveyorPackage {
  double chainPosition;
  ItemValue item;

  /// `netId`: the server-unique id the client tracks the package by.
  final int netId;
  bool justFlipped = false;

  /// The world position of the package (updated by the block entity).
  Vec3? worldPosition;
  double yaw = 0;

  ChainConveyorPackage(this.chainPosition, this.item, this.netId);

  /// `write` / `writeToClient`: the saved form of a package.
  static int _nextNetId = 0;

  /// `netIdGenerator.incrementAndGet()`.
  static int nextNetId() => ++_nextNetId;
}

/// `ChainConveyorBlockEntity.wrapAngle`.
double wrapAngle(double angle) {
  angle %= 360;
  if (angle < 0) angle += 360;
  return angle;
}

/// `ChainConveyorBlockEntity.getChainCost`: the iron chains a connection costs.
int getChainCost(Pos connection) {
  final length = math.sqrt(
    connection.x * connection.x +
        connection.y * connection.y +
        connection.z * connection.z,
  );
  return math.max((length / 2.5).round(), 1);
}

/// `ChainConveyorBlockEntity.calculateConnectionStats`.
ConnectionStats calculateConnectionStats(
  Pos worldPos,
  Pos connection, {
  required bool reversed,
}) {
  const offBranchDistance = 35.0;
  final direction =
      180 /
      math.pi *
      math.atan2(connection.x.toDouble(), connection.z.toDouble());
  final angle = wrapAngle(direction - offBranchDistance * (reversed ? -1 : 1));
  final oppositeAngle = wrapAngle(
    angle + 180 + 2 * offBranchDistance * (reversed ? -1 : 1),
  );

  final start =
      worldPos.bottomCenter +
      VecHelper.rotate((0.0, 0.0, 1.25), angle, Axis.y) +
      (0.0, 6 / 16, 0.0);
  final end =
      (worldPos + connection).bottomCenter +
      VecHelper.rotate((0.0, 0.0, 1.25), oppositeAngle, Axis.y) +
      (0.0, 6 / 16, 0.0);
  final length = (start - end).length;
  return ConnectionStats(angle, length, start, end);
}

/// `ChainConveyorBlockEntity.calculateConnectionStats(BlockPos)`: computes the stats of one
/// connection and stores them in [stats]. The direction comes from the current [speed], not from
/// the cached `reversed` field.
void putConnectionStats(
  Map<Pos, ConnectionStats> stats,
  Pos worldPos,
  Pos connection,
  double speed,
) => stats[connection] = calculateConnectionStats(
  worldPos,
  connection,
  reversed: speed < 0,
);

/// `ChainConveyorBlockEntity.getPackagePosition`.
Vec3 chainPackagePosition(
  Pos worldPos,
  double chainPosition,
  Pos? travelTarget,
  Map<Pos, ConnectionStats> stats,
) {
  if (travelTarget == null) {
    return worldPos.bottomCenter +
        VecHelper.rotate((0.0, 6 / 16, 0.875), chainPosition, Axis.y);
  }
  final s = stats[travelTarget];
  if (s == null) return (0.0, 0.0, 0.0);
  final diff = (s.end - s.start).normalized;
  return s.start + diff * math.min(s.chainLength, chainPosition);
}

/// `ChainConveyorBlockEntity.loopThresholdCrossed`.
bool loopThresholdCrossed(
  double chainPosition,
  double prevChainPosition,
  double offBranchAngle, {
  required bool reversed,
}) {
  final sign1 = AngleHelper.getShortestAngleDiff(
    offBranchAngle,
    prevChainPosition,
  ).sign;
  final sign2 = AngleHelper.getShortestAngleDiff(
    offBranchAngle,
    chainPosition,
  ).sign;
  final notCrossed = sign1 >= sign2 && !reversed || sign1 <= sign2 && reversed;
  return !notCrossed;
}

/// Why `validateAndConnect` refused a connection (the `chain_conveyor.*` message key), or `null`
/// when the geometry is valid. The inventory / creative checks stay in the host handler.
String? validateConnectionGeometry(
  Pos first,
  Pos target, {
  required int maxLength,
}) {
  if (target == first) return 'chain_conveyor.cannot_connect_to_self';
  if (!target.closerThan(first, maxLength.toDouble()))
    return 'chain_conveyor.too_far';
  if (target.closerThan(first, 2.5)) return 'chain_conveyor.too_close';

  final diff = target - first;
  final horizontal = math.sqrt(diff.x * diff.x + diff.z * diff.z) - 1.5;
  if (horizontal <= 0) return 'chain_conveyor.cannot_connect_vertically';
  if (diff.y.abs() / horizontal > 1) return 'chain_conveyor.too_steep';
  return null;
}

/// `ChainConveyorBlockEntity.forPointsAlongChains`: calls [callback] with evenly spaced points on
/// the two chain halves, `false` when the connection has no stats.
bool forPointsAlongChains(
  Pos worldPos,
  Pos connection,
  int positions,
  Map<Pos, ConnectionStats> stats,
  void Function(Vec3 point) callback,
) {
  final s = stats[connection];
  if (s == null) return false;

  final start = s.start;
  final direction = s.end - start;
  final origin = worldPos.center;
  final normal = direction.cross((0.0, 1.0, 0.0)).normalized;
  final offset = start - origin;
  final start2 = origin + (offset + normal * (-2 * normal.dot(offset)));

  for (final firstChain in [true, false]) {
    var steps = positions ~/ 2;
    if (firstChain) steps += positions % 2;
    if (steps <= 0) continue;
    for (var i = 0; i < steps; i++) {
      callback((firstChain ? start : start2) + direction * ((0.5 + i) / steps));
    }
  }
  return true;
}

/// `ChainConveyorBlockEntity.transform` (`TransformableBlockEntity`): the connections and the
/// targets of the travelling packages follow a contraption that rotates or mirrors the conveyor.
/// The connection stats are rebuilt from the transformed offsets when the data is read back.
void transformChainConveyorNbt(NbtMap nbt, StructureTransform transform) {
  final connections = nbt.getList('Connections');
  if (connections.isEmpty) return;

  nbt.putList('Connections', [
    for (final c in connections) NbtValue.intArray(_transformedPos(c, transform)),
  ]);
  for (final entry in nbt.getList('TravellingPackages')) {
    if (entry.kind != NbtKind.compound) continue;
    final packages = NbtMap.of(entry);
    packages.putBlockPos(
      'Target',
      transform.applyPosWithoutOffset(packages.getBlockPos('Target')),
    );
  }
}

/// One `Connections` entry (an int array of three) transformed by [transform].
List<int> _transformedPos(NbtValue value, StructureTransform transform) {
  if (value.kind != NbtKind.intArray) return const [0, 0, 0];
  final array = value.value as List<int>;
  if (array.length < 3) return const [0, 0, 0];
  final p = transform.applyPosWithoutOffset((array[0], array[1], array[2]));
  return [p.$1, p.$2, p.$3];
}

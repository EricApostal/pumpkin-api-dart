// The small redstone blocks as pure functions: the rose quartz lamp cluster search and
// its output towards a reader, the redstone contact's pairing rule, and the analog
// lever's state helpers.
import '../common/common.dart';

/// `RoseQuartzLampBlock.forEachInCluster`: breadth first over the six neighbours,
/// at most 16 blocks (manhattan) from [start], visiting every lamp but [start] itself,
/// in the Java order (the frontier is a queue).
List<Pos> roseQuartzCluster(Pos start, bool Function(Pos) isLamp) {
  final frontier = <Pos>[start];
  final visited = <Pos>{start};
  final found = <Pos>[];
  while (frontier.isNotEmpty) {
    final pos = frontier.removeAt(0);
    for (final d in Direction.values) {
      final current = pos.relative(d);
      if (current.distManhattan(start) > 16) continue;
      if (!visited.add(current)) continue;
      if (!isLamp(current)) continue;
      found.add(current);
      frontier.add(current);
    }
  }
  return found;
}

/// `RoseQuartzLampBlock.getDistanceToPowered`: walking from [pos] along [column] through
/// lamps, the power (15 down to 1) of the first powering lamp, else 0.
int roseQuartzDistanceToPowered(Pos pos, Direction column, bool Function(Pos) isLamp, bool Function(Pos) isPowering) {
  var current = pos;
  for (var power = 15; power > 0; power--) {
    if (!isLamp(current)) return 0;
    if (isPowering(current)) return power;
    current = current.relative(column);
  }
  return 0;
}

/// What the lamp at some position is like as a reader sees it.
enum LampReader { lamp, comparator, other }

/// `RoseQuartzLampBlock.getSignal`: [side] is the vanilla `side` (reader to lamp).
/// [readerKind] describes the block on the reader's side.
int roseQuartzSignal({
  required Pos pos,
  required Direction side,
  required bool powering,
  required LampReader readerKind,
  required bool Function(Pos) isLamp,
  required bool Function(Pos) isPowering,
}) {
  switch (readerKind) {
    case LampReader.lamp:
      return 0;
    case LampReader.comparator:
      return roseQuartzDistanceToPowered(pos, side, isLamp, isPowering);
    case LampReader.other:
      return powering ? 15 : 0;
  }
}

/// `RoseQuartzLampBlock.neighborChanged` as a decision: what to do when the lamp at a
/// position with [powered] sees [neighbourSignal].
enum LampAction { nothing, switchOff, activate }

LampAction roseQuartzOnNeighborChanged({required bool powered, required bool neighbourSignal}) {
  if (powered == neighbourSignal) return LampAction.nothing;
  if (powered) return LampAction.switchOff;
  return LampAction.activate;
}

/// `RoseQuartzLampBlock.tick`: the properties after a scheduled tick, `null` when nothing
/// changes ([activate] is `ACTIVATE`, [powering] `POWERING`).
({bool activate, bool powering})? roseQuartzTick({required bool activate, required bool powering}) {
  if (powering || activate) return (activate: false, powering: activate);
  return null;
}

/// `RedstoneContactBlock.hasValidContact`: the block at `pos.relative(direction)` is a
/// contact (redstone or elevator) whose facing is [direction] opposite.
bool hasValidContact(String? neighbourKey, Direction? neighbourFacing, Direction direction) {
  if (neighbourKey != 'create:redstone_contact' && neighbourKey != 'create:elevator_contact') return false;
  return neighbourFacing == direction.opposite;
}

/// The redstone contact's `getSignal`: [side] is the vanilla `side`.
int redstoneContactSignal({required bool powered, required Direction facing, required Direction side}) =>
    powered && side != facing.opposite ? 15 : 0;

/// `shouldRedstoneWireConnectTo` of the redstone contact.
bool redstoneContactConnects({required Direction facing, required Direction? side}) =>
    side != null && facing != side.opposite;

/// `AnalogLeverBlockEntity.changeState`: the new state and whether the output timer restarts.
({int state, bool changed}) analogLeverStep(int state, {required bool back}) {
  final next = (state + (back ? -1 : 1)).clamp(0, 15);
  return (state: next, changed: next != state);
}

/// The pitch of the analog lever's click: `.25 + ((state + 5) / 15) * .5`.
double analogLeverPitch(int state) => 0.25 + ((state + 5) / 15) * 0.5;

/// `AnalogLeverBlock.getDirectSignal`: the state towards the connected direction only.
int analogLeverDirectSignal(int state, Direction connected, Direction side) => connected == side ? state : 0;

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`.
Direction analogLeverConnected(String face, Direction facing) => switch (face) {
  'ceiling' => Direction.down,
  'floor' => Direction.up,
  _ => facing,
};

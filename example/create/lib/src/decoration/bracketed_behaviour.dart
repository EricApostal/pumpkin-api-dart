// `BracketedBlockEntityBehaviour` and the registry of things a bracket can hold.
//
// Kinetics and fluids add the behaviour to the block entities of shafts, cogwheels and pipes:
//
// ```dart
// addBehaviour(BracketedBlockEntityBehaviour(canHave: (state) => state.key == 'create:shaft'));
// ```
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/direction.dart';
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import 'bracket.dart';
import 'bracket.dart' as bracket_;

/// The bracket stored in the block entity of a shaft, cogwheel or pipe.
final class BracketedBlockEntityBehaviour extends BlockEntityBehaviour {
  static const String typeId = 'bracketed';

  @override
  String get id => typeId;

  /// `Predicate<BlockState> pred`: whether the owner's current block state can carry a bracket.
  final bool Function(BState state) canHave;

  BState? _bracket;
  bool _reRender = false;

  BracketedBlockEntityBehaviour({this.canHave = _always});

  static bool _always(BState _) => true;

  /// The behaviour of the block entity at [pos], or `null`.
  static BracketedBlockEntityBehaviour? at(BlockEntityStore store, String worldId, Pos pos) =>
      store.at(worldId, pos.toBlockPos())?.getBehaviour<BracketedBlockEntityBehaviour>();

  bool get isBracketPresent => _bracket != null;

  /// `getBracket()`.
  BState? get bracket => _bracket;

  /// `isBracketValid`: the stored state must be a bracket block.
  bool isBracketValid(BState state) => state.key == woodenBracketKey || state.key == metalBracketKey;

  /// `canHaveBracket()`: asks the predicate with the owner's block state.
  bool canHaveBracket() {
    final world = owner.world;
    if (world == null) return false;
    return canHave(HostBlockGetter(world).stateAt(owner.pos.toPos()));
  }

  /// `applyBracket`: stores the bracket, sends it to the clients and updates the neighbour shapes
  /// (girders connect to brackets).
  Future<void> applyBracket(BState state) async {
    _bracket = state;
    _reRender = true;
    owner.sendData();
    final world = owner.world;
    if (world != null) await world.updateShapeAround(pos: owner.pos);
  }

  /// `removeBracket(inOnReplacedContext)`: removes and returns the bracket.
  Future<BState?> removeBracket({bool inOnReplacedContext = false}) async {
    final removed = _bracket;
    if (removed == null) return null;
    _bracket = null;
    _reRender = true;
    owner.sendData();
    if (inOnReplacedContext) return removed;
    final world = owner.world;
    if (world != null) await world.updateShapeAround(pos: owner.pos);
    return removed;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final b = _bracket;
    if (b != null && isBracketValid(b)) {
      final c = NbtCompound()..putString('Name', b.key);
      if (b.props.isNotEmpty) {
        final p = NbtCompound();
        b.props.forEach(p.putString);
        c.putCompound('Properties', p);
      }
      tag.putCompound('Bracket', c);
    }
    if (clientPacket && _reRender) {
      tag.putCompound('Redraw', NbtCompound());
      _reRender = false;
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final c = tag.getCompound('Bracket');
    if (c != null) {
      _bracket = null;
      final name = c.getString('Name');
      if (name != null) {
        final props = <String, String>{};
        final p = c.getCompound('Properties');
        if (p != null) {
          for (final k in p.keys) {
            final v = p.getString(k);
            if (v != null) props[k] = v;
          }
        }
        final s = BState(name, props);
        if (isBracketValid(s)) _bracket = s;
      }
    }
  }
}

/// What a bracket attaches to: kinetics and fluids register their blocks here; shafts, cogwheels
/// and the pipes of the fluids module are known by default.
final class BracketRegistry {
  final Map<String, BracketTarget Function(BState state)> _targets = {};

  BracketRegistry() {
    BracketTarget axisTarget(BState s, BracketType t) => BracketTarget(s.axisOf('axis'), t);
    _targets['create:shaft'] = (s) => axisTarget(s, BracketType.shaft);
    _targets['create:cogwheel'] = (s) => axisTarget(s, BracketType.cog);
    _targets['create:large_cogwheel'] = (s) => axisTarget(s, BracketType.cog);
    _targets['create:glass_fluid_pipe'] = (s) => axisTarget(s, BracketType.pipe);
    _targets['create:mechanical_pump'] =
        (s) => BracketTarget(s.dir('facing')?.axis, BracketType.pipe);
    _targets['create:fluid_pipe'] = (s) => BracketTarget(straightPipeAxis(s), BracketType.pipe);
  }

  /// Registers (or replaces) how a block is bracketed.
  void addTarget(String blockKey, BracketTarget Function(BState state) resolve) => _targets[blockKey] = resolve;

  /// The target description of [state], or `null` if brackets do not fit it.
  BracketTarget? resolve(BState state) => _targets[state.key]?.call(state);

  /// `BracketBlock.getSuitableBracket(blockState, direction)`.
  BState? suitableBracket(BState bracketDefault, BState blockState, Direction direction) {
    final t = resolve(blockState);
    if (t == null) return null;
    return bracket_.suitableBracket(bracketDefault, t.axis, direction, t.type);
  }
}

/// `FluidPropagator.getStraightPipeAxis` for `create:fluid_pipe`: the axis of a pipe that has
/// exactly one pair of opposite connections.
Axis? straightPipeAxis(BState state) {
  Axis? found;
  var connections = 0;
  for (final axis in Axis.values) {
    final open1 = state.flag(Direction.fromAxisAndDirection(axis, AxisDirection.negative).serializedName);
    final open2 = state.flag(Direction.fromAxisAndDirection(axis, AxisDirection.positive).serializedName);
    if (open1) connections++;
    if (open2) connections++;
    if (open1 && open2) {
      if (found != null) return null;
      found = axis;
    }
  }
  return connections == 2 ? found : null;
}

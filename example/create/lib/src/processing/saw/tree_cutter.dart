// `TreeCutter` (pure): the tree the mechanical saw fells in one go. Ported from
// `content/kinetics/saw/TreeCutter.java`; the world is a pair of callbacks so the search runs in
// `dart test`. Dynamic trees (the Dynamictrees compat) do not exist in this fork.
import '../../api/block_state.dart';
import '../../common/direction.dart';
import '../../common/pos.dart' hide pos;

/// Reads the state at a position (`BlockGetter.getBlockState`).
typedef StateAt = BState Function(Pos pos);

/// `BlockState.is(TagKey)`.
typedef StateHasTag = bool Function(BState state, String tag);

/// `AbstractBlockBreakQueue` of the saw: what one cut destroys.
final class CutTree {
  final List<Pos> logs;
  final List<Pos> leaves;
  final List<Pos> attachments;

  const CutTree(this.logs, this.leaves, this.attachments);

  static const CutTree none = CutTree([], [], []);

  bool get isEmpty => logs.isEmpty && leaves.isEmpty && attachments.isEmpty;

  /// `destroyBlocks`: attachments first, then logs, then leaves (the order keeps hanging
  /// blocks from breaking on their own).
  void destroyBlocks(void Function(Pos pos) drop) {
    for (final p in attachments) {
      drop(p);
    }
    for (final p in logs) {
      drop(p);
    }
    for (final p in leaves) {
      drop(p);
    }
  }
}

/// `TreeCutter.isRoot`.
bool isRoot(BState state, StateHasTag hasTag) => hasTag(state, 'create:roots');

/// `TreeCutter.isLog`: the logs tag, the slimy logs of the honey compat and mushroom stems.
bool isLog(BState state, StateHasTag hasTag) =>
    hasTag(state, 'minecraft:logs') ||
    hasTag(state, 'create:slimy_logs') ||
    state.key == 'minecraft:mushroom_stem';

/// `TreeCutter.isVerticalPlant`: bamboo, cactus, sugar cane, kelp.
bool isVerticalPlant(BState state) => switch (state.key) {
  'minecraft:bamboo' ||
  'minecraft:cactus' ||
  'minecraft:sugar_cane' ||
  'minecraft:kelp' ||
  'minecraft:kelp_plant' => true,
  _ => false,
};

/// `TreeCutter.isChorus`.
bool isChorus(BState state) =>
    state.key == 'minecraft:chorus_plant' ||
    state.key == 'minecraft:chorus_flower';

/// `TreeCutter.isSawable`: the blocks the saw may break at all.
bool isSawable(BState state, StateHasTag hasTag) {
  if (hasTag(state, 'minecraft:saplings')) return false;
  if (isLog(state, hasTag) || hasTag(state, 'minecraft:leaves')) return true;
  if (isRoot(state, hasTag)) return true;
  if (isVerticalPlant(state)) return true;
  if (hasTag(state, 'create:solid_crops')) return true;
  if (isChorus(state)) return true;
  return false;
}

/// `TreeCutter.findTree`: the logs, leaves and attachments of the tree cut at [pos].
///
/// [height] is `level.getHeight()`; [pos] is the position the saw cut into (the block there is
/// gone already), [brokenState] the state that was broken.
CutTree findTree({
  required StateAt stateAt,
  required StateHasTag hasTag,
  required int height,
  required Pos pos,
  required BState brokenState,
}) {
  final logs = <Pos>[];
  final leaves = <Pos>[];
  final attachments = <Pos>[];
  final visited = <Pos>{};
  final frontier = <Pos>[];

  final stateAbove = stateAt(pos.above);

  // Bamboo, sugar cane, cactus and kelp: the column above.
  if (isVerticalPlant(brokenState)) {
    if (!isVerticalPlant(stateAbove)) return CutTree.none;
    logs.add(pos.above);
    for (var i = 1; i < height; i++) {
      final current = pos.aboveBy(i);
      if (!isVerticalPlant(stateAt(current))) break;
      logs.add(current);
    }
    return CutTree(logs.reversed.toList(), leaves, attachments);
  }

  // Chorus: everything connected above.
  if (isChorus(brokenState)) {
    if (!isChorus(stateAbove)) return CutTree.none;
    frontier.add(pos.above);
    while (frontier.isNotEmpty) {
      final current = frontier.removeAt(0);
      if (!visited.add(current)) continue;
      logs.add(current);
      for (final d in Direction.values) {
        final offset = current.relative(d);
        if (visited.contains(offset) || !isChorus(stateAt(offset))) continue;
        frontier.add(offset);
      }
    }
    return CutTree(logs.reversed.toList(), leaves, attachments);
  }

  // A regular tree.
  if (!_validateCut(stateAt, hasTag, pos)) return CutTree.none;

  visited.add(pos);
  frontier.addAll(pos.offset(-1, 0, -1).boxTo(pos.offset(1, 1, 1)));

  var hasRoots = false;
  while (frontier.isNotEmpty) {
    final currentPos = frontier.removeAt(0);
    if (!visited.add(currentPos)) continue;
    final currentState = stateAt(currentPos);
    if (isRoot(currentState, hasTag)) {
      hasRoots = true;
    } else if (!isLog(currentState, hasTag)) {
      continue;
    }
    logs.add(currentPos);
    _forNeighbours(currentPos, visited, 0, 1, frontier.add);
  }

  visited
    ..clear()
    ..addAll(logs);
  frontier
    ..clear()
    ..addAll(logs);

  if (hasRoots) {
    final oldLogs = <Pos>{...logs};
    while (frontier.isNotEmpty) {
      final currentPos = frontier.removeAt(0);
      if (!isRoot(stateAt(currentPos), hasTag)) continue;
      if (!oldLogs.contains(currentPos)) logs.add(currentPos);
      _forNeighbours(currentPos, visited, -1, 0, (p) {
        if (visited.add(p)) frontier.add(p);
      });
    }
    visited
      ..clear()
      ..addAll(logs);
    frontier
      ..clear()
      ..addAll(logs);
  }

  // The leaves around the logs.
  while (frontier.isNotEmpty) {
    final prevPos = frontier.removeAt(0);
    final prevState = stateAt(prevPos);
    final prevLeafDistance = _isLeaf(prevState) ? _leafDistance(prevState) : 0;

    _forNeighbours(prevPos, visited, -1, 1, (currentPos) {
      final state = stateAt(currentPos);
      final subtract = currentPos - pos;

      if (hasTag(state, 'create:tree_attachments')) {
        attachments.add(currentPos);
        visited.add(currentPos);
        return;
      }

      final horizontalDistance = (subtract.x.abs() > subtract.z.abs()
          ? subtract.x.abs()
          : subtract.z.abs());
      if (horizontalDistance <= _nonDecayingLeafDistance(state, hasTag) &&
          visited.add(currentPos)) {
        leaves.add(currentPos);
        frontier.add(currentPos);
        return;
      }

      if (_isLeaf(state) &&
          _leafDistance(state) > prevLeafDistance &&
          visited.add(currentPos)) {
        leaves.add(currentPos);
        frontier.add(currentPos);
      }
    });
  }

  return CutTree(logs, leaves, attachments);
}

/// `TreeCutter.validateCut`: whether the layer above the cut is supported only by the cut itself.
bool _validateCut(StateAt stateAt, StateHasTag hasTag, Pos pos) {
  final visited = <Pos>{};
  final frontier = <Pos>[pos, pos.above];
  final posY = pos.y;

  while (frontier.isNotEmpty) {
    final currentPos = frontier.removeAt(0);
    final belowPos = currentPos.below;
    final lowerLayer = currentPos.y == posY;

    visited.add(currentPos);
    final currentState = stateAt(currentPos);
    final belowState = stateAt(belowPos);

    if (!isLog(currentState, hasTag) && !isRoot(currentState, hasTag)) continue;
    if (!lowerLayer &&
        pos != belowPos &&
        (isLog(belowState, hasTag) || isRoot(belowState, hasTag))) {
      return false;
    }

    for (final direction in Direction.values) {
      if (direction == Direction.down) continue;
      if (direction == Direction.up && !lowerLayer) continue;
      final offset = currentPos.relative(direction);
      if (visited.contains(offset)) continue;
      frontier.add(offset);
    }
  }

  return true;
}

/// `forNeighbours`: the box around [pos] from [minY] to [maxY], skipping visited positions.
void _forNeighbours(
  Pos pos,
  Set<Pos> visited,
  int minY,
  int maxY,
  void Function(Pos) accept,
) {
  for (final p in pos.offset(-1, minY, -1).boxTo(pos.offset(1, maxY, 1))) {
    if (!visited.contains(p)) accept(p);
  }
}

/// `TreeCutter.isLeaf`: a `distance` property (`LeavesBlock.DISTANCE`).
bool _isLeaf(BState state) => state.has('distance');

int _leafDistance(BState state) => state.intValue('distance');

/// `TreeCutter.nonDecayingLeafDistance`.
int _nonDecayingLeafDistance(BState state, StateHasTag hasTag) {
  if (state.key == 'minecraft:red_mushroom_block') return 2;
  if (state.key == 'minecraft:brown_mushroom_block') return 3;
  if (hasTag(state, 'minecraft:wart_blocks') ||
      state.key == 'minecraft:weeping_vines' ||
      state.key == 'minecraft:weeping_vines_plant') {
    return 3;
  }
  return -1;
}

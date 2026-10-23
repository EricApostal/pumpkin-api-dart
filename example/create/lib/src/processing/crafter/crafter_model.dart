// The pure logic of the mechanical crafter: the crafting grid (`GroupedItems`), the
// `Pointing` property, the connected input groups and the chain traversal of
// `RecipeGridHandler`. Ported from
// `content/kinetics/crafter/{MechanicalCrafterBlock,ConnectedInputHandler,RecipeGridHandler}.java`.
//
// Placement grouping: Java does not auto-connect on placement either — `getStateForPlacement`
// only copies facing/pointing from the neighbour so fronts line up, and `neighborChanged` only
// refreshes `InvManipulationBehaviour`, never `ConnectedInput` (confirmed on the Java reference
// arm, Create 6.0.11: a `fill`-placed 3x3 stays nine lone `Controller: 1b` inputs; the first
// ponder scene only shows green connection lines because it explicitly calls
// `connectCrafterInvs`, i.e. `toggleConnection`). So no placement/neighbour hook is missing
// relative to Java; the wrench-edge path in `crafter_block.dart` is the complete port. Crafters
// with aligned front/pointing still craft as one chain because `RecipeGridHandler` follows the
// pointing, not `ConnectedInput`.
//
// The chain functions take a [CrafterWorld] view so they run on the plain Dart VM; the block
// entity (`mechanical_crafter_block_entity.dart`) provides the host implementation.
import '../../api/block_state.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../conveyance/nbt_names.dart' show enumByNameIgnoreCase;
import '../common/stack.dart';

/// The key of the crafter block.
const String crafterBlockKey = 'create:mechanical_crafter';

/// `MechanicalCrafterBlock.POINTING`, in the property's value order.
enum CrafterPointing { up, left, down, right }

/// `Pointing.getXRotation()`: UP 0, LEFT 270, DOWN 180, RIGHT 90.
int crafterPointingXRotation(CrafterPointing pointing) => switch (pointing) {
  CrafterPointing.up => 0,
  CrafterPointing.left => 270,
  CrafterPointing.down => 180,
  CrafterPointing.right => 90,
};

/// `Pointing` by its serialized name.
CrafterPointing? crafterPointingByName(String? name) {
  for (final p in CrafterPointing.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// `MechanicalCrafterBlockEntity.Phase`.
enum CrafterPhase {
  idle,
  accepting,
  assembling,
  exporting,
  waiting,
  crafting,
  inserting;

  /// The name Java writes to NBT (`Phase`).
  String get javaName => name.toUpperCase();

  static CrafterPhase? fromJavaName(String? name) =>
      enumByNameIgnoreCase(name, values, nameOf: (p) => p.javaName);
}

/// `MechanicalCrafterBlock.pointingFromFacing`.
CrafterPointing pointingFromFacing(
  Direction pointingFace,
  Direction blockFacing,
) {
  final positive = blockFacing.axisDirection == AxisDirection.positive;

  var pointing = pointingFace == Direction.down
      ? CrafterPointing.up
      : CrafterPointing.down;
  if (pointingFace == Direction.east) {
    pointing = positive ? CrafterPointing.left : CrafterPointing.right;
  }
  if (pointingFace == Direction.west) {
    pointing = positive ? CrafterPointing.right : CrafterPointing.left;
  }
  if (pointingFace == Direction.north) {
    pointing = positive ? CrafterPointing.left : CrafterPointing.right;
  }
  if (pointingFace == Direction.south) {
    pointing = positive ? CrafterPointing.right : CrafterPointing.left;
  }
  return pointing;
}

/// `MechanicalCrafterBlock.getTargetDirection`: where a crafter sends its items.
Direction crafterTargetDirection(BState state) {
  if (state.key != crafterBlockKey) return Direction.up;
  final facing = state.dir('facing') ?? Direction.north;
  final pointing =
      crafterPointingByName(state['pointing']) ?? CrafterPointing.up;
  var target = (0.0, 1.0, 0.0);
  target = VecHelper.rotate(
    target,
    -crafterPointingXRotation(pointing).toDouble(),
    Axis.z,
  );
  target = VecHelper.rotate(
    target,
    AngleHelper.horizontalAngle(facing),
    Axis.y,
  );
  return Direction.nearest(target.$1, target.$2, target.$3);
}

/// `MechanicalCrafterBlock.isValidTarget`.
bool isValidCrafterTarget(
  CrafterWorld world,
  Pos targetPos,
  BState crafterState,
) {
  final targetState = world.stateAt(targetPos);
  if (!world.isLoaded(targetPos)) return false;
  if (targetState.key != crafterBlockKey) return false;
  if (crafterState['facing'] != targetState['facing']) return false;
  final a = crafterPointingByName(crafterState['pointing']);
  final b = crafterPointingByName(targetState['pointing']);
  if (a != null &&
      b != null &&
      (crafterPointingXRotation(a) - crafterPointingXRotation(b)).abs() ==
          180) {
    return false;
  }
  return true;
}

/// `RecipeGridHandler.GroupedItems`: the items a crafter holds, placed on an integer grid.
///
/// `x` grows to the right of the block's front face and `y` grows upwards, so the first row of
/// a crafting pattern is the one with the largest `y` (see `MechanicalCraftingInput.of`).
final class GroupedItems {
  /// The stacks by grid position; missing cells are empty.
  final Map<(int, int), PStack> grid;

  int minX = 0, minY = 0, maxX = 0, maxY = 0, width = 0, height = 0;
  bool statsReady = false;

  GroupedItems([Map<(int, int), PStack>? grid]) : grid = grid ?? {};

  /// `new GroupedItems(stack)`.
  GroupedItems.single(PStack stack) : grid = {(0, 0): stack};

  /// `mergeOnto`: moves this grid onto [other], shifted towards [pointing].
  void mergeOnto(GroupedItems other, CrafterPointing pointing) {
    final xOffset = pointing == CrafterPointing.left
        ? 1
        : pointing == CrafterPointing.right
        ? -1
        : 0;
    final yOffset = pointing == CrafterPointing.down
        ? 1
        : pointing == CrafterPointing.up
        ? -1
        : 0;
    grid.forEach((key, stack) {
      other.grid[(key.$1 + xOffset, key.$2 + yOffset)] = stack;
    });
    other.statsReady = false;
  }

  /// `calcStats`: the bounding box of the grid, always including the origin.
  void calcStats() {
    if (statsReady) return;
    statsReady = true;

    minX = 0;
    minY = 0;
    maxX = 0;
    maxY = 0;

    for (final key in grid.keys) {
      if (key.$1 < minX) minX = key.$1;
      if (key.$2 < minY) minY = key.$2;
      if (key.$1 > maxX) maxX = key.$1;
      if (key.$2 > maxY) maxY = key.$2;
    }

    width = maxX - minX + 1;
    height = maxY - minY + 1;
  }

  /// `onlyEmptyItems`.
  bool get onlyEmptyItems {
    for (final stack in grid.values) {
      if (stack.isNotEmpty) return false;
    }
    return true;
  }

  bool get isEmpty => grid.isEmpty || onlyEmptyItems;

  @override
  String toString() => 'GroupedItems(${grid.length} cells)';
}

/// `ConnectedInputHandler.ConnectedInput`: the crafters one input is shared between, as offsets
/// from the controller (`[posZero]` for a controller that is alone).
final class ConnectedInput {
  bool isController;
  List<Pos> data;

  ConnectedInput({this.isController = true, List<Pos>? data})
    : data = data ?? [posZero];

  /// `attachTo`: makes this a member of the controller at [controllerPos].
  void attachTo(Pos controllerPos, Pos myPos) {
    isController = false;
    data = [controllerPos - myPos];
  }

  /// The controller's position, seen from [myPos].
  Pos controllerOf(Pos myPos) => myPos + data.first;

  @override
  String toString() => 'ConnectedInput(controller: $isController, $data)';
}

/// What the chain logic needs of one crafter (`MechanicalCrafterBlockEntity`).
///
/// [crafterAt] must return the same instance for the same position while a chain is walked:
/// the traversal compares nodes by identity, like Java.
abstract interface class CrafterNode {
  Pos get crafterPos;

  BState get crafterState;

  ConnectedInput get input;

  CrafterPhase get phase;

  /// `craftingItemPresent`: slot 0 holds an item.
  bool get hasCraftingItem;

  /// `craftingItemOrCoverPresent`.
  bool get hasCraftingItemOrCover;

  /// `begin()`.
  void begin();

  /// `continueIfAllPrecedingFinished()`.
  void continueIfAllPrecedingFinished();

  /// `eject()`: drops the grid and the slot item.
  void eject();
}

/// The world lookups the chain logic needs.
abstract interface class CrafterWorld {
  BState stateAt(Pos pos);

  bool isLoaded(Pos pos);

  CrafterNode? crafterAt(Pos pos);
}

/// `RecipeGridHandler.getTargetingCrafter`.
CrafterNode? targetingCrafter(CrafterWorld world, CrafterNode crafter) {
  final state = crafter.crafterState;
  if (state.key != crafterBlockKey) return null;

  final targetPos = crafter.crafterPos.relative(crafterTargetDirection(state));
  final target = world.crafterAt(targetPos);
  if (target == null) return null;
  final targetState = target.crafterState;
  if (targetState.key != crafterBlockKey) return null;
  if (state['facing'] != targetState['facing']) return null;
  return target;
}

/// `RecipeGridHandler.getPrecedingCrafters`: the crafters that feed this one.
List<CrafterNode> precedingCrafters(CrafterWorld world, CrafterNode crafter) {
  final crafters = <CrafterNode>[];
  final state = crafter.crafterState;
  if (state.key != crafterBlockKey) return crafters;

  final blockFacing = state.dir('facing') ?? Direction.north;
  final blockPointing = crafterTargetDirection(state);
  for (final facing in Direction.values) {
    if (blockFacing.axis == facing.axis) continue;
    if (blockPointing == facing) continue;

    final neighbourPos = crafter.crafterPos.relative(facing);
    final neighbourState = world.stateAt(neighbourPos);
    if (neighbourState.key != crafterBlockKey) continue;
    if (crafterTargetDirection(neighbourState) != facing.opposite) continue;
    if (blockFacing != neighbourState.dir('facing')) continue;
    final be = world.crafterAt(neighbourPos);
    if (be == null) continue;

    crafters.add(be);
  }
  return crafters;
}

/// `RecipeGridHandler.getAllCraftersOfChainIf`: the whole connected group, `null` when it is
/// cyclic or (depending on [poweredStart]) does not hold any item.
List<CrafterNode>? allCraftersOfChainIf(
  CrafterWorld world,
  CrafterNode root,
  bool Function(CrafterNode) test, {
  bool poweredStart = false,
}) {
  final crafters = <CrafterNode>[];
  final frontier = <(CrafterNode, CrafterNode?)>[(root, null)];
  final visited = <CrafterNode>{};

  var empty = false;
  var allEmpty = true;

  while (frontier.isNotEmpty) {
    final (current, last) = frontier.removeAt(0);

    if (visited.contains(current)) return null;
    if (!test(current)) {
      empty = true;
    } else {
      allEmpty = false;
    }

    crafters.add(current);
    visited.add(current);

    final target = targetingCrafter(world, current);
    if (!identical(target, last) && target != null) {
      frontier.add((target, current));
    }
    for (final preceding in precedingCrafters(world, current)) {
      if (!identical(preceding, last)) frontier.add((preceding, current));
    }
  }

  return (empty && !poweredStart) || allEmpty ? null : crafters;
}

/// `RecipeGridHandler.getAllCraftersOfChain`.
List<CrafterNode>? allCraftersOfChain(CrafterWorld world, CrafterNode root) =>
    allCraftersOfChainIf(world, root, (_) => true);

/// `ConnectedInputHandler.shouldConnect`: whether the crafter at the block-entity position
/// recorded in [refState] (check its key) may join its neighbour in [direction].
///
/// Java's `shouldConnect(world, pos, face, direction)` reads the block state at `pos` and of
/// the neighbour at `pos + direction` (`ConnectedInputHandler.java:39-54`). Its only live
/// caller is the wrench edge interaction (`EdgeInteractionBehaviour`); placed grids never
/// auto-connect — verified on the Java reference arm (release Create 6.0.11): a `fill`-placed
/// 3x3 stays nine lone `Controller: 1b` inputs. Java's `getStateForPlacement` only copies the
/// neighbour's facing/pointing so the fronts line up; `neighborChanged` only refreshes the
/// *insertion* behaviour, never `ConnectedInput`.
///
/// The host has no edge interactions, so the port routes the connection through a wrench
/// clicking the side towards a compatible neighbour (see `crafter_block.dart`); the grouping
/// itself is identical to Java's.
bool shouldConnectCrafter(
  BState refState,
  BState neighbour,
  Direction direction,
) {
  if (refState.key != crafterBlockKey) return false;
  final refDirection = refState.dir('facing') ?? Direction.north;
  if (direction.axis == refDirection.axis) return false;
  if (neighbour.key != crafterBlockKey) return false;
  if (refDirection != neighbour.dir('facing')) return false;
  return true;
}

// The turtle's brain: its state (inventory, fuel, selected slot, colour,
// upgrades), the queue of commands the Lua `turtle` API issues, and the
// animation clock that paces them. Binding-free: the world is a
// [TurtleWorld] the plugin passes in.
//
// Mirrors `TurtleBrain` (shared/turtle/core, mc-26.3):
//
// * `executeCommand` queues a command (at most 16 waiting) and the program
//   waits for the `turtle_response` event with its id;
// * `update()` (once per server tick; asynchronous, the world calls of a
//   command finish later) runs the next command when no animation
//   is playing, answers it with `turtle_response (id, true, results...)` or
//   `(id, false, message)`, then advances the animation: every move, turn,
//   tool swing and item transfer plays an 8 tick animation during which no other
//   command runs, which is what limits a turtle to 2.5 actions a second;
// * the animation number is part of the client data, the client animates the
//   turtle from it.
import 'dart:async';
import 'dart:collection';

import 'direction.dart';
import 'stack.dart';
import 'upgrades.dart';
import 'world.dart';

/// The terminal of a turtle (`Config.TURTLE_TERM_WIDTH` / `TURTLE_TERM_HEIGHT`).
const int turtleTerminalWidth = 39;
const int turtleTerminalHeight = 13;

/// `TurtleAnimation` (the ordinal is what the client data carries).
enum TurtleAnimation {
  none,
  moveForward,
  moveBack,
  moveUp,
  moveDown,
  turnLeft,
  turnRight,
  swingLeftTool,
  swingRightTool,
  wait,
  shortWait,
}

/// The outcome of a command: `TurtleCommandResult`.
final class TurtleResult {
  final bool success;
  final String? message;

  /// The values after `true`: plain Dart values (num, bool, String, List,
  /// Map) the Lua layer converts.
  final List<Object?> values;

  const TurtleResult.ok([this.values = const []]) : success = true, message = null;

  const TurtleResult.fail([this.message]) : success = false, values = const [];
}

/// A command the turtle runs when its turn comes.
///
/// A command that touches the world is asynchronous: the host applies changes
/// later. [TurtleBrain.update] waits for it.
typedef TurtleCommand = FutureOr<TurtleResult> Function(TurtleBrain turtle, TurtleWorld world);

/// The server wide turtle settings (`Config`).
final class TurtleSettings {
  /// `turtlesNeedFuel`.
  final bool needsFuel;

  /// `TurtleBlockEntity.getFuelLimit` of normal and advanced turtles
  /// (`Config.turtleFuelLimit` 20000, `advancedTurtleFuelLimit` 100000).
  final int fuelLimit;
  final int advancedFuelLimit;

  const TurtleSettings({this.needsFuel = true, this.fuelLimit = 20000, this.advancedFuelLimit = 100000});
}

final class _Queued {
  final int id;
  final TurtleCommand command;

  const _Queued(this.id, this.command);
}

final class TurtleBrain {
  /// `TurtleBlockEntity.INVENTORY_SIZE`.
  static const int inventorySize = 16;

  /// `TurtleBrain.ANIM_DURATION`.
  static const int animationDuration = 8;

  /// The most commands waiting at once (`commandQueue.size() > 16` refuses).
  static const int maxQueued = 16;

  final bool advanced;
  final TurtleSettings settings;
  final TurtleUpgrades upgradeTable;
  final ItemInfo itemInfo;
  late final Slots inventory = Slots(inventorySize, itemInfo);

  /// Where the turtle stands: set by the plugin from its `ComputerLocation` (a world id,
  /// `World.getId()`, the folder name `world`), updated by moves. The initial value is the host's
  /// fallback world name, not a dimension key: `get_world_name` unwraps to `world`.
  String worldId = 'world';
  WorldPos pos = const WorldPos(0, 0, 0);
  Dir facing = Dir.north;

  /// The computer's id, once it has one.
  int? computerId;

  int selectedSlot = 0;
  int _fuel = 0;

  /// The dye colour (`0xRRGGBB`) or -1.
  int colour = -1;

  /// The overlay model (`computercraft:rainbow_flag`) or null.
  String? overlay;

  UpgradeInstance? _left;
  UpgradeInstance? _right;

  String? ownerUuid;
  String? ownerName;

  TurtleAnimation animation = TurtleAnimation.none;
  int animationProgress = 0;

  /// The computer's event queue (`ServerComputer.queueEvent`).
  void Function(String name, List<Object?> args)? queueEvent;

  /// Called when an upgrade was added, removed or replaced, so the peripherals
  /// of the computer can follow.
  void Function()? onUpgradesChanged;

  /// Called with a line for failures that point at the server and not at the
  /// program (a world that cannot be reached, a command that threw, a move the
  /// host refused).
  void Function(String message)? log;

  /// Set when the persisted state changed / the client data changed.
  bool saveDirty = false;
  bool clientDirty = false;

  final Queue<_Queued> _queue = Queue();
  int _issued = 0;

  /// Whether an [update] is still running (a command that waits for the host).
  bool _updating = false;
  List<TurtleStack?> _snapshot = List<TurtleStack?>.filled(inventorySize, null);

  TurtleBrain({
    required this.advanced,
    required this.settings,
    required this.upgradeTable,
    required this.itemInfo,
  });

  // -- Fuel ------------------------------------------------------------------

  int get fuelLimit => advanced ? settings.advancedFuelLimit : settings.fuelLimit;

  bool get isFuelNeeded => settings.needsFuel;

  int get fuelLevel => _fuel < fuelLimit ? _fuel : fuelLimit;

  set fuelLevel(int value) {
    final next = value < fuelLimit ? value : fuelLimit;
    if (next == _fuel) return;
    _fuel = next < 0 ? 0 : next;
    saveDirty = true;
    clientDirty = true;
  }

  /// `consumeFuel`: false if there is not enough.
  bool consumeFuel(int amount) {
    if (!isFuelNeeded) return true;
    final needed = amount < 0 ? 0 : amount;
    if (fuelLevel >= needed) {
      fuelLevel = fuelLevel - needed;
      return true;
    }
    return false;
  }

  void addFuel(int amount) => fuelLevel = fuelLevel + (amount < 0 ? 0 : amount);

  // -- Upgrades ----------------------------------------------------------------

  UpgradeInstance? upgradeOn(TurtleSide side) => side == TurtleSide.left ? _left : _right;

  /// Equips [upgrade] (null removes one) and tells the computer.
  void setUpgrade(TurtleSide side, UpgradeInstance? upgrade) {
    final current = upgradeOn(side);
    if (current == null && upgrade == null) return;
    if (side == TurtleSide.left) {
      _left = upgrade;
    } else {
      _right = upgrade;
    }
    saveDirty = true;
    clientDirty = true;
    onUpgradesChanged?.call();
  }

  /// Sets an upgrade when loading (no events).
  void setUpgradeDirect(TurtleSide side, UpgradeInstance? upgrade) {
    if (side == TurtleSide.left) {
      _left = upgrade;
    } else {
      _right = upgrade;
    }
  }

  // -- Animation -----------------------------------------------------------------

  /// `playAnimation`.
  void playAnimation(TurtleAnimation next) {
    animation = next;
    animationProgress = next == TurtleAnimation.shortWait ? animationDuration ~/ 2 : 0;
    clientDirty = true;
  }

  void _updateAnimation() {
    if (animation == TurtleAnimation.none) return;
    if (++animationProgress >= animationDuration) {
      animation = TurtleAnimation.none;
      animationProgress = 0;
    }
  }

  // -- Commands ------------------------------------------------------------------

  /// `executeCommand`: queues [command]. Returns its id, or null when too many
  /// commands wait (the program is told `false, "Too many ongoing turtle
  /// commands"`).
  int? enqueue(TurtleCommand command) {
    if (_queue.length > maxQueued) return null;
    final id = ++_issued;
    _queue.add(_Queued(id, command));
    return id;
  }

  /// How many commands wait.
  int get queued => _queue.length;

  /// Drops all waiting commands (the computer shut down).
  void clearQueue() => _queue.clear();

  /// One server tick: runs the next command if no animation plays, then
  /// advances the animation (the order of `TurtleBrain.update`). A call while
  /// the previous one still waits for its command does nothing, so a slow
  /// command never runs twice and the animation clock only advances once per
  /// finished update.
  Future<void> update(TurtleWorldProvider worldProvider) async {
    if (_updating) return;
    _updating = true;
    try {
      await _update(worldProvider);
    } finally {
      _updating = false;
    }
  }

  Future<void> _update(TurtleWorldProvider worldProvider) async {
    if (animation == TurtleAnimation.none && _queue.isNotEmpty) {
      final next = _queue.removeFirst();
      TurtleResult result;
      final world = worldProvider();
      if (world == null) {
        log?.call('the world $worldId cannot be reached');
        result = const TurtleResult.fail('Cannot reach the world');
      } else {
        try {
          result = await next.command(this, world);
        } catch (e) {
          log?.call('a command threw: $e');
          result = TurtleResult.fail('Turtle command failed: $e');
        }
        if (!result.success && result.message == 'Movement failed') {
          log?.call('the host refused to move the turtle from $pos');
        }
      }
      final send = queueEvent;
      if (send != null) {
        if (result.success) {
          send('turtle_response', [next.id.toDouble(), true, ...result.values]);
        } else {
          send('turtle_response', [next.id.toDouble(), false, result.message]);
        }
      }
    }
    _updateAnimation();
    _checkInventory();
  }

  /// `TurtleBlockEntity.setChanged`: queues `turtle_inventory` when a slot
  /// changed since the last tick.
  void _checkInventory() {
    var changed = false;
    for (var i = 0; i < inventorySize; i++) {
      if (!sameSlot(inventory[i], _snapshot[i])) {
        changed = true;
        _snapshot[i] = inventory[i]?.copy();
      }
    }
    if (changed) {
      saveDirty = true;
      queueEvent?.call('turtle_inventory', const []);
    }
  }

  /// Marks the inventory as already known (after loading), so no event fires.
  void resetSnapshot() => _snapshot = [for (final stack in inventory.items) stack?.copy()];

  // -- Selected slot ---------------------------------------------------------------

  void selectSlot(int slot) {
    if (slot >= 0 && slot < inventorySize && slot != selectedSlot) {
      selectedSlot = slot;
      saveDirty = true;
    }
  }

  /// `TurtleUtil.storeItemOrDrop`: puts [stack] in the inventory starting at
  /// the selected slot. Returns what did not fit (the host cannot drop items
  /// into the world, see docs/host-requirements.md).
  TurtleStack? storeItems(TurtleStack stack) {
    final remainder = inventory.storeFromOffset(stack, selectedSlot);
    saveDirty = true;
    return remainder;
  }
}

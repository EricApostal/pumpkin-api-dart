// The `turtle` API of CC: Tweaked (`TurtleAPI`, shared/turtle/apis, mc-26.3).
//
// In CC every action is a `MethodResult.pullEvent("turtle_response", ...)`: the
// call queues a command on the brain and the Lua thread yields until the brain
// answers with a `turtle_response` event carrying the command's id. A native
// function here cannot yield, so the API is a small Lua layer over native
// functions: `native.queue(name, ...)` validates the arguments and queues the
// command, the Lua wrapper then yields on `turtle_response` until its own id
// comes back (`terminate` ends the wait with the error `Terminated`, like in
// CC). The functions that only read (`getFuelLevel`, `getItemCount`, ...)
// are plain natives.
//
// `rom/apis/turtle/turtle.lua` (loaded by `bios.lua` when `turtle` exists) adds
// `turtle.craft` for a crafting table upgrade and wraps `equipLeft/Right`.
import '../../lua/lua.dart';
import '../../turtle/brain.dart';
import '../../turtle/commands.dart';
import '../../turtle/stack.dart';
import '../../turtle/upgrades.dart';

/// Builds a global table once the VM exists (the Lua layer needs it).
typedef VmApiBuilder = LuaTable Function(LuaVm vm);

/// The builder of the `turtle` global for [brain].
VmApiBuilder turtleApiBuilder(TurtleBrain brain) => (vm) {
  final native = _buildNatives(vm, brain);
  final function = vm.load(_luaLayer, '=turtle');
  final result = vm.call(function, [native]);
  final table = result.isEmpty ? null : result.first;
  if (table is! LuaTable) throw StateError('The turtle API chunk did not return a table');
  return table;
};

/// `checkSlot`: a slot number 1 to 16 as 0 to 15.
int _slot(Args a, int index) {
  final slot = a.integer(index);
  if (slot < 1 || slot > TurtleBrain.inventorySize) {
    throw LuaError.message('Slot number $slot out of range');
  }
  return slot - 1;
}

int? _optSlot(Args a, int index) => a.isNone(index) ? null : _slot(a, index);

/// `checkCount`: 0 to 64, default 64.
int _count(Args a, int index) {
  final count = a.optInteger(index, 64);
  if (count < 0 || count > 64) throw LuaError.message('Item count $count out of range');
  return count;
}

TurtleSide? _side(Args a, int index) {
  if (a.isNone(index)) return null;
  final name = a.string(index);
  return switch (name) {
    'left' => TurtleSide.left,
    'right' => TurtleSide.right,
    _ => a.bad(index, "unknown option '$name'"),
  };
}

Interact _interact(String name, String base) => switch (name.substring(base.length)) {
  'Up' => Interact.up,
  'Down' => Interact.down,
  _ => Interact.forward,
};

/// Builds the command for the Lua call `name(args...)`.
TurtleCommand _command(String name, List<Object?> list) {
  final a = Args(name, list);
  switch (name) {
    case 'forward':
      return TurtleCommands.move(Move.forward);
    case 'back':
      return TurtleCommands.move(Move.back);
    case 'up':
      return TurtleCommands.move(Move.up);
    case 'down':
      return TurtleCommands.move(Move.down);
    case 'turnLeft':
      return TurtleCommands.turn(left: true);
    case 'turnRight':
      return TurtleCommands.turn(left: false);
    case 'dig' || 'digUp' || 'digDown':
      return TurtleCommands.tool(ToolVerb.dig, _interact(name, 'dig'), _side(a, 0));
    case 'attack' || 'attackUp' || 'attackDown':
      return TurtleCommands.tool(ToolVerb.attack, _interact(name, 'attack'), _side(a, 0));
    case 'place' || 'placeUp' || 'placeDown':
      return TurtleCommands.place(_interact(name, 'place'));
    case 'drop' || 'dropUp' || 'dropDown':
      return TurtleCommands.drop(_interact(name, 'drop'), _count(a, 0));
    case 'suck' || 'suckUp' || 'suckDown':
      return TurtleCommands.suck(_interact(name, 'suck'), _count(a, 0));
    case 'detect' || 'detectUp' || 'detectDown':
      return TurtleCommands.detect(_interact(name, 'detect'));
    case 'compare' || 'compareUp' || 'compareDown':
      return TurtleCommands.compare(_interact(name, 'compare'));
    case 'inspect' || 'inspectUp' || 'inspectDown':
      return TurtleCommands.inspect(_interact(name, 'inspect'));
    case 'compareTo':
      return TurtleCommands.compareTo(_slot(a, 0));
    case 'transferTo':
      return TurtleCommands.transferTo(_slot(a, 0), _count(a, 1));
    case 'select':
      return TurtleCommands.select(_slot(a, 0));
    case 'refuel':
      final count = a.isNone(0) ? 0x7FFFFFFF : a.integer(0);
      if (count < 0) throw LuaError.message('Refuel count $count out of range');
      return TurtleCommands.refuel(count);
    case 'equipLeft':
      return TurtleCommands.equip(TurtleSide.left);
    case 'equipRight':
      return TurtleCommands.equip(TurtleSide.right);
  }
  throw LuaError.message('No such turtle command $name');
}

LuaTable _buildNatives(LuaVm vm, TurtleBrain brain) {
  final native = LuaTable();

  // `queue(name, ...)`: the id of the queued command, or `false, message`.
  define(native, 'queue', (list) {
    final name = list.isEmpty ? '' : list.first;
    if (name is! String) throw LuaError.message('turtle command name expected');
    final TurtleCommand command;
    try {
      command = _command(name, list.sublist(1));
    } on LuaError catch (e) {
      // The position of the program that called `turtle.x(...)`, not of the
      // Lua layer: level 2.
      final message = e.value is String ? e.value! as String : 'invalid arguments';
      throw LuaError('${vm.where(2)}$message');
    }
    final id = brain.enqueue(command);
    if (id == null) return <Object?>[false, 'Too many ongoing turtle commands'];
    return one(id.toDouble());
  });

  define(native, 'getFuelLevel', (_) => one(brain.isFuelNeeded ? brain.fuelLevel.toDouble() : 'unlimited'));
  define(native, 'getFuelLimit', (_) => one(brain.isFuelNeeded ? brain.fuelLimit.toDouble() : 'unlimited'));
  define(native, 'getSelectedSlot', (_) => one((brain.selectedSlot + 1).toDouble()));

  define(native, 'getItemCount', (list) {
    final slot = _optSlot(Args('getItemCount', list), 0) ?? brain.selectedSlot;
    return one((brain.inventory[slot]?.count ?? 0).toDouble());
  });

  define(native, 'getItemSpace', (list) {
    final slot = _optSlot(Args('getItemSpace', list), 0) ?? brain.selectedSlot;
    final stack = brain.inventory[slot];
    if (stack == null) return one(64.0);
    final max = brain.itemInfo.maxStack(stack.item);
    return one(((max < 64 ? max : 64) - stack.count).toDouble());
  });

  define(native, 'getItemDetail', (list) {
    final a = Args('getItemDetail', list);
    final slot = _optSlot(a, 0) ?? brain.selectedSlot;
    final stack = brain.inventory[slot];
    if (stack == null) return one(null);
    return one(_toLua(itemDetails(stack, brain.itemInfo, detailed: a.isNone(1) ? false : a.boolean(1))));
  });

  for (final side in TurtleSide.values) {
    final name = side == TurtleSide.left ? 'getEquippedLeft' : 'getEquippedRight';
    define(native, name, (_) {
      final instance = brain.upgradeOn(side);
      if (instance == null) return one(null);
      return one(_toLua(itemDetails(TurtleStack(instance.upgrade.item, 1), brain.itemInfo, detailed: true)));
    });
  }
  return native;
}

/// The table `getItemDetail` returns: the basic details (`name`, `count`),
/// plus `displayName`, `maxCount` and `tags` when [detailed]. The display
/// name is derived from the item key (the host has no translation); `damage`,
/// `maxDamage` and the other component based fields are not filled.
Map<String, Object?> itemDetails(TurtleStack stack, ItemInfo info, {required bool detailed}) {
  final details = <String, Object?>{'name': stack.item, 'count': stack.count};
  if (detailed) {
    details['displayName'] = _displayName(stack.item);
    details['maxCount'] = info.maxStack(stack.item);
    details['tags'] = <String, Object?>{};
  }
  return details;
}

String _displayName(String key) {
  final path = key.contains(':') ? key.substring(key.indexOf(':') + 1) : key;
  return path.split('_').map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1)).join(' ');
}

/// Dart values (the turtle model's results) as Lua values.
Object? _toLua(Object? value) {
  if (value is Map) {
    final table = LuaTable();
    for (final entry in value.entries) {
      final converted = _toLua(entry.value);
      if (converted != null) table.setString(entry.key.toString(), converted);
    }
    return table;
  }
  if (value is List) {
    final table = LuaTable();
    var i = 1;
    for (final item in value) {
      table.setInt(i++, _toLua(item));
    }
    return table;
  }
  if (value is int) return value.toDouble();
  return value;
}

/// Converts the extra values of a `turtle_response` for the Lua side.
Object? turtleValueToLua(Object? value) => _toLua(value);

/// The Lua layer: waits for the command's `turtle_response` and returns its
/// results.
const String _luaLayer = r'''
local native = ...
local queue = native.queue
local unpack = table.unpack or unpack

local function wait(id, err)
  if id == false then return false, err end
  while true do
    local response = table.pack(coroutine.yield("turtle_response"))
    if response[1] == "terminate" then error("Terminated", 0) end
    if response[1] == "turtle_response" and response[2] == id then
      return unpack(response, 3, response.n)
    end
  end
end

local turtle = {}

local commands = {
  "forward", "back", "up", "down", "turnLeft", "turnRight",
  "dig", "digUp", "digDown", "place", "placeUp", "placeDown",
  "drop", "dropUp", "dropDown", "suck", "suckUp", "suckDown",
  "attack", "attackUp", "attackDown", "detect", "detectUp", "detectDown",
  "compare", "compareUp", "compareDown", "inspect", "inspectUp", "inspectDown",
  "compareTo", "transferTo", "select", "refuel", "equipLeft", "equipRight",
}
for _, name in ipairs(commands) do
  turtle[name] = function(...) return wait(queue(name, ...)) end
end

for _, name in ipairs({
  "getFuelLevel", "getFuelLimit", "getSelectedSlot", "getItemCount", "getItemSpace",
  "getItemDetail", "getEquippedLeft", "getEquippedRight",
}) do
  turtle[name] = native[name]
end

return turtle
''';

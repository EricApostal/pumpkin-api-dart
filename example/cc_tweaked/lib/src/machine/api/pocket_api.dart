// The `pocket` API of CC: Tweaked (`shared/pocket/apis/PocketAPI.java`,
// mc-26.3): control the pocket computer you are using, adding or removing its
// upgrades.
//
// Only a pocket computer has this global, which is how a program tells what it
// runs on:
//
//     if pocket then print("On a pocket computer") end
//
// `bios.lua` loads `rom/apis/pocket` on the same test, and the mod's ROM has no
// such directory, so the global is this table alone; it must therefore be
// present only where it really works (a pocket computer), never on a block
// computer or a turtle.
//
// Java's four methods run on the main thread and return `true`, or `false` with
// a reason. Here they need the holder's inventory, which only the plugin tick
// can touch, so the native queues the request and the Lua layer waits for the
// `pocket_response` event carrying its id — the shape of the `turtle` API
// (`turtle_api.dart`, `turtle/brain.dart`).
import '../../lua/lua.dart';
import '../lua_host.dart';

/// Which upgrade slot a method works on (`PocketSide`).
///
/// `top` is the `top_pocket_upgrade` component of the item, shown on the
/// computer's `top` side; `back` is `back_pocket_upgrade` on its `back` side
/// (`PocketBrain.java:51-52`, where the peripheral of an upgrade is
/// `computer.setPeripheral(side, ...)`).
enum PocketSide {
  top,
  back;

  /// The Lua name (`"top"`, `"back"`), which is also the side the upgrade's
  /// peripheral is attached to.
  String get luaName => name;

  /// The side called [name], or null.
  static PocketSide? parse(String name) {
    for (final side in values) {
      if (side.luaName == name.toLowerCase()) return side;
    }
    return null;
  }
}

/// What the `pocket` API needs from the plugin: the holder's inventory and the
/// upgrade components of its item.
///
/// The implementation owns the request ids: it answers each queued request with
/// a `pocket_response` event `(id, ok, reason?)`, exactly as a turtle's brain
/// answers `turtle_response`.
abstract interface class PocketHost {
  /// The computer's event queue (`Computer.queueEvent`), set when the computer
  /// is given this host.
  set queueEvent(void Function(String name, List<Object?> args)? send);

  /// `pocket.equipBack` / `equipTop`: queues a search of the holder's
  /// inventory for another upgrade and its move into [side]. Returns the
  /// request id, or null when too many requests wait.
  int? equip(PocketSide side);

  /// `pocket.unequipBack` / `unequipTop`: queues taking the upgrade out of
  /// [side] and giving its item back to the holder. Returns the request id, or
  /// null when too many requests wait.
  int? unequip(PocketSide side);
}

/// The builder of the `pocket` global for [host]'s computer.
HostApiBuilder pocketApiBuilder(PocketHost host) => (lua) {
  final native = LuaTable();

  PocketSide side(Args a, int index) {
    final name = a.optString(index, 'back');
    return PocketSide.parse(name) ?? a.bad(index, "unknown side '$name'");
  }

  /// The arguments of a queued request: its id, or `false` and the reason it
  /// could not be queued.
  List<Object?> queue(NativeImpl submit, String name, List<Object?> list) {
    final id = submit([side(Args(name, list), 0)]);
    if (id.isEmpty || id.first == null) return <Object?>[false, 'Too many ongoing pocket requests'];
    return id;
  }

  define(native, 'equip', (list) => queue((args) => _id(host.equip(args.first! as PocketSide)), 'equip', list));
  define(native, 'unequip', (list) => queue((args) => _id(host.unequip(args.first! as PocketSide)), 'unequip', list));

  final function = lua.load(_luaLayer, '=pocket');
  final result = lua.call(function, [native]);
  final table = result.isEmpty ? null : result.first;
  if (table == null || table is bool || table is double || table is String) {
    throw StateError('The pocket API chunk did not return a table');
  }
  return table;
};

List<Object?> _id(int? id) => id == null ? const <Object?>[null] : <Object?>[id.toDouble()];

/// The Lua layer: `PocketAPI`'s four methods, each waiting for its
/// `pocket_response`.
const String _luaLayer = r'''
local native = ...
local unpack = table.unpack or unpack

local function run(kind, side)
  local id, err = native[kind](side)
  if id == false then return false, err end
  while true do
    local response = table.pack(coroutine.yield("pocket_response"))
    if response[1] == "terminate" then error("Terminated", 0) end
    if response[1] == "pocket_response" and response[2] == id then
      return unpack(response, 3, response.n)
    end
  end
end

local pocket = {}
pocket.equipBack = function() return run("equip", "back") end
pocket.equipTop = function() return run("equip", "top") end
pocket.unequipBack = function() return run("unequip", "back") end
pocket.unequipTop = function() return run("unequip", "top") end

return pocket
''';
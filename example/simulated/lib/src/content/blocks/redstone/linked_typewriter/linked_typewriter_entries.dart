// The typewriter's key table: the entries a player binds to keys, and the
// redstone-link bookkeeping around them.
//
// `KeyboardEntry` is the unit: two item stacks (Create's redstone-link
// `Frequency` pair) and a GLFW key code. The wire codec is
// `ItemStack.OPTIONAL_STREAM_CODEC`, `ItemStack.OPTIONAL_STREAM_CODEC`,
// `ByteBufCodecs.INT` — the exact order of
// `LinkedTypewriterEntries.KeyboardEntry.STREAM_CODEC`.
//
// The table keeps the two "pending" sets the Java class keeps, so a key that is
// activated and deactivated in the same tick ends up deactivated: `updateNetworks`
// adds every pending activation first, then removes every pending deactivation.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.redstone.linked_typewriter
//         .LinkedTypewriterEntries
// TODO(parity): `KeyboardEntry.CODEC` (the NBT form, keys `FirstItem` /
// `SecondItem` / `GLFWKey`) needs the item-stack NBT codec; `saveKeys` /
// `readKeys` wait for it.
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/protocol/item_stack.dart' show ItemStackData;
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// One key of a typewriter: the two link frequencies and the key code.
final class KeyboardEntry {
  /// The key the player pressed (a GLFW code).
  final int glfwKeyCode;

  /// The first redstone-link frequency; an empty stack is `Frequency.EMPTY`.
  ItemStackData first;

  /// The second redstone-link frequency.
  ItemStackData second;

  /// The block the entry belongs to; set when the entry is stored or sent.
  Pos? pos;

  bool _active = false;

  KeyboardEntry({
    required this.glfwKeyCode,
    this.first = ItemStackData.empty,
    this.second = ItemStackData.empty,
    this.pos,
  });

  /// `Frequency.of(stack)`: an empty stack is the empty frequency.
  factory KeyboardEntry.fromCodec(ItemStackData first, ItemStackData second, int glfwKey) =>
      KeyboardEntry(glfwKeyCode: glfwKey, first: first, second: second);

  /// `activate()`.
  void activate() => _active = true;

  /// `deactivate()`.
  void deactivate() => _active = false;

  /// `isAlive()`: whether the key is currently pressed.
  bool get isAlive => _active;

  /// `getTransmittedStrength()`: a live key emits a full signal.
  int get transmittedStrength => _active ? 15 : 0;

  /// `setLocation(pos)`.
  void setLocation(Pos newPos) => pos = newPos;

  /// The pair of frequencies, as the redstone link network keys them.
  (ItemStackData, ItemStackData) get asCouple => (first, second);

  /// `KeyboardEntry.STREAM_CODEC`.
  void write(PacketWriter w) {
    first.write(w);
    second.write(w);
    w.writeInt(glfwKeyCode);
  }

  /// The reader of [write].
  static KeyboardEntry read(PacketReader r) =>
      KeyboardEntry.fromCodec(ItemStackData.read(r), ItemStackData.read(r), r.readInt());

  @override
  String toString() => 'KeyboardEntry(key $glfwKeyCode, active: $_active)';
}

/// `LinkedTypewriterEntries`: the key table of one typewriter.
final class LinkedTypewriterEntries {
  /// `Int2ObjectLinkedOpenHashMap`: insertion ordered.
  final Map<int, KeyboardEntry> _keyMap = <int, KeyboardEntry>{};

  final Set<KeyboardEntry> _newlyActivated = <KeyboardEntry>{};
  final Set<KeyboardEntry> _newlyDeactivated = <KeyboardEntry>{};

  /// The entries by key code (insertion order, as the Java map).
  Map<int, KeyboardEntry> get keyMap => _keyMap;

  /// `getEntries()`: an immutable copy in insertion order.
  List<KeyboardEntry> get entries => List<KeyboardEntry>.unmodifiable(_keyMap.values);

  /// `getSize()`.
  int get size => _keyMap.length;

  /// `getEntry(key)`.
  KeyboardEntry? getEntry(int key) => _keyMap[key];

  /// `setKey(index, entry)`: `null` removes the key.
  void setKey(int index, KeyboardEntry? entry) {
    if (entry == null) {
      _keyMap.remove(index);
      return;
    }
    _keyMap[index]?.deactivate();
    _keyMap[index] = entry;
  }

  /// `addAll(map)`: replaces the whole key set without touching the pending
  /// sets (that is what the save packet does after `clearAll`).
  void addAll(Map<int, KeyboardEntry> newMap) => _keyMap.addAll(newMap);

  /// `activateKey(index)`: marks the entry live and queues it for the network.
  void activateKey(int index) {
    final entry = _keyMap[index];
    if (entry == null) return;
    entry.activate();
    _newlyActivated.add(entry);
  }

  /// `deactivateKey(index)`.
  void deactivateKey(int index) {
    final entry = _keyMap[index];
    if (entry == null) return;
    entry.deactivate();
    _newlyDeactivated.add(entry);
  }

  /// `deactivateAll()`: every live entry is queued for removal and turned off.
  void deactivateAll() {
    for (final entry in _keyMap.values) {
      if (entry.isAlive) _newlyDeactivated.add(entry);
      entry.deactivate();
    }
  }

  /// `clearAll()`: every key is dropped, and both pending sets are dropped with
  /// them (so a cleared typewriter sends no network update at all).
  void clearAll() {
    deactivateAll();
    _keyMap.clear();
    _newlyDeactivated.clear();
    _newlyActivated.clear();
  }

  /// `updateNetworks(level)`: activations first, then deactivations, then both
  /// pending sets are emptied.
  ///
  /// [add] and [remove] are the redstone-link network calls
  /// (`Create.REDSTONE_LINK_NETWORK_HANDLER.addToNetwork` / `removeFromNetwork`).
  void updateNetworks({
    required void Function(KeyboardEntry entry) add,
    required void Function(KeyboardEntry entry) remove,
  }) {
    for (final entry in _newlyActivated) {
      add(entry);
    }
    _newlyActivated.clear();

    for (final entry in _newlyDeactivated) {
      remove(entry);
    }
    _newlyDeactivated.clear();
  }

  /// `onKeyInteraction(key, pressed)` from `LinkedTypewriterBlockEntity`: a press
  /// activates the key of that code, a release deactivates it.
  ///
  /// Returns the entry that changed, or `null` when no entry has [key].
  KeyboardEntry? onKeyInteraction(int key, bool pressed) {
    final entry = getEntry(key);
    if (entry == null) return null;
    if (pressed) {
      activateKey(key);
    } else {
      deactivateKey(key);
    }
    return entry;
  }
}

/// `LinkedTypewriterItemBindHandler` / `TypewriterSaveKeyToItemPacket`: writing a
/// key into an item's block-entity tag.
///
/// The tag holds a `Keys` list; an entry whose `GLFWKey` matches is *replaced in
/// place*, otherwise it is appended. The item-stack tags themselves are opaque
/// here (they are the `FirstItem` / `SecondItem` compounds the item NBT codec
/// owns), which is enough to test the list handling.
abstract final class TypewriterItemKeys {
  /// The tag key the entries live under.
  static const String keysTag = 'Keys';

  /// The tag key of the GLFW code inside one entry.
  static const String glfwKeyTag = 'GLFWKey';

  /// `TypewriterSaveKeyToItemPacket.handle`: adds [entry] to [keys] (the existing
  /// `Keys` list, or `null` when the tag has none) and returns the new list.
  ///
  /// [glfwKey] is the code of [entry]; an existing entry with the same code is
  /// replaced, keeping its position.
  static List<Map<String, Object>> bindEntry({
    required List<Map<String, Object>>? keys,
    required Map<String, Object> entry,
    required int glfwKey,
  }) {
    final result = [...?keys];
    for (var i = 0; i < result.length; i++) {
      if (result[i][glfwKeyTag] == glfwKey) {
        result[i] = entry;
        return result;
      }
    }
    result.add(entry);
    return result;
  }
}

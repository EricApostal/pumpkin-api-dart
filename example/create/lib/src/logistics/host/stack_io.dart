// Host item stacks <-> [LStack]. A host `ItemStack` is a resource; this reads its item, count and
// the components that differ from the item's defaults (the patch), and builds new stacks from an
// [LStack]. Create's own components are read through `customComponent`; the package components
// are decoded into their logical form, and a lossless copy of them rides along in
// `minecraft:custom_data` under `CreateLogistics` (the wire form cannot hold components that
// nobody registered a codec for).
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/nbt.dart';
import '../model/package.dart';
import '../model/stack.dart';
import '../model/stack_wire.dart';

/// The key inside `minecraft:custom_data` of the private copy of the package data.
const String privateDataKey = 'CreateLogistics';

const String _customData = 'minecraft:custom_data';

class StackIo {
  final StackWire wire;

  /// The names of Create's custom components (`create:filter_items`, ...), read on `create:` items.
  final List<String> customComponentNames;

  final Map<String, Map<String, String>> _baseline = {};

  StackIo(this.wire, this.customComponentNames);

  StackInfo get info => wire.info;

  static String _name(DataComponent c) => RegistryKeys.fromWireName(c.wireName);

  Future<Map<String, String>> _loadBaseline(String key) async {
    final cached = _baseline[key];
    if (cached != null && cached.isNotEmpty) return cached;
    final s = ItemStack.create(registryKey: key, count: 1);
    final map = <String, String>{};
    for (final c in await s.getComponents()) {
      map[_name(c.component)] = base64Encode(c.value);
    }
    final max = await s.getMaxCount();
    info.learn(key, max, map.containsKey('minecraft:max_damage'));
    _baseline[key] = map;
    return map;
  }

  /// Reads [stack] (not consumed). `null` and empty stacks read as [LStack.empty].
  Future<LStack> read(ItemStack? stack) async {
    if (stack == null) return LStack.empty;
    final count = await stack.getCount();
    if (count <= 0) return LStack.empty;
    final key = await stack.getRegistryKey();
    final max = await stack.getMaxCount();
    final base = await _loadBaseline(key);
    final comps = <String, String>{};
    final present = <String>{};
    var maxDamage = 0;
    for (final c in await stack.getComponents()) {
      final name = _name(c.component);
      present.add(name);
      final b64 = base64Encode(c.value);
      if (name == 'minecraft:max_damage') maxDamage = _varInt(c.value);
      if (base[name] != b64) comps[name] = b64;
    }
    for (final name in base.keys) {
      if (!present.contains(name)) comps[name] = removedComponent;
    }
    if (key.startsWith('create:')) {
      for (final name in customComponentNames) {
        List<int>? v;
        try {
          v = stack.customComponent(name);
        } on Object {
          v = null;
        }
        if (v == null) continue;
        if (PackageComponents.logical.contains(name)) {
          final logical = wire.wireToLogical(name, v);
          if (logical != null) comps[name] = base64Encode(logical);
        } else {
          comps[name] = base64Encode(v);
        }
      }
      _restorePrivate(comps);
    }
    final damageable = maxDamage > 0;
    info.learn(key, max, damageable);
    final sorted = Map.fromEntries(
      comps.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return LStack(
      key,
      count,
      maxStack: max,
      damageable: damageable,
      comps: sorted,
    );
  }

  /// A new host stack for [s] (owned by the caller), `null` for an empty stack.
  Future<ItemStack?> write(LStack s) async {
    if (s.isEmpty) return null;
    final out = ItemStack.create(
      registryKey: s.key,
      count: s.count > 255 ? 255 : s.count,
    );
    var customData = s.comps[_customData];
    final logical = <String, String>{};
    for (final e in s.comps.entries) {
      final name = e.key;
      if (name == _customData) continue;
      if (PackageComponents.logical.contains(name)) {
        logical[name] = e.value;
        final w = wire.logicalToWire(name, base64Decode(e.value));
        if (w != null) _setCustom(out, name, w);
        continue;
      }
      if (name.startsWith('create:')) {
        _setCustom(out, name, base64Decode(e.value));
        continue;
      }
      final component = DataComponent.fromWireName(
        RegistryKeys.toWireName(name),
      );
      if (component == null) continue;
      try {
        if (e.value == removedComponent) {
          await out.removeComponent(component: component);
        } else {
          await out.setComponent(
            component: component,
            value: base64Decode(e.value),
          );
        }
      } on Object {
        // a component the host rejects is dropped
      }
    }
    final data = _withPrivate(customData, logical);
    if (data != null) {
      try {
        await out.setComponent(
          component: DataComponent.customData,
          value: data,
        );
      } on Object {
        // ignore: the wire form is still there
      }
    } else if (customData != null && customData != removedComponent) {
      try {
        await out.setComponent(
          component: DataComponent.customData,
          value: base64Decode(customData),
        );
      } on Object {
        // ignore
      }
    }
    return out;
  }

  void _setCustom(ItemStack s, String name, List<int> bytes) {
    try {
      s.setCustomComponent(name, bytes);
    } on Object {
      // a value the host's codec check rejects is dropped
    }
  }

  // -- the private copy -------------------------------------------------------------------------

  /// Replaces the logical package components in [comps] by the private copy if there is one, and
  /// removes the private key from `minecraft:custom_data`.
  void _restorePrivate(Map<String, String> comps) {
    final cd = comps[_customData];
    if (cd == null || cd == removedComponent) return;
    try {
      final root = NetworkNbt.decode(base64Decode(cd));
      if (root == null) return;
      final map = Map<String, NbtValue>.of(root.asCompound);
      final priv = map.remove(privateDataKey);
      if (priv == null || priv.kind != NbtKind.string) return;
      final decoded = (jsonDecode(priv.value as String) as Map)
          .cast<String, String>();
      comps.addAll(decoded);
      if (map.isEmpty) {
        comps.remove(_customData);
      } else {
        comps[_customData] = base64Encode(
          NetworkNbt.encode(NbtValue.compound(map)),
        );
      }
    } on Object {
      // a custom_data value that is no compound stays as it is
    }
  }

  /// The `minecraft:custom_data` bytes with the private copy of [logical], or `null` when there
  /// is nothing to add.
  List<int>? _withPrivate(String? existing, Map<String, String> logical) {
    if (logical.isEmpty) return null;
    var map = <String, NbtValue>{};
    if (existing != null && existing != removedComponent) {
      try {
        map = Map<String, NbtValue>.of(
          NetworkNbt.decode(base64Decode(existing))?.asCompound ?? const {},
        );
      } on Object {
        map = {};
      }
    }
    map[privateDataKey] = NbtValue.string(jsonEncode(logical));
    return NetworkNbt.encode(NbtValue.compound(map));
  }

  static int _varInt(List<int> bytes) {
    var value = 0;
    var shift = 0;
    for (final b in bytes) {
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return value;
  }
}

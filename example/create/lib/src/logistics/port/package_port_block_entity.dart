// `PackagePortBlockEntity`, `FrogportBlockEntity` and `PostboxBlockEntity`: the ports that accept
// packages and forward them to their target (a chain conveyor or a train station).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../host/host_inventory.dart';
import '../host/lg_block_entity.dart';
import '../host/lvl.dart';
import '../host/runtime.dart';
import '../model/inventory.dart';
import '../model/package.dart';
import '../model/stack.dart';
import '../packager/packager_block_entity.dart';
import 'package_port_target.dart';

/// A frogport that can be woken by the packager below it (`FrogportBlockEntity`).
abstract interface class FrogportPuller {
  void tryPullingFromOwnAndAdjacentInventories();
}

/// `PackagePortBlockEntity`.
abstract class PackagePortBlockEntity extends LgBlockEntity {
  /// The 18 package slots (`inventory` in Java; named `packages` here because `inventory` is a
  /// host top-level name).
  final MemoryInv packages = MemoryInv(
    18,
    limit: 64,
    validator: (slot, stack) => PackageItem.isPackage(stack),
  );

  bool acceptsPackages = true;
  String addressFilter = '';
  PackagePortTarget? target;

  final Map<String, dynamic> _state = {};

  PackagePortBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => _state;

  /// The package filter string (`getFilterString`), `null` when packages are not accepted.
  String? get filterString => acceptsPackages ? addressFilter : null;

  bool get isBackedUp => packages.nonEmpty().length >= packages.slots;

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
    acceptsPackages = map['acceptsPackages'] as bool? ?? true;
    addressFilter = map['addressFilter'] as String? ?? '';
    target = PackagePortTarget.fromMap(map['target']);
    final stacks = map['inventory'];
    if (stacks is List) {
      for (var i = 0; i < packages.slots && i < stacks.length; i++) {
        packages.stacks[i] = stacks[i] is String
            ? _stack(stacks[i] as String)
            : LStack.empty;
      }
    }
  }

  static LStack _stack(String json) {
    try {
      return LStackMapper.fromJson(json);
    } on Object {
      return LStack.empty;
    }
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'acceptsPackages': acceptsPackages,
    'addressFilter': addressFilter,
    'target': target?.toMap(),
    'inventory': [
      for (final s in packages.stacks) s.isEmpty ? null : s.toJson(),
    ],
  };

  /// `filterChanged()`.
  void filterChanged() {}

  /// `getComparatorOutput()`.
  int get comparatorOutput {
    final nonEmpty = packages.nonEmpty().length;
    if (nonEmpty == 0) return 0;
    return (1 + (14 * nonEmpty) ~/ packages.slots).clamp(0, 15);
  }

  /// `drop(box)`.
  void drop(LStack box) {
    if (box.isEmpty) return;
    final w = world;
    if (w == null) return;
    unawaited(_drop(w, box));
  }

  Future<void> _drop(World w, LStack box) async {
    final stack = await Lg.i.write(box);
    if (stack != null) await w.dropItem(pos.toPos().center, stack);
  }

  /// The block key at [pos].
  String get blockKey =>
      world == null ? 'minecraft:air' : Lvl(world!).blockKey(pos.toPos());

  @override
  void onRemoved() {
    for (final stack in packages.nonEmpty()) {
      drop(stack);
    }
    packages.clear();
    super.onRemoved();
  }
}

/// `FrogportBlockEntity`.
class FrogportBlockEntity extends PackagePortBlockEntity
    implements FrogportPuller {
  static const String type = 'create:package_frogport';

  double passiveYaw = 0;
  bool failedLastExport = false;

  FrogportBlockEntity(super.worldId, super.pos);

  @override
  Map<String, dynamic> get state => super.state;

  @override
  void readState(Map<String, dynamic> map) {
    super.readState(map);
    passiveYaw = (map['passiveYaw'] as num?)?.toDouble() ?? 0;
    failedLastExport = map['failedLastExport'] == true;
  }

  @override
  Map<String, dynamic> stateToMap() => {
    ...super.stateToMap(),
    'passiveYaw': passiveYaw,
    'failedLastExport': failedLastExport,
  };

  @override
  void lazyTick() {
    super.lazyTick();
    final previousFail = failedLastExport;
    _tryPushingToAdjacentInventories();
    tryPullingFromOwnAndAdjacentInventories();
    if (failedLastExport != previousFail) sendData();
  }

  /// `tryPushingToAdjacentInventories()`: packages in the port move into the inventory below.
  void _tryPushingToAdjacentInventories() {
    if (packages.nonEmpty().isEmpty) return;
    failedLastExport = false;
    final w = world;
    if (w == null) return;
    final below = pos.toPos().below;
    final inv = hostInvAt(
      w,
      below.toBlockPos(),
      Lg.i.io,
      side: Direction.up.toHost(),
    );
    if (inv == null) return;
    for (var slot = 0; slot < packages.slots; slot++) {
      final stack = packages.at(slot);
      if (stack.isEmpty) continue;
      unawaited(_pushOne(inv, slot));
    }
  }

  Future<void> _pushOne(ItemInv target, int slot) async {
    final stack = packages.extractNow(slot, 1, simulate: true);
    if (stack.isEmpty) return;
    final remainder = await insertStacked(target, stack);
    if (remainder.isEmpty) {
      packages.extractNow(slot, 1);
      markDirty();
    } else {
      failedLastExport = true;
    }
  }

  /// `tryPullingFromOwnAndAdjacentInventories()`.
  @override
  void tryPullingFromOwnAndAdjacentInventories() => unawaited(_pull());

  Future<void> _pull() async {
    if (target == null) return;
    if (await _tryPullingFrom(packages)) return;

    final w = world;
    if (w == null) return;

    // The packager below exposes its held box through its capability in Java; plugin block
    // entities have no item handler here, so the box is taken from the block entity directly.
    final below = store.typed<PackagerBlockEntity>(
      worldId,
      pos.toPos().below.toBlockPos(),
    );
    if (below != null && below.heldBox.isNotEmpty) {
      if (packages.nonEmpty().length < packages.slots) {
        final box = below.heldBox;
        below.heldBox = LStack.empty;
        below.notifyUpdate();
        startAnimation(box, deposit: true);
        return;
      }
    }

    final inv = hostInvAt(
      w,
      pos.toPos().below.toBlockPos(),
      Lg.i.io,
      side: Direction.up.toHost(),
    );
    if (inv == null) return;
    await _tryPullingFrom(inv);
  }

  /// `tryPullingFrom(handler)`.
  Future<bool> _tryPullingFrom(ItemInv handler) async {
    final filter = filterString;
    for (var slot = 0; slot < handler.slots; slot++) {
      final stack = await handler.stackAt(slot);
      if (stack.isEmpty || !PackageItem.isPackage(stack)) continue;
      if (filter != null && PackageItem.matchBoxAddress(stack, filter))
        continue;
      final taken = await handler.extract(slot, 1);
      if (taken.isEmpty) continue;
      startAnimation(taken, deposit: true);
      return true;
    }
    return false;
  }

  /// `startAnimation(box, deposit)`: the port forwards the package at once.
  void startAnimation(LStack box, {required bool deposit}) {
    if (!PackageItem.isPackage(box)) return;
    if (deposit) {
      _deposit(box);
      return;
    }
    if (packages.insertStackedNow(box).isNotEmpty) drop(box);
  }

  void _deposit(LStack box) {
    // The target blocks (chain conveyor, train station) belong to other modules; a package that
    // cannot be exported is dropped at the port.
    drop(box);
  }
}

/// `PostboxBlockEntity`: a package port with an 18 slot buffer, used by train stations.
class PostboxBlockEntity extends PackagePortBlockEntity {
  static const String type = 'create:package_postbox';

  bool forceFlag = false;

  PostboxBlockEntity(super.worldId, super.pos);

  /// `onOpenChange(open)`.
  void onOpenChange(bool open) {
    final w = world;
    if (w == null) return;
    final info = Lvl(w).info(pos.toPos());
    if (info == null || !info.key.contains('_postbox')) return;
    unawaited(
      Lvl(w).setProps(pos.toPos(), {
        'open': open ? 'true' : 'false',
      }, neighbors: true),
    );
  }
}

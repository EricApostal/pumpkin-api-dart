/// `FactoryPanelSupportBehaviour` (Create's factory gauge link of redstone links and
/// display links), published by the `redstone` module.
///
/// The behaviour lives on the redstone link and display link block entities and stores
/// the factory panels connected to them. The logistics module provides
/// [FactoryPanelAccess] as a service (`ctx.services.provide<FactoryPanelAccess>(...)`) so
/// the behaviour can ask a panel for its state, and calls [PanelSupportBehaviour.connect] /
/// [PanelSupportBehaviour.disconnect] (found with `be.getBehaviour<PanelSupportBehaviour>()`)
/// when the player connects a panel with a link. Without the service the links simply
/// have no panels.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/common.dart' hide pos;
import '../common/host_bridge.dart';
import '../core/block_entity.dart';
import '../core/module.dart';

/// `PanelSlot`: the four slots of a factory panel block, in Java's enum order.
enum PanelSlotId {
  topLeft('top_left'),
  topRight('top_right'),
  bottomLeft('bottom_left'),
  bottomRight('bottom_right');

  const PanelSlotId(this.serializedName);

  final String serializedName;

  static PanelSlotId? byName(String? name) {
    for (final s in values) {
      if (s.serializedName == name) return s;
    }
    return null;
  }
}

/// `FactoryPanelPosition`: a panel block and one of its slots.
final class FactoryPanelPos {
  final Pos pos;
  final PanelSlotId slot;

  const FactoryPanelPos(this.pos, this.slot);

  @override
  bool operator ==(Object other) => other is FactoryPanelPos && other.pos == pos && other.slot == slot;

  @override
  int get hashCode => Object.hash(pos, slot);

  @override
  String toString() => 'FactoryPanelPos($pos, ${slot.serializedName})';
}

/// A loaded factory panel as the links see it (`FactoryPanelBehaviour`).
abstract interface class FactoryPanelHandle {
  /// `isActive()`.
  bool get isActive;

  /// `satisfied`.
  bool get satisfied;

  /// `count`.
  int get count;

  /// `getLevelInStorage()`: how many of the filter item the panel's storage holds.
  int get levelInStorage;

  /// The display name of the panel's filter item (`getFilter().getHoverName()`).
  String get filterName;

  /// `getAmount() * (upTo ? 1 : filter.getMaxStackSize())`: the demand in items.
  int get demand;

  /// `getPromised()`: items on their way.
  int get promised;

  /// `getIngredientStatusColor()` as 0xRRGGBB.
  int get ingredientStatusColor;

  /// `checkForRedstoneInput()`: the panel re-reads its redstone inputs.
  void checkForRedstoneInput();

  /// `targetedByLinks.remove(linkPos)` followed by a block entity update.
  void removeLink(Pos linkPos);
}

/// The logistics module's side: finds the panels of a world.
abstract interface class FactoryPanelAccess {
  /// `FactoryPanelBehaviour.at(level, position)`, `null` if there is no panel.
  FactoryPanelHandle? panelAt(String worldId, FactoryPanelPos position);
}

/// `FactoryPanelSupportBehaviour`.
class PanelSupportBehaviour extends BlockEntityBehaviour {
  static const String behaviourId = 'FactoryPanelSupport';

  @override
  String get id => behaviourId;

  final List<FactoryPanelPos> _linkedPanels = [];
  bool _changed = false;

  final bool Function() _isOutput;
  final bool Function() _outputPower;
  final void Function() _onNotify;
  final FactoryPanelAccess? Function() _access;

  PanelSupportBehaviour({
    required bool Function() isOutput,
    required bool Function() outputPower,
    required void Function() onNotify,
    required FactoryPanelAccess? Function() access,
  }) : _isOutput = isOutput,
       _outputPower = outputPower,
       _onNotify = onNotify,
       _access = access;

  /// Convenience constructor taking the access from [ctx]'s services.
  factory PanelSupportBehaviour.of(
    CreateContext ctx, {
    required bool Function() isOutput,
    required bool Function() outputPower,
    required void Function() onNotify,
  }) => PanelSupportBehaviour(
    isOutput: isOutput,
    outputPower: outputPower,
    onNotify: onNotify,
    access: () => ctx.services.find<FactoryPanelAccess>(),
  );

  /// `getLinkedPanels`.
  List<FactoryPanelPos> get linkedPanels => _linkedPanels;

  /// `shouldPanelBePowered`.
  bool get shouldPanelBePowered => _isOutput() && _outputPower();

  /// `isOutput`.
  bool get isOutput => _isOutput();

  /// `notifyLink`.
  void notifyLink() => _onNotify();

  /// `connect(panel)`.
  void connect(FactoryPanelPos panel) {
    if (_linkedPanels.contains(panel)) return;
    _linkedPanels.add(panel);
    _changed = true;
  }

  /// `disconnect(panel)`.
  void disconnect(FactoryPanelPos panel) {
    _linkedPanels.remove(panel);
    _changed = true;
  }

  /// `notifyPanels`: every connected panel re-reads its redstone input.
  void notifyPanels() {
    final world = owner.world;
    final access = _access();
    if (world == null || access == null) return;
    for (final position in List.of(_linkedPanels)) {
      if (!world.isLoaded(pos: position.pos.toBlockPos())) continue;
      final panel = access.panelAt(owner.worldId, position);
      if (panel == null) {
        _linkedPanels.remove(position);
        _changed = true;
        continue;
      }
      panel.checkForRedstoneInput();
    }
  }

  /// `shouldBePoweredTristate`: `null` when a connected panel is not loaded (suppress the update).
  bool? shouldBePoweredTristate() {
    final world = owner.world;
    final access = _access();
    for (final position in List.of(_linkedPanels)) {
      if (world == null || !world.isLoaded(pos: position.pos.toBlockPos())) return null;
      final panel = access?.panelAt(owner.worldId, position);
      if (panel == null) {
        _linkedPanels.remove(position);
        _changed = true;
        continue;
      }
      if (panel.isActive && panel.satisfied && panel.count != 0) return true;
    }
    return false;
  }

  @override
  void tick() {
    if (_changed) {
      _changed = false;
      if (!isOutput) notifyLink();
      owner.markDirty();
    }
  }

  @override
  void onRemoved() {
    final world = owner.world;
    final access = _access();
    if (world == null || access == null) return;
    for (final position in _linkedPanels) {
      if (!world.isLoaded(pos: position.pos.toBlockPos())) continue;
      access.panelAt(owner.worldId, position)?.removeLink(owner.pos.toPos());
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putList('LinkedGauges', [
      for (final p in _linkedPanels)
        NbtCompound()
          ..putIntArray('pos', [p.pos.x, p.pos.y, p.pos.z])
          ..putString('slot', p.slot.serializedName),
    ]);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    _linkedPanels.clear();
    for (final entry in tag.getList('LinkedGauges') ?? const <Object>[]) {
      if (entry is! NbtCompound) continue;
      final arr = entry.getIntArray('pos');
      final slot = PanelSlotId.byName(entry.getString('slot'));
      if (arr == null || arr.length < 3 || slot == null) continue;
      _linkedPanels.add(FactoryPanelPos((arr[0], arr[1], arr[2]), slot));
    }
  }
}

// `FactoryPanelBlockEntity`: the four gauges of a factory panel block.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../host/lg_block_entity.dart';
import '../host/lvl.dart';
import '../packager/packager_block_entity.dart';
import '../packager/repackager/repackager_block_entity.dart';
import 'factory_panel_behaviour.dart';

class FactoryPanelBlockEntity extends LgBlockEntity {
  static const String type = 'create:factory_panel';

  final Map<PanelSlot, FactoryPanelBehaviour> panels = {};
  bool restocker = false;
  bool redraw = true;

  final Map<String, dynamic> _state = {};

  FactoryPanelBlockEntity(super.worldId, super.pos) {
    for (final slot in PanelSlot.values) {
      final behaviour = FactoryPanelBehaviour(this, slot);
      panels[slot] = behaviour;
      addBehaviour(behaviour);
    }
  }

  @override
  Map<String, dynamic> get state => _state;

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
    restocker = map['restocker'] == true;
    final stored = map['panels'];
    if (stored is! Map) return;
    for (final slot in PanelSlot.values) {
      final data = stored[slot.serializedName];
      if (data is Map) panels[slot]!.readFromMap(data.cast<String, dynamic>());
    }
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'restocker': restocker,
    'panels': {
      for (final entry in panels.entries)
        if (entry.value.active) entry.key.serializedName: entry.value.toMap(),
    },
  };

  Lvl? get _lvl => world == null ? null : Lvl(world!);

  /// This block entity's position as a [Pos].
  Pos get _pos => pos.toPos();

  /// `FactoryPanelBlock.connectedDirection(state)`.
  Direction get connectedDirection {
    final info = _lvl?.info(_pos);
    final props = info?.properties ?? const <String, String>{};
    final face = props['face'] ?? 'floor';
    final facing =
        Direction.byName(props['facing'] ?? 'north') ?? Direction.north;
    return switch (face) {
      'ceiling' => Direction.up,
      'floor' => Direction.down,
      _ => facing,
    };
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (activePanels() == 0) {
      final w = world;
      if (w != null) unawaited(w.breakBlock(pos, drop: false));
      return;
    }

    final info = _lvl?.info(_pos);
    if (info?.key != 'create:factory_gauge') return;
    final adjacent = _lvl
        ?.info(_pos.relative(connectedDirection.opposite))
        ?.key;
    final shouldBeRestocker = adjacent == 'create:packager';
    if (restocker == shouldBeRestocker) return;
    restocker = shouldBeRestocker;
    redraw = true;
    sendData();
  }

  /// `getRestockedPackager()`.
  PackagerBlockEntity? getRestockedPackager() {
    if (!restocker) return null;
    final info = _lvl?.info(_pos);
    if (info?.key != 'create:factory_gauge') return null;
    final packagerPos = _pos.relative(connectedDirection.opposite);
    final be = store.typed<PackagerBlockEntity>(
      worldId,
      packagerPos.toBlockPos(),
    );
    if (be == null || be is RepackagerBlockEntity) return null;
    return be;
  }

  int activePanels() {
    var result = 0;
    for (final behaviour in panels.values) {
      if (behaviour.isActive) result++;
    }
    return result;
  }

  /// `addPanel(slot, frequency)`.
  bool addPanel(PanelSlot slot, String? frequency) {
    final behaviour = panels[slot];
    if (behaviour == null || behaviour.isActive) return false;
    behaviour.enable();
    if (frequency != null) behaviour.setNetwork(frequency);
    redraw = true;
    sendData();
    return true;
  }

  /// `removePanel(slot)`.
  bool removePanel(PanelSlot slot) {
    final behaviour = panels[slot];
    if (behaviour == null || !behaviour.isActive) return false;
    behaviour.disable();
    redraw = true;
    sendData();
    return true;
  }

  void notifyUpdate() => sendData();

  @override
  void onRemoved() {
    for (final behaviour in panels.values) {
      if (behaviour.isActive) behaviour.disconnectAll();
    }
    final count = activePanels();
    final w = world;
    if (w != null && count > 1) {
      unawaited(_dropGauges(w, count - 1));
    }
    super.onRemoved();
  }

  Future<void> _dropGauges(World w, int count) async {
    final stack = ItemStack.create(
      registryKey: 'create:factory_gauge',
      count: count,
    );
    await w.dropItem(pos.center, stack);
  }
}

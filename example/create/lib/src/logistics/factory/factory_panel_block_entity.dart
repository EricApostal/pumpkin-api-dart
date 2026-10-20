// `FactoryPanelBlockEntity`: the four gauges of a factory panel block.
import 'dart:async';
import 'dart:math' as math;

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
    restocker = map['Restocker'] == true;
    for (final slot in PanelSlot.values) {
      final data = map[slot.serializedName];
      if (data is! Map) continue;
      final behaviour = panels[slot]!;
      behaviour.slot = slot;
      behaviour.readFromMap(data.cast<String, dynamic>());
    }
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'Restocker': restocker,
    for (final entry in panels.entries)
      if (entry.value.active) entry.key.serializedName: entry.value.toMap(),
  };

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putBool('Restocker', restocker);
    if (clientPacket && redraw) {
      // `NBTHelper.putMarker`: the client rebuilds the panel shape and clears the marker.
      tag.putCompound('Redraw', NbtCompound());
      redraw = false;
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.containsKey('Restocker')) {
      restocker = tag.getBool('Restocker') ?? false;
    }
    if (clientPacket && tag.containsKey('Redraw')) {
      redraw = true;
      lastShape = null;
      world?.invalidateShape(pos);
    }
  }

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
    lastShape = null;
    world?.invalidateShape(pos);
    if (activePanels() > 1) _playSound(place: true);
    sendData();
    return true;
  }

  /// `removePanel(slot)`.
  bool removePanel(PanelSlot slot) {
    final behaviour = panels[slot];
    if (behaviour == null || !behaviour.isActive) return false;
    behaviour.disable();
    redraw = true;
    lastShape = null;
    world?.invalidateShape(pos);
    if (activePanels() > 0) _playSound(place: false);
    sendData();
    return true;
  }

  /// `getBlockState().getSoundType()` of the gauge: the place or break sound of copper.
  void _playSound({required bool place}) {
    final w = world;
    if (w == null) return;
    w.playSound(
      sound: place ? Sound.blockCopperPlace : Sound.blockCopperBreak,
      category: SoundCategory.blocks,
      pos: pos.toPos().center,
      // `(getVolume() + 1) / 2` and `getPitch() * 0.8` of the sound type.
      volume: 1,
      pitch: 0.8,
    );
  }

  /// `FactoryPanelBlockEntity.getShape()`: the union of the boxes of the active gauges.
  ///
  /// Each gauge is a `1/16` box around its slot position, inflated by `1/16` and by `3/16` along
  /// the plane of the block's connected direction. The result is cached in [lastShape] until a
  /// gauge is added or removed, like Java.
  List<BlockBox> getShape() {
    final cached = lastShape;
    if (cached != null) return cached;

    final props = _lvl?.info(_pos)?.properties ?? const <String, String>{};
    final xRot = _radToDeg(_xRot(props)) + 90;
    final yRot = _radToDeg(_yRot(props));
    final plane = _axisAlignedPlaneOf(connectedDirection);

    final boxes = <BlockBox>[];
    for (final behaviour in panels.values) {
      if (!behaviour.isActive) continue;
      var vec = (
        0.25 + behaviour.slot.xOffset * 0.5,
        1 / 16,
        0.25 + behaviour.slot.yOffset * 0.5,
      );
      vec = _rotateCenteredDeg(vec, 180, Axis.y);
      vec = _rotateCenteredDeg(vec, xRot, Axis.x);
      vec = _rotateCenteredDeg(vec, yRot, Axis.y);
      final inflate = 1 / 16;
      final dx = inflate + plane.$1 * 3 / 16;
      final dy = inflate + plane.$2 * 3 / 16;
      final dz = inflate + plane.$3 * 3 / 16;
      boxes.add(
        BlockBox(
          vec.$1 - dx,
          vec.$2 - dy,
          vec.$3 - dz,
          vec.$1 + dx,
          vec.$2 + dy,
          vec.$3 + dz,
        ),
      );
    }
    return lastShape = boxes;
  }

  /// The cached shape (`lastShape`), `null` until [getShape] runs or a gauge changes.
  List<BlockBox>? lastShape;

  /// `FactoryPanelBlock.getXRot(state)`.
  static double _xRot(Map<String, String> props) {
    final face = props['face'] ?? 'floor';
    return face == 'ceiling'
        ? math.pi / 2
        : (face == 'floor' ? -math.pi / 2 : 0.0);
  }

  /// `FactoryPanelBlock.getYRot(state)`.
  static double _yRot(Map<String, String> props) {
    final face = props['face'] ?? 'floor';
    final facing =
        Direction.byName(props['facing'] ?? 'north') ?? Direction.north;
    return (face == 'ceiling' ? math.pi : 0.0) + _rad(
      _horizontalAngle(facing),
    );
  }

  static double _rad(double degrees) => degrees == 0 ? 0 : degrees / 180 * math.pi;

  static double _radToDeg(double radians) => radians == 0 ? 0 : radians * 180 / math.pi;

  /// `AngleHelper.horizontalAngle`.
  static double _horizontalAngle(Direction facing) {
    if (facing.axis.isVertical) return 0;
    var angle = facing.toYRot;
    if (facing.axis == Axis.x) angle = -angle;
    return angle;
  }

  /// `VecHelper.axisAlingedPlaneOf(Direction)`.
  static (double, double, double) _axisAlignedPlaneOf(Direction face) {
    final normal = face.normal;
    return (
      1 - normal.$1.abs().toDouble(),
      1 - normal.$2.abs().toDouble(),
      1 - normal.$3.abs().toDouble(),
    );
  }

  /// `VecHelper.rotateCentered(vec, deg, axis)`.
  static (double, double, double) _rotateCenteredDeg(
    (double, double, double) vec,
    double deg,
    Axis axis,
  ) {
    if (deg == 0) return vec;
    final angle = deg / 180 * math.pi;
    final sin = math.sin(angle), cos = math.cos(angle);
    final x = vec.$1 - 0.5, y = vec.$2 - 0.5, z = vec.$3 - 0.5;
    final (double, double, double) r = switch (axis) {
      Axis.x => (x, y * cos - z * sin, z * cos + y * sin),
      Axis.y => (x * cos + z * sin, y, z * cos - x * sin),
      Axis.z => (x * cos - y * sin, y * cos + x * sin, z),
    };
    return (r.$1 + 0.5, r.$2 + 0.5, r.$3 + 0.5);
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

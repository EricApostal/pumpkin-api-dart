// `ControllerRailBlock`: a powered rail that accelerates minecarts to a speed proportional
// to its redstone power, in a direction. The vanilla `BaseRailBlock` shape logic (rails that
// connect to their neighbours and form curves and slopes on their own) is not ported.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/util.dart' hide pos;
import '../core/blocks.dart';
import 'rail_logic.dart';
import 'support/level.dart';
import 'support/manifest_block.dart';
import 'support/placement.dart';
import 'support/placer.dart';
import 'support/shapes.dart';

/// [RailEnv] over the host.
final class HostRailEnv implements RailEnv {
  final Lvl lvl;

  const HostRailEnv(this.lvl);

  @override
  BState stateAt(Pos pos) {
    final info = lvl.info(pos);
    return info == null ? BState.air : BState(info.key, info.properties);
  }

  @override
  Future<int> bestNeighborSignal(Pos pos) => lvl.bestNeighborSignal(pos);
}

/// `ControllerRailBlock`.
final class ControllerRailBlock {
  static const String key = 'controller_rail';

  late final CreateBlock block;

  /// The last position of each minecart that touched a rail, to estimate its motion.
  final Map<int, (Vec3, int)> _lastSeen = {};

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      shapeRules: [
        for (final shape in const ['north_south', 'east_west', 'ascending_east', 'ascending_west', 'ascending_north', 'ascending_south'])
          ShapeRule(
            when: {'shape': shape},
            collisionShape: BlockShape.empty,
            selectionShape: BlockShape.boxes([pixelBox(0, 0, 0, 16, railIsSlope(shape) ? 8 : 2, 16)]),
          ),
      ],
      collisionShape: BlockShape.empty,
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        onEntityCollision: _onEntityInside,
        onComparatorOutput: (server, e) => int.tryParse(block.stateOf(e.stateIndex)['power'] ?? '') ?? 0,
        onCanPlace: (server, e) => e.canPlace && Lvl(e.targetWorld).canSupportRigid(e.pos.toPos().below),
      ),
    );
    return block;
  }

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final ctx = placeContextOf(server, e);
    if (ctx != null) {
      final placed = railPlacement(ctx);
      final current = block.stateOf(e.stateIndex);
      // Keep a slope the player set up; straight rails follow the player's direction.
      if (!railIsSlope(current['shape'] ?? '') &&
          (placed['shape'] != current['shape'] || placed['backwards'] != current['backwards'])) {
        await lvl.setProps(pos, placed, neighbors: true);
      }
    }
    await _updateState(lvl, pos);
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final props = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    // shouldBeRemoved
    if (!railIsStable(props['shape'] ?? 'north_south', lvl.canSupportRigid, pos)) {
      await lvl.destroyBlock(pos);
      return;
    }
    await _updateState(lvl, pos);
  }

  /// `updateState`: the power follows the neighbours and the rails along the line.
  Future<void> _updateState(Lvl lvl, Pos pos) async {
    final props = lvl.info(pos)?.properties;
    if (props == null) return;
    final newPower = await calculateRailPower(pos, HostRailEnv(lvl));
    if ((int.tryParse(props['power'] ?? '') ?? 0) != newPower) {
      await _placeAndNotify(lvl, pos, {'power': '$newPower'}, props['shape'] ?? 'north_south');
    }
  }

  /// `placeAndNotify`.
  Future<void> _placeAndNotify(Lvl lvl, Pos pos, Map<String, String> change, String shape) async {
    await lvl.setProps(pos, change, neighbors: true);
    await lvl.updateNeighbors(pos.below);
    if (railIsSlope(shape)) await lvl.updateNeighbors(pos.above);
  }

  /// `entityInside`: pushes minecarts along the rail.
  Future<void> _onEntityInside(Server server, CustomBlockEntityCollisionEventData e) async {
    if (!e.entityType.endsWith('minecart')) return;
    final world = e.targetWorld;
    final lvl = Lvl(world);
    final railPos = e.pos.toPos();
    final props = lvl.info(railPos)?.properties ?? block.stateOf(e.stateIndex);

    final now = lvl.gameTime;
    final cartPos = e.entityPos;
    final last = _lastSeen[e.entityId];
    _lastSeen[e.entityId] = (cartPos, now);
    if (_lastSeen.length > 512) _lastSeen.removeWhere((_, v) => now - v.$2 > 40);
    // The host does not report a velocity: estimate it from the last position per tick.
    var motion = (0.0, 0.0, 0.0);
    if (last != null && now > last.$2 && now - last.$2 <= 4) {
      final dt = (now - last.$2).toDouble();
      motion = ((cartPos.$1 - last.$1.$1) / dt, (cartPos.$2 - last.$1.$2) / dt, (cartPos.$3 - last.$1.$3) / dt);
    }

    final entity = world.getEntityById(id: e.entityId);
    if (entity == null) return;
    final result = cartVelocity(
      props: props,
      motion: motion,
      cartPos: cartPos,
      railPos: railPos,
      maxSpeed: entity.isInWater() ? 0.2 : 0.4,
    );
    if (result == null) return;
    entity.setVelocity(velocity: result.velocity);
  }

  /// `onWrenched`: tries the three other rotations, then flipping `backwards`, keeping the
  /// first that is stable. Returns whether the rail changed.
  static Future<bool> wrench(Lvl lvl, Pos pos) async {
    final props = lvl.info(pos)?.properties;
    if (props == null) return false;
    for (final rotation in [BlockRotation.clockwise90, BlockRotation.clockwise180, BlockRotation.counterclockwise90]) {
      final r = railRotate(props, rotation);
      if (railIsStable(r.shape, lvl.canSupportRigid, pos)) {
        await lvl.setProps(pos, {'shape': r.shape, 'backwards': '${r.backwards}'}, neighbors: true);
        await lvl.updateNeighbors(pos.below);
        if (railIsSlope(r.shape)) await lvl.updateNeighbors(pos.above);
        return true;
      }
    }
    final shape = props['shape'] ?? 'north_south';
    if (railIsStable(shape, lvl.canSupportRigid, pos)) {
      await lvl.setProps(pos, {'backwards': '${props['backwards'] != 'true'}'}, neighbors: true);
      return true;
    }
    return true;
  }
}

// The kinetic blocks in the wrench registry of the equipment module
// (`IWrenchable`): which blocks rotate how, what a sneak click does to encased
// blocks, and the state switcher that keeps networks consistent.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/wrenchable.dart';
import 'chain_drive.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'placement.dart';
import 'runtime.dart';
import 'wrench.dart';

Dir _dir(BlockDirection d) => Dir.fromName(d.name)!;

/// Registers the kinetic [blockKeys] and installs the state switcher.
void installKineticWrench(WrenchRegistry registry, KineticsRuntime rt, Iterable<String> blockKeys) {
  registry.stateSwitcher = (world, pos, newStateId) {
    final worldId = rt.worlds.touch(world);
    return KineticOps.switchToBlockState(rt, worldId, pos, rt.states.decode(newStateId));
  };

  KState stateOf(WrenchContext c) => KState(c.blockKey, c.properties);

  int? idOf(KState s) => rt.states.idOf(s);

  RotationTraits traitsOf(KState s) {
    // The horizontal-only variants: `axis` with x/z only (speed controller, sequenced gearshift),
    // `facing` with four values (cuckoo clocks, steam engine).
    final horizontalAxis = s.path == 'rotation_speed_controller' || s.path == 'sequenced_gearshift';
    final horizontalFacing = s.path.endsWith('cuckoo_clock') || s.path == 'steam_engine';
    return RotationTraits(horizontalAxisOnly: horizontalAxis, horizontalFacingOnly: horizontalFacing);
  }

  registry.registerDefault(blockKeys);

  // Cogwheels: a rotated cogwheel must still fit its surroundings (canSurvive).
  for (final large in [false, true]) {
    final key = large ? 'create:large_cogwheel' : 'create:cogwheel';
    registry.register(
      key,
      CallbackWrenchable(
        rotatedState: (c) {
          final s = stateOf(c);
          final r = wrenchRotate(s, _dir(c.face), traits: traitsOf(s), blocks: rt.blocks);
          final axis = r.axisOf('axis') ?? KAxis.y;
          final level = rt.level(rt.worlds.touch(c.world));
          if (!isValidCogwheelPosition(large, level.stateAt, rt.blocks, toKPos(c.pos), axis)) return null;
          return idOf(r);
        },
      ),
    );
  }

  // Encased shafts lose their casing on a sneak click.
  for (final variant in ['andesite', 'brass']) {
    registry.register(
      'create:${variant}_encased_shaft',
      CallbackWrenchable(
        onSneakOverride: (c) async {
          final axis = c.properties['axis'] ?? 'y';
          await c.registry.stateSwitcher!(c.world, c.pos, idOf(KState('create:shaft', {'axis': axis, 'waterlogged': 'false'}))!);
          return WrenchResult.success;
        },
      ),
    );
  }

  // Encased cogwheels: the casing click toggles the shaft stubs, rotation swaps them.
  for (final variant in ['andesite', 'brass']) {
    for (final large in [false, true]) {
      final key = 'create:${variant}_encased${large ? '_large' : ''}_cogwheel';
      late final CallbackWrenchable handler;
      handler = CallbackWrenchable(
        rotatedState: (c) {
          final s = stateOf(c);
          return idOf(wrenchRotate(s, _dir(c.face), traits: traitsOf(s), blocks: rt.blocks));
        },
        onWrenchedOverride: (c) async {
          final s = stateOf(c);
          final face = _dir(c.face);
          if (face.axis != (s.axisOf('axis') ?? KAxis.y)) return c.registry.defaultRotate(c, handler);
          final toggled = s.toggle(face.isPositive ? 'top_shaft' : 'bottom_shaft');
          await c.registry.stateSwitcher!(c.world, c.pos, idOf(toggled)!);
          return WrenchResult.success;
        },
        onSneakOverride: (c) async {
          final axis = c.properties['axis'] ?? 'y';
          final target = KState(large ? 'create:large_cogwheel' : 'create:cogwheel', {'axis': axis, 'waterlogged': 'false'});
          await c.registry.stateSwitcher!(c.world, c.pos, idOf(target)!);
          return WrenchResult.success;
        },
      );
      registry.register(key, handler);
    }
  }

  // Chain drives: rotate around the chain, settle the connections afterwards.
  for (final key in ['create:encased_chain_drive', 'create:adjustable_chain_gearshift']) {
    registry.register(
      key,
      CallbackWrenchable(
        rotatedState: (c) {
          final s = stateOf(c);
          return idOf(wrenchRotate(s, _dir(c.face), traits: traitsOf(s), blocks: rt.blocks));
        },
        updateAfterWrenched: (c, rotatedId) {
          final rotated = rt.states.decode(rotatedId);
          final axis = rotated.axisOf('axis') ?? KAxis.y;
          var s = rotated.setAll({'axis': axis.name, 'part': 'none', 'axis_along_first': 'true'});
          final level = rt.level(rt.worlds.touch(c.world));
          s = chainDriveSettle(s, toKPos(c.pos), level.stateAt, rt.blocks);
          return idOf(s) ?? rotatedId;
        },
      ),
    );
  }

  // The sequenced gearshift tilts to vertical when clicked on a side face.
  registry.register(
    'create:sequenced_gearshift',
    CallbackWrenchable(
      rotatedState: (c) {
        var s = stateOf(c);
        final face = _dir(c.face);
        if (face.axis != KAxis.y && s.axisOf('axis') != face.axis) s = s.toggle('vertical');
        return idOf(wrenchRotate(s, face, traits: traitsOf(s), blocks: rt.blocks));
      },
    ),
  );

  // Large water wheels refuse the wrench; their structure blocks pass the sneak click to the wheel.
  registry.register(
    'create:large_water_wheel',
    CallbackWrenchable(onWrenchedOverride: (c) async => WrenchResult.pass),
  );
  registry.register(
    'create:water_wheel_structure',
    CallbackWrenchable(
      onWrenchedOverride: (c) async => WrenchResult.pass,
      onSneakOverride: (c) async {
        final worldId = rt.worlds.touch(c.world);
        final level = rt.level(worldId);
        final s = level.stateAt(toKPos(c.pos));
        var p = toKPos(c.pos);
        var cur = s;
        for (var i = 0; i < 8 && cur.isCreate('water_wheel_structure'); i++) {
          p = p.relative(cur.dirOf('facing') ?? Dir.north);
          cur = level.stateAt(p);
        }
        if (!cur.isCreate('large_water_wheel')) return c.registry.defaultDismantle(c);
        final master = BlockPos(x: p.x, y: p.y, z: p.z);
        return c.registry.defaultDismantle(
          WrenchContext(
            registry: c.registry,
            player: c.player,
            world: c.world,
            pos: master,
            face: c.face,
            blockKey: cur.block,
            stateId: rt.states.idOf(cur) ?? c.stateId,
            properties: cur.props,
            hand: c.hand,
            stack: c.stack,
            cursor: c.cursor,
          ),
        );
      },
    ),
  );
}

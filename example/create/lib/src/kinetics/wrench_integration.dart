// The kinetic blocks in the wrench registry of the equipment module
// (`IWrenchable`): which blocks rotate how, what a sneak click does to encased
// blocks, and the state switcher that keeps networks consistent.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/wrenchable.dart';
import 'block_data.dart' show dyeColorNames;
import 'chain_drive.dart';
import 'gantry/gantry_shaft.dart' show scheduleGantryShaftPowerUpdate;
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'kinetic_blocks_a.dart'
    show poweredShaftStillValid, steamEngineConnectedDirection;
import 'placement.dart';
import 'runtime.dart';
import 'water_wheel_logic.dart' show waterWheelCanSurvive;
import 'wrench.dart';

Dir _dir(BlockDirection d) => Dir.fromName(d.name)!;

/// Registers the kinetic [blockKeys] and installs the state switcher.
void installKineticWrench(
  WrenchRegistry registry,
  KineticsRuntime rt,
  Iterable<String> blockKeys,
) {
  registry.stateSwitcher = (world, pos, newStateId) {
    final worldId = rt.worlds.touch(world);
    return KineticOps.switchToBlockState(
      rt,
      worldId,
      pos,
      rt.states.decode(newStateId),
    );
  };

  KState stateOf(WrenchContext c) => KState(c.blockKey, c.properties);

  int? idOf(KState s) => rt.states.idOf(s);

  RotationTraits traitsOf(KState s) {
    // The horizontal-only variants: `axis` with x/z only (speed controller, sequenced gearshift),
    // `facing` with four values (cuckoo clocks, steam engine).
    final horizontalAxis =
        s.path == 'rotation_speed_controller' ||
        s.path == 'sequenced_gearshift';
    final horizontalFacing =
        s.path.endsWith('cuckoo_clock') || s.path == 'steam_engine';
    return RotationTraits(
      horizontalAxisOnly: horizontalAxis,
      horizontalFacingOnly: horizontalFacing,
    );
  }

  /// `IWrenchable.onWrenched`: the rotated state, or `null` when it would not
  /// survive at the position (Java checks `canSurvive` before switching).
  int? rotatedChecked(
    WrenchContext c,
    bool Function(KState rotated) canSurvive,
  ) {
    final s = stateOf(c);
    final r = wrenchRotate(
      s,
      _dir(c.face),
      traits: traitsOf(s),
      blocks: rt.blocks,
    );
    if (!canSurvive(r)) return null;
    return idOf(r);
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
          final r = wrenchRotate(
            s,
            _dir(c.face),
            traits: traitsOf(s),
            blocks: rt.blocks,
          );
          final axis = r.axisOf('axis') ?? KAxis.y;
          final level = rt.level(rt.worlds.touch(c.world));
          if (!isValidCogwheelPosition(
            large,
            level.stateAt,
            rt.blocks,
            toKPos(c.pos),
            axis,
          )) {
            return null;
          }
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
          await c.registry.stateSwitcher!(
            c.world,
            c.pos,
            idOf(
              KState('create:shaft', {'axis': axis, 'waterlogged': 'false'}),
            )!,
          );
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
          final r = wrenchRotate(
            s,
            _dir(c.face),
            traits: traitsOf(s),
            blocks: rt.blocks,
          );
          final axis = r.axisOf('axis') ?? KAxis.y;
          final level = rt.level(rt.worlds.touch(c.world));
          if (!isValidCogwheelPosition(
            large,
            level.stateAt,
            rt.blocks,
            toKPos(c.pos),
            axis,
          )) {
            return null;
          }
          return idOf(r);
        },
        onWrenchedOverride: (c) async {
          final s = stateOf(c);
          final face = _dir(c.face);
          if (face.axis != (s.axisOf('axis') ?? KAxis.y)) {
            return c.registry.defaultRotate(c, handler);
          }
          final toggled = s.toggle(
            face.isPositive ? 'top_shaft' : 'bottom_shaft',
          );
          await c.registry.stateSwitcher!(c.world, c.pos, idOf(toggled)!);
          return WrenchResult.success;
        },
        onSneakOverride: (c) async {
          final axis = c.properties['axis'] ?? 'y';
          final target = KState(
            large ? 'create:large_cogwheel' : 'create:cogwheel',
            {'axis': axis, 'waterlogged': 'false'},
          );
          await c.registry.stateSwitcher!(c.world, c.pos, idOf(target)!);
          return WrenchResult.success;
        },
      );
      registry.register(key, handler);
    }
  }

  // Chain drives: rotate around the chain, settle the connections afterwards.
  for (final key in [
    'create:encased_chain_drive',
    'create:adjustable_chain_gearshift',
  ]) {
    registry.register(
      key,
      CallbackWrenchable(
        rotatedState: (c) {
          final s = stateOf(c);
          return idOf(
            wrenchRotate(
              s,
              _dir(c.face),
              traits: traitsOf(s),
              blocks: rt.blocks,
            ),
          );
        },
        updateAfterWrenched: (c, rotatedId) {
          final rotated = rt.states.decode(rotatedId);
          final axis = rotated.axisOf('axis') ?? KAxis.y;
          var s = rotated.setAll({
            'axis': axis.name,
            'part': 'none',
            'axis_along_first': 'true',
          });
          final level = rt.level(rt.worlds.touch(c.world));
          s = chainDriveSettle(s, toKPos(c.pos), level.stateAt, rt.blocks);
          // `updateAfterWrenched` re-reads POWERED; the redstone query is async,
          // so the block's scheduled tick finishes it.
          if (s.has('powered')) {
            c.world.scheduleTick(c.pos, const Duration(milliseconds: 50));
          }
          return idOf(s) ?? rotatedId;
        },
      ),
    );
  }

  // Blocks whose rotation must still fit (`IWrenchable.onWrenched` checks
  // `canSurvive` before applying a rotated state).
  registry.register(
    'create:water_wheel',
    CallbackWrenchable(
      rotatedState: (c) {
        final level = rt.level(rt.worlds.touch(c.world));
        return rotatedChecked(
          c,
          (r) => waterWheelCanSurvive(level.stateAt, toKPos(c.pos), r),
        );
      },
    ),
  );

  registry.register(
    'create:steam_engine',
    CallbackWrenchable(
      rotatedState: (c) {
        final level = rt.level(rt.worlds.touch(c.world));
        return rotatedChecked(c, (r) {
          final attached = toKPos(c.pos)
              .relative(steamEngineConnectedDirection(r).opposite);
          return level.stateAt(attached).isCreate('fluid_tank');
        });
      },
    ),
  );

  registry.register(
    'create:powered_shaft',
    CallbackWrenchable(
      rotatedState: (c) {
        final level = rt.level(rt.worlds.touch(c.world));
        return rotatedChecked(
          c,
          (r) => poweredShaftStillValid(r, toKPos(c.pos), level.stateAt),
        );
      },
    ),
  );

  // Cranks and valve handles are attached to the block behind them.
  for (final key in [
    'create:hand_crank',
    'create:copper_valve_handle',
    for (final color in dyeColorNames) 'create:${color}_valve_handle',
  ]) {
    registry.register(
      key,
      CallbackWrenchable(
        rotatedState: (c) {
          return rotatedChecked(c, (r) {
            final facing = r.dirOf('facing') ?? Dir.up;
            final behind = toKPos(c.pos).relative(facing.opposite);
            final state = c.world.getBlockState(pos: toBlockPos(behind));
            return state.collisionShapes.isNotEmpty;
          });
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
        if (face.axis != KAxis.y && s.axisOf('axis') != face.axis) {
          s = s.toggle('vertical');
        }
        return idOf(
          wrenchRotate(s, face, traits: traitsOf(s), blocks: rt.blocks),
        );
      },
    ),
  );

  // Gantry shafts re-run `neighborChanged` after a rotation, so the powered state
  // of the line follows the new facing (`GantryShaftBlock.onWrenched`).
  registry.register(
    'create:gantry_shaft',
    CallbackWrenchable(
      updateAfterWrenched: (c, rotatedId) {
        scheduleGantryShaftPowerUpdate(rt, c.world, c.pos);
        return rotatedId;
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
        if (!cur.isCreate('large_water_wheel')) {
          return c.registry.defaultDismantle(c);
        }
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

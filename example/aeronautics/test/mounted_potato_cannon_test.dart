// The mounted potato cannon's saved state. Java writes `State.CHARGING.name()`
// (`MountedPotatoCannonBlockEntity.java:297`) and reads it with `readEnum`
// (`.java:437-444`), whose unknown name is the first constant, `CHARGED`. The
// state machine is pure, so the encoding runs on the Dart VM.
import 'package:aeronautics/src/content/blocks/mounted_potato_cannon/mounted_potato_cannon_logic.dart';
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/equipment/potato/potato_model.dart' show PotatoType, PotatoTypes;
import 'package:sable/sable.dart' show Vector3d;
import 'package:test/test.dart';

void main() {
  group('MountedPotatoCannon State', () {
    test('is written as the Java enum name, not the Dart one', () {
      final logic = MountedPotatoCannonLogic();
      expect(logic.toMap()['State'], 'CHARGING');
      logic.state = MountedPotatoCannonState.firing;
      expect(logic.toMap()['State'], 'FIRING');
      logic.state = MountedPotatoCannonState.charged;
      expect(logic.toMap()['State'], 'CHARGED');
    });

    test('the Java name resolves to the intended state, not the fallback', () {
      expect(
        MountedPotatoCannonLogic.stateByName('FIRING'),
        MountedPotatoCannonState.firing,
      );
      expect(
        MountedPotatoCannonLogic.stateByName('FIRING'),
        isNot(MountedPotatoCannonState.values.first),
      );
      expect(
        MountedPotatoCannonLogic.stateByName('CHARGING'),
        MountedPotatoCannonState.charging,
      );
    });

    test('an unknown or missing name is the first constant, as readEnum', () {
      expect(
        MountedPotatoCannonLogic.stateByName('sideways'),
        MountedPotatoCannonState.charged,
      );
      expect(
        MountedPotatoCannonLogic.stateByName(null),
        MountedPotatoCannonState.charged,
      );
    });

    test('a round trip through the map keeps the state', () {
      final logic = MountedPotatoCannonLogic()
        ..state = MountedPotatoCannonState.firing;
      final restored = MountedPotatoCannonLogic()..readMap(logic.toMap());
      expect(restored.state, MountedPotatoCannonState.firing);
    });
  });

  group('MountedPotatoCannon inventory', () {
    final types = PotatoTypes([
      PotatoType.fromJson('basic', '{"items": ["minecraft:potato"], "reload_ticks": 10}'),
    ]);

    test('a load keeps the saved ammo: initialize only refreshes the cached type', () {
      // `read` restored the slot; `initialize` used to read an empty map over it, which zeroed
      // `item`/`count` on the first tick after a load
      // (`MountedPotatoCannonBlockEntity.java:75-82` only calls `updateCachedType`).
      final inventory = MountedPotatoCannonInventory()
        ..readMap({'item': 'minecraft:potato', 'count': 7}, types);

      inventory.updateCachedType(types);

      expect(inventory.item, 'minecraft:potato');
      expect(inventory.count, 7);
      expect(inventory.ammo?.type.key, 'basic');
    });

    test('updateCachedType drops a type the slot no longer holds', () {
      final inventory = MountedPotatoCannonInventory(item: 'minecraft:cobblestone', count: 3)
        ..updateCachedType(types);
      expect(inventory.projectileType, isNull);
      expect(inventory.ammo, isNull);
    });
  });

  group('MountedPotatoCannon recoil', () {
    test('the impulse is the opposite of the facing, scaled by the magnitude', () {
      final logic = MountedPotatoCannonLogic();
      // `applyRecoil(2)` is `(2 / 2) * config`.
      logic.applyRecoil(2);
      final expected = logic.recoilMagnitude;
      expect(expected, greaterThan(0));

      final out = Vector3d();
      // The recoil points along the *opposite* of the facing: a cannon facing north kicks south.
      expect(logic.recoilDirection(Direction.north, out), isTrue);
      expect((out.x, out.y, out.z), (0, 0, expected));

      expect(logic.recoilDirection(Direction.up, out), isTrue);
      expect((out.x, out.y, out.z), (0, -expected, 0));
    });

    test('there is nothing to apply before a shot, and the magnitude halves every tick', () {
      final logic = MountedPotatoCannonLogic();
      final out = Vector3d();
      expect(logic.recoilDirection(Direction.north, out), isFalse);

      logic.applyRecoil(4);
      final before = logic.recoilMagnitude;
      logic.tick(speed: 0, powered: false, trapdoorInFront: false);
      expect(logic.recoilMagnitude, before / 2);
      expect(logic.recoilDirection(Direction.north, out), isTrue);
      expect(out.z, before / 2);
    });
  });
}
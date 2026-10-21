// The mounted potato cannon's saved state. Java writes `State.CHARGING.name()`
// (`MountedPotatoCannonBlockEntity.java:297`) and reads it with `readEnum`
// (`.java:437-444`), whose unknown name is the first constant, `CHARGED`. The
// state machine is pure, so the encoding runs on the Dart VM.
import 'package:aeronautics/src/content/blocks/mounted_potato_cannon/mounted_potato_cannon_logic.dart';
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
}

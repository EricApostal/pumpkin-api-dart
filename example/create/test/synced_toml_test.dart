import 'package:create/src/infrastructure/config/synced_toml.dart';
import 'package:test/test.dart';

void main() {
  group('SyncedToml', () {
    test('writes one table per group, values indented with a tab', () {
      final toml = SyncedToml()
        ..table('physics')
        ..value('propellerBearingThrust', 0.2)
        ..table('kinetics.stressValues.v2.impact')
        ..value('borehead_bearing', 8.0);

      expect(toml.toString(), '[physics]\n\tpropellerBearingThrust = 0.2\n\n[kinetics.stressValues.v2.impact]\n\tborehead_bearing = 8.0\n');
    });

    test('a double is always a float literal', () {
      final toml = SyncedToml()
        ..table('a')
        ..value('integer_valued', 2.0)
        ..value('whole', 64.0)
        ..value('an_int', 2);
      expect(toml.toString(), contains('integer_valued = 2.0'));
      expect(toml.toString(), contains('whole = 64.0'));
      expect(toml.toString(), contains('an_int = 2\n'));
    });

    test('a key that is not bare is quoted', () {
      final toml = SyncedToml()
        ..table('assembly')
        ..value('Primary Disassembly', false);
      expect(toml.toString(), contains('"Primary Disassembly" = false'));
    });

    test('a null value writes nothing, so the client keeps its own default', () {
      final toml = SyncedToml()
        ..table('a')
        ..value('kept', 1)
        ..value('dropped', null);
      expect(toml.toString(), isNot(contains('dropped')));
      expect(toml.toString(), contains('kept = 1'));
    });

    test('an empty document is empty', () {
      expect(SyncedToml().isEmpty, isTrue);
      expect((SyncedToml()..value('a', 1)).isEmpty, isFalse);
    });
  });
}

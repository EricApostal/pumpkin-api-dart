// ignore_for_file: implementation_imports
import 'package:simulated/src/config/sim_config.dart';
import 'package:simulated/src/config/sim_synced_config.dart';
import 'package:test/test.dart';

/// The NeoForge handshake has to carry `simulated-synced.toml`: a client that
/// has Simulated parses it into the mod's `ModConfigSpec` and reads it from
/// Create's `KineticStats` (`BlockStressValues.getImpact` ->
/// `SimStress::getImpact`) while building a kinetic block's tooltip. A client
/// the file was never sent to throws `IllegalStateException: Cannot get config
/// value before config is loaded` on the first hover, which is the crash this
/// test guards.
void main() {
  group('simSyncedToml', () {
    test('the body is the Java file layout, not the JSON one', () {
      final body = simSyncedToml(const SimServerConfig());
      expect(body, contains('[assembly]'));
      expect(body, contains('[physics]'));
      expect(body, contains('[blocks]'));
      expect(body, contains('[equipment]'));
      expect(body, contains('maxBlocksMoved = 128000'));
      expect(body, contains('swivel_stiffness = 1600.0'));
      expect(body, contains('optical_sensor_max_range = 15'));
      expect(body, contains('maxPlungerLauncherRange = 64'));
      // The Java key with a space in it (`SimAssembly.java:16`).
      expect(body, contains('"Primary Disassembly" = false'));
      // `CStress.getName()` is `stressValues.v2`, so the table is not `stress`.
      expect(body, isNot(contains('[kinetics.stress]')));
      expect(body, isNot(contains('server.kinetics')));
    });

    test('the stress tables hold the values the plugin config overrides', () {
      final body = simSyncedToml(
        const SimServerConfig(
          kinetics: SimKineticsConfig(
            stress: SimStressConfig(configuredImpacts: {'swivel_bearing': 5.5}),
          ),
        ),
      );
      expect(body, contains('[kinetics.stressValues.v2.impact]'));
      expect(body, contains('swivel_bearing = 5.5'));
    });

    test('no stress override, no stress table', () {
      expect(simSyncedToml(const SimServerConfig()), isNot(contains('stressValues')));
    });

    test('the file name is the one the client writes in its own config dir', () {
      expect(simSyncedConfigFile, 'simulated-synced.toml');
    });
  });
}

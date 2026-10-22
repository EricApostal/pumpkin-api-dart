// ignore_for_file: implementation_imports
import 'package:aeronautics/src/config/aero_config.dart';
import 'package:aeronautics/src/config/aero_synced_config.dart';
import 'package:test/test.dart';

/// `aeronautics-synced.toml` has to reach the client with the handshake: the
/// client parses it into the mod's `ModConfigSpec`, and Create's `KineticStats`
/// reads the stress impact of an Aeronautics kinetic block through the provider
/// `NeoForgeAeroConfigService` registers (`AeroStress::getImpact`). A client the
/// file was never sent to throws "Cannot get config value before config is
/// loaded" on the first hover.
void main() {
  group('aeroSyncedToml', () {
    test('the body is the Java file layout', () {
      final body = aeroSyncedToml(AeroServerConfig());
      expect(body, contains('[physics]'));
      expect(body, contains('[blocks]'));
      expect(body, contains('propellerBearingThrust = 0.2'));
      // The Java config key, not the port's field name (`...AirflowMult`).
      expect(body, contains('propellerBearingAirflow = 0.05'));
      expect(body, isNot(contains('propellerBearingAirflowMult')));
      expect(body, contains('recoil_magnitude = 0.2'));
      expect(body, contains('hot_air_burner_max = 500'));
      expect(body, contains('steam_vent_hot_air_amount = 5000'));
    });

    test('the live config is what is sent', () {
      final config = AeroServerConfig();
      config.physics.woodenPropellerThrust = 3.5;
      expect(aeroSyncedToml(config), contains('woodenPropellerThrust = 3.5'));
    });

    test('the file name is the one the client writes in its own config dir', () {
      expect(aeroSyncedConfigFile, 'aeronautics-synced.toml');
    });
  });
}

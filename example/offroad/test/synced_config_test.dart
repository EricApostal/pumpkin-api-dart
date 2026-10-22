// ignore_for_file: implementation_imports
import 'package:offroad/src/config/offroad_config.dart';
import 'package:offroad/src/config/offroad_synced_config.dart';
import 'package:test/test.dart';

/// `offroad-synced.toml` has to reach the client with the handshake: the client
/// parses it into the mod's `ModConfigSpec`, and Create's `KineticStats` reads
/// the borehead bearing's stress impact through the provider
/// `NeoForgeOffroadConfigService` registers (`OffroadStress::getImpact`). A client
/// the file was never sent to throws "Cannot get config value before config is
/// loaded" on the first hover.
void main() {
  group('offroadSyncedToml', () {
    test('the body is the Java file layout', () {
      final body = offroadSyncedToml(OffroadServerConfig());
      expect(body, contains('[blocks]'));
      expect(body, contains('borehead_bearing_search_radius = 1.5'));
      expect(body, contains('borehead_bearing_stall_recovery_ticks = 10'));
      expect(body, contains('borehead_bearing_stalling_enabled = true'));
      expect(body, contains('borehead_bearing_rotation_divisor = 4.0'));
      // `CStress.getName()` is `stressValues.v2`.
      expect(body, contains('[kinetics.stressValues.v2.impact]'));
      expect(body, contains('borehead_bearing = 8.0'));
      expect(body, contains('wheel_mount = 16.0'));
    });

    test('the live config is what is sent', () {
      final config = OffroadServerConfig();
      config.blocks.boreheadBearingRotationDivisor = 6;
      expect(offroadSyncedToml(config), contains('borehead_bearing_rotation_divisor = 6.0'));
    });

    test('the file name is the one the client writes in its own config dir', () {
      expect(offroadSyncedConfigFile, 'offroad-synced.toml');
    });
  });
}

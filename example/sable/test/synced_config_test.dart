// ignore_for_file: implementation_imports
import 'package:sable/src/config/sable_synced_config.dart';
import 'package:sable/src/sublevel/system/sable_server_config.dart';
import 'package:test/test.dart';

/// `sable-synced.toml` has to reach the client with the handshake: the client
/// parses it into the mod's `ModConfigSpec`, and Sable reads
/// `SUB_LEVEL_SUBSTEPS_PER_TICK` on the client too
/// (`PhysicsConfigData.updateFromConfig`). A client the file was never sent to
/// throws "Cannot get config value before config is loaded" where the Java arm
/// works.
void main() {
  group('sableSyncedToml', () {
    test('the body carries the Java keys', () {
      final body = sableSyncedToml(SableServerConfig());
      expect(body, contains('sub_level_substeps_per_tick = 2'));
      expect(body, contains('sub_level_storage_pruning = false'));
      // The file has no tables: both values are at the root.
      expect(body, isNot(contains('[')));
    });

    test('the live config is what is sent', () {
      expect(
        sableSyncedToml(SableServerConfig(subLevelSubstepsPerTick: 4)),
        contains('sub_level_substeps_per_tick = 4'),
      );
    });

    test('the file name is the one the client writes in its own config dir', () {
      expect(sableSyncedConfigFile, 'sable-synced.toml');
    });
  });
}

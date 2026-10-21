// TEMP: measure the assembly direction the client is told, live. Delete when done.
@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:create/src/core/nbt.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

void main() {
  group('carriage assembly direction probe', skip: PumpkinLab.skipReason(), () {
    test('the carriage spawn payload carries a horizontal direction', () async {
      final lab = await PumpkinLab.boot();
      addTearDown(lab.shutdown);

      final watcher = await lab.connect('Watcher');
      final stand = await lab.playerPosition('Watcher');
      print('PROBE stand=$stand');

      await lab.server.command('forceload add -48 -48 48 48');
      await lab.server.settle(const Duration(seconds: 2));

      // The rig of scn-trainglue-ab.sh, at the client's own chunk corner: the station points at
      // the track under it (offset -2 in x), the assembly direction is north (-z), the scan starts
      // one block in that direction, and the frontmost bogey has to be at the station marker.
      final ox = stand.x & ~15;
      final oz = (stand.z & ~15) + 4;
      final f = stand.y - 6;
      await lab.server.scenario([
        'fill ${ox - 2} ${f - 1} ${oz - 10} ${ox + 5} ${f + 8} ${oz + 6} minecraft:air',
        'fill ${ox - 2} ${f - 1} ${oz - 10} ${ox + 5} ${f - 1} ${oz + 6} minecraft:stone',
        'fill $ox $f ${oz - 8} $ox $f ${oz + 4} create:track',
        'setblock ${ox + 2} $f $oz create:track_station',
        'data merge block ${ox + 2} $f $oz {PluginData:{TargetTrack:[I;-2,0,0]}}',
        'setblock $ox ${f + 1} ${oz - 1} create:small_bogey[axis=z]',
        'setblock $ox ${f + 1} ${oz - 5} create:small_bogey[axis=z]',
        'fill $ox ${f + 2} ${oz - 5} $ox ${f + 2} ${oz - 1} minecraft:iron_block',
        'setblock $ox ${f + 3} ${oz - 3} create:controls[facing=north]',
        'create glue $ox ${f + 1} ${oz - 1} $ox ${f + 2} ${oz - 1}',
        'create glue $ox ${f + 2} ${oz - 1} $ox ${f + 2} ${oz - 2}',
        'create glue $ox ${f + 2} ${oz - 2} $ox ${f + 2} ${oz - 3}',
        'create glue $ox ${f + 2} ${oz - 3} $ox ${f + 2} ${oz - 4}',
        'create glue $ox ${f + 2} ${oz - 4} $ox ${f + 2} ${oz - 5}',
        'create glue $ox ${f + 1} ${oz - 5} $ox ${f + 2} ${oz - 5}',
        'create glue $ox ${f + 2} ${oz - 3} $ox ${f + 3} ${oz - 3}',
      ]);
      final probe = await lab.server.outputOf(
        'create assembleprobe ${ox + 2} $f $oz',
      );
      print('PROBE assemble: ${probe.join(' | ')}');
      await lab.server.settle(const Duration(seconds: 3));

      final spawns = [
        for (final packet in watcher.readTrace().customPayloads)
          if (packet.channel == 'neoforge:advanced_add_entity') packet,
      ];
      print('PROBE spawn payloads: ${spawns.length}');
      for (final packet in spawns) {
        final reader = PacketReader(packet.data!);
        final entityId = reader.readVarInt();
        final length = reader.readVarInt(); // the spawn data length, then the data itself
        final root = NetworkNbt.read(reader)?.asCompound;
        final contraption = root?['Contraption']?.asCompound;
        print(
          'PROBE payload entity=$entityId len=$length '
          'keys=${root?.keys.toList()} '
          'kind=${contraption?['Type']?.value} '
          'direction=${contraption?['AssemblyDirection']?.value} '
          'blocks=${contraption?['Blocks']?.asCompound.length}',
        );
      }
      expect(spawns, isNotEmpty);
    });
  });
}
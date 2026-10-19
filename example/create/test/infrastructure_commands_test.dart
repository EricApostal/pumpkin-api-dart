import 'package:create/src/api/infra_data.dart';
import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/infrastructure/commands/command_parsing.dart';
import 'package:create/src/infrastructure/commands/railway_report.dart';
import 'package:create/src/infrastructure/debug/debug_info.dart';
import 'package:create/src/infrastructure/server_speed.dart';
import 'package:test/test.dart';

void main() {
  test('uuid and entity references', () {
    const u = '123e4567-E89B-12d3-a456-426614174000';
    expect(isUuid(u), isTrue);
    expect(parseUuid(u), '123e4567-e89b-12d3-a456-426614174000');
    expect(() => parseUuid('nope'), throwsA(isA<ArgumentParseException>()));
    expect(shortId(u), '123e4');
    expect(EntityRef.parse(u), isA<EntityUuid>());
    expect(EntityRef.parse('Steve'), isA<PlayerName>());
    expect(() => EntityRef.parse('@e[type=minecart]'), throwsA(isA<ArgumentParseException>()));
  });

  test('catnip config ids and paths', () {
    final id = CatnipConfigId.parse('create:server');
    expect(id.modId, 'create');
    expect(id.side, CatnipConfigSide.server);
    expect(id.toString(), 'create:server');
    expect(CatnipConfigSide.values.map((s) => s.index), [0, 1, 2]);
    expect(() => CatnipConfigId.parse('create'), throwsA(isA<ArgumentParseException>()));
    expect(() => CatnipConfigId.parse('Create:server'), throwsA(isA<ArgumentParseException>()));
    expect(() => CatnipConfigId.parse('create:nowhere'), throwsA(isA<ArgumentParseException>()));
    final p = CatnipConfigPath.parse('kinetics.encasedFan.fanPushDistance');
    expect(p.components, ['kinetics', 'encasedFan', 'fanPushDistance']);
    expect(p.dotted, 'kinetics.encasedFan.fanPushDistance');
    expect(() => CatnipConfigPath.parse('a..b'), throwsA(isA<ArgumentParseException>()));
    expect(() => CatnipConfigPath.parse('a b'), throwsA(isA<ArgumentParseException>()));
  });

  test('config text parsing follows the type of the default', () {
    expect(parseConfigText(true, 'false'), false);
    expect(parseConfigText(true, 'yes'), isNull);
    expect(parseConfigText(5, '12'), 12);
    expect(parseConfigText(5, '1.5'), isNull);
    expect(parseConfigText(1.5, '2'), 2.0);
    expect(parseConfigText('A', 'B', enumValues: ['A', 'B']), 'B');
    expect(parseConfigText('A', 'C', enumValues: ['A', 'B']), isNull);
  });

  test('wrapped values from payload variants', () {
    expect(wrapPayloadVariant('BOOL', true), isA<WrappedBool>());
    expect(wrapPayloadVariant('INT', 3), isA<WrappedInt>());
    expect(wrapPayloadVariant('FLOAT', 1.5), isA<WrappedFloat>());
    expect(wrapPayloadVariant('ENUM', 2), isA<WrappedEnum>());
    expect(wrapPayloadVariant('STRING', 3), isNull);
    expect(WrappedConfigValue.types, ['BOOL', 'INT', 'FLOAT', 'DOUBLE', 'STRING', 'ENUM']);
  });

  test('railway report', () {
    final lines = railwayReport(const RailwaySummary(
      graphCount: 6,
      signalGroupCount: 2,
      trainCount: 1,
      nearestGraphs: [TrackGraphSummary('abcdef12-0000-0000-0000-000000000000', 12, signalCount: 3)],
      nearestTrains: [
        TrainSummary(
          id: '11111222-0000-0000-0000-000000000000',
          name: 'Express',
          carriageCount: 3,
          graphId: 'abcdef12-0000-0000-0000-000000000000',
          destinationName: 'Central',
          distanceToDestination: 41.7,
          hasSchedule: true,
          scheduleEntry: 1,
          scheduleState: 'IN_TRANSIT',
          presence: [(dimension: 'minecraft:overworld', position: (1, 64, 2))],
        ),
      ],
    ));
    final text = lines.whereType<TextLine>().map((l) => l.text).toList();
    expect(text, contains('Track Networks: 6'));
    expect(text, contains('abcde with 12 Nodes'));
    expect(text, contains(' -> 3 Signals'));
    expect(text, contains('[...]')); // more than five graphs
    expect(text, contains('┬11111: Express, 3 Wagons'));
    expect(text, contains('├─Travelling to Central (41m away)'));
    expect(text, contains('├─Schedule, Entry 1, IN TRANSIT'));
    expect(text, contains('├─In minecraft:overworld near [1, 64, 2]'));
    expect(lines.whereType<TeleportButton>().single.command, '/c train tp 11111222-0000-0000-0000-000000000000');
    expect(lines.whereType<DeleteButton>().single.command, '/c train remove 11111222-0000-0000-0000-000000000000');
  });

  test('debug info printing', () {
    final section = DebugInfoSection.builder('Create')
        .put('Mod Version', '6.0.11')
        .put('Boom', (String? p) => throw StateError('no'))
        .put('Multi', 'a\nb')
        .section('Inner')
        .put('x', 'y')
        .finishSection()
        .build();
    final out = printDebugInfo('Server', 'Steve', [section]);
    expect(out, startsWith('<details>\n<summary>Server Info</summary>'));
    expect(out, contains('Create:\n\tMod Version: 6.0.11\n'));
    expect(out, contains('Error getting information!'));
    expect(out, contains('\tMulti: a\n\t       b\n'));
    expect(out, contains('\tInner:\n\t\tx: y\n'));
    expect(out, endsWith('</details>\n'));
  });

  test('server speed sync interval', () {
    final s = ServerSpeedSync();
    var sent = 0;
    for (var i = 0; i < 100; i++) {
      if (s.tick(20)) sent++;
    }
    expect(sent, 4); // after 21 ticks each
  });

  test('binary nbt', () {
    final root = NbtValue.compound({'Command': const NbtValue.string('say hi'), 'auto': const NbtValue.byte(1)});
    final bytes = BinaryNbt.write(root, name: 'x');
    expect(bytes[0], 10);
    final back = BinaryNbt.read(bytes)!;
    expect(back.name, 'x');
    expect(back.root.asCompound['Command']!.value, 'say hi');
    expect(BinaryNbt.read(BinaryNbt.write(root))!.name, '');
    expect(BinaryNbt.read(const [0]), isNull);
  });
}

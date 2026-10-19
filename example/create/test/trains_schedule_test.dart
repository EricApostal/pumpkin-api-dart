import 'package:create/src/common/common.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/protocol/item_stack.dart' show ItemStackData;
import 'package:create/src/redstone/link/frequency.dart';
import 'package:create/src/redstone/link/link_network.dart';
import 'package:create/src/trains/bogey/abstract_bogey_block.dart';
import 'package:create/src/trains/bogey/standard_bogey_block.dart';
import 'package:create/src/trains/entity/carriage.dart';
import 'package:create/src/trains/entity/carriage_bogey.dart';
import 'package:create/src/trains/entity/carriage_storage.dart';
import 'package:create/src/trains/entity/train.dart';
import 'package:create/src/trains/graph/edge_point_type.dart';
import 'package:create/src/trains/graph/dimension_palette.dart' show overworldId;
import 'package:create/src/trains/graph/track_edge.dart';
import 'package:create/src/trains/graph/track_graph.dart';
import 'package:create/src/trains/graph/track_node.dart';
import 'package:create/src/trains/graph/track_node_location.dart';
import 'package:create/src/trains/manager/create.dart';
import 'package:create/src/trains/schedule/condition/cargo_threshold_condition.dart';
import 'package:create/src/trains/schedule/condition/fluid_threshold_condition.dart';
import 'package:create/src/trains/schedule/condition/idle_cargo_condition.dart';
import 'package:create/src/trains/schedule/condition/item_threshold_condition.dart';
import 'package:create/src/trains/schedule/condition/player_passenger_condition.dart';
import 'package:create/src/trains/schedule/condition/redstone_link_condition.dart';
import 'package:create/src/trains/schedule/condition/schedule_wait_condition.dart';
import 'package:create/src/trains/schedule/condition/scheduled_delay.dart';
import 'package:create/src/trains/schedule/condition/station_powered_condition.dart';
import 'package:create/src/trains/schedule/condition/station_unloaded_condition.dart';
import 'package:create/src/trains/schedule/condition/time_of_day_condition.dart';
import 'package:create/src/trains/schedule/condition/timed_wait_condition.dart';
import 'package:create/src/trains/schedule/destination/change_throttle_instruction.dart';
import 'package:create/src/trains/schedule/destination/change_title_instruction.dart';
import 'package:create/src/trains/schedule/destination/deliver_packages_instruction.dart';
import 'package:create/src/trains/schedule/destination/destination_instruction.dart';
import 'package:create/src/trains/schedule/destination/fetch_packages_instruction.dart';
import 'package:create/src/trains/schedule/destination/schedule_instruction.dart';
import 'package:create/src/trains/schedule/glob_match.dart';
import 'package:create/src/trains/schedule/hat/train_hat_info.dart';
import 'package:create/src/trains/schedule/hat/train_hat_info_reload_listener.dart';
import 'package:create/src/trains/schedule/schedule.dart';
import 'package:create/src/trains/schedule/schedule_edit_packet.dart';
import 'package:create/src/trains/schedule/schedule_entry.dart';
import 'package:create/src/trains/schedule/schedule_item.dart';
import 'package:create/src/trains/schedule/schedule_level.dart';
import 'package:create/src/trains/schedule/schedule_menu.dart';
import 'package:create/src/trains/schedule/schedule_runtime.dart';
import 'package:create/src/trains/schedule/schedule_services.dart';
import 'package:create/src/trains/schedule/train_edit_packet.dart';
import 'package:create/src/trains/station/global_package_port.dart';
import 'package:create/src/trains/station/global_station.dart';
import 'package:create/src/trains/track/track_material.dart';
import 'package:create/src/trains/util/ctag.dart';
import 'package:test/test.dart';

/// A [ScheduleLevel] with settable answers.
class FakeLevel implements ScheduleLevel {
  @override
  int overworldClockTime = 0;
  @override
  bool hasServer = true;
  final Set<String> dimensions = {'minecraft:overworld'};
  final Set<(String, Pos)> loaded = {};
  final Set<(String, Pos)> powered = {};
  @override
  ScheduleFilters filters = const PlainScheduleFilters();
  @override
  RedstoneLinkNetworkHandler? redstoneLinks;

  @override
  SchedulePortInventories get ports => throw UnimplementedError();

  @override
  bool hasDimension(String dimension) => dimensions.contains(dimension);
  @override
  bool isLoaded(String dimension, Pos pos) => loaded.contains((dimension, pos));
  @override
  bool hasNeighborSignal(String dimension, Pos pos) => powered.contains((dimension, pos));
  @override
  bool isPositionEntityTicking(String dimension, Pos pos) => loaded.contains((dimension, pos));
}

/// A carriage cargo with settable contents.
class FakeCargo implements CarriageStorage {
  List<CargoItem> items = [];
  List<CargoFluid> fluids = [];
  int version = 0;
  int idle = 0;
  bool resetCalled = false;

  @override
  List<CargoItem> getAllItems() => items;
  @override
  List<CargoFluid> getFluids() => fluids;
  @override
  int getVersion() => version;
  @override
  int getTicksSinceLastExchange() => idle;
  @override
  void resetIdleCargoTracker() {
    resetCalled = true;
    idle = 0;
  }

  @override
  void tickIdleCargoTracker() {
    idle++;
  }

  @override
  void write(CTag tag, bool spawnPacket) {}
  @override
  void read(CTag tag, bool spawnPacket) {}
  @override
  int extractFuel() => 0;
}

Train makeTrain({int carriages = 0, bool conductor = true}) {
  final block = AbstractBogeyBlock.byKey('create:small_bogey') ?? StandardBogeyBlock.registerStandardBlocks().first;
  final list = <Carriage>[];
  for (var i = 0; i < carriages; i++) {
    final c = Carriage(CarriageBogey(block, false, null), CarriageBogey(block, false, null), 3);
    c.storage = FakeCargo();
    if (conductor) c.presentConductors = Couple.create(true, true);
    list.add(c);
  }
  return Train(
    '00000000-0000-4000-8000-00000000000${carriages + 1}',
    null,
    null,
    list,
    <int>[for (var i = 1; i < carriages; i++) 3],
    false,
    0,
  );
}

ScheduleEntry entry(ScheduleInstruction i, [List<List<ScheduleWaitCondition>> conditions = const []]) =>
    ScheduleEntry(i, [for (final c in conditions) List.of(c)]);

DestinationInstruction destination(String name) => DestinationInstruction()..data.putString('Text', name);

ScheduledDelay delay(int value, TimeUnit unit) => ScheduledDelay()
  ..data.putInt('Value', value)
  ..data.putInt('TimeUnit', unit.index);

void main() {
  setUp(() => Schedule.ensureRegistered());

  group('registries', () {
    test('ids equal the Java ones and are registered in order', () {
      expect(
        [for (final p in Schedule.INSTRUCTION_TYPES) p.first],
        [
          'create:destination',
          'create:package_delivery',
          'create:package_retrieval',
          'create:rename',
          'create:throttle',
        ],
      );
      expect(
        [for (final p in Schedule.CONDITION_TYPES) p.first],
        [
          'create:delay',
          'create:time_of_day',
          'create:fluid_threshold',
          'create:item_threshold',
          'create:redstone_link',
          'create:player_count',
          'create:idle',
          'create:unloaded',
          'create:powered',
        ],
      );
      for (final p in Schedule.INSTRUCTION_TYPES) {
        expect(p.second().getId(), p.first);
      }
      for (final p in Schedule.CONDITION_TYPES) {
        expect(p.second().getId(), p.first);
      }
    });
  });

  group('NBT layout', () {
    test('instruction: {Id, Data}', () {
      final i = destination('Central*');
      final tag = i.write();
      expect(tag.getString('Id'), 'create:destination');
      expect(tag.getCompound('Data').getString('Text'), 'Central*');
      final back = ScheduleInstruction.fromTag(tag);
      expect(back, isA<DestinationInstruction>());
      expect((back as DestinationInstruction).getFilter(), 'Central*');
    });

    test('unknown instruction falls back to a destination, unknown condition is null', () {
      final tag = CTag()
        ..putString('Id', 'create:nope')
        ..putCompound('Data', CTag());
      expect(ScheduleInstruction.fromTag(tag), isA<DestinationInstruction>());
      expect(ScheduleWaitCondition.fromTag(tag), isNull);
    });

    test('the throttle instruction defaults to 100', () {
      final t = ChangeThrottleInstruction();
      expect(t.write().getCompound('Data').getInt('Value'), 100);
      expect(t.getThrottle(), 1.0);
      t.data.putInt('Value', 55);
      expect(t.getThrottle(), closeTo(0.55, 1e-6));
      expect(t.getThrottle(), isNot(0.55)); // a float
    });

    test('defaults of the conditions', () {
      final d = ScheduledDelay();
      expect(d.getData().getInt('Value'), 5);
      expect(d.getData().getInt('TimeUnit'), TimeUnit.SECONDS.index);
      expect(d.totalWaitTicks(), 100);
      final t = TimeOfDayCondition();
      expect(t.getData().getInt('Hour'), 8);
      expect(t.getData().getInt('Rotation'), 5);
      expect(t.getRotation(), 2000);
      final i = ItemThresholdCondition();
      expect(i.getData().getString('Threshold'), '10');
      expect(i.slotsTargeted(), 1);
      expect(RedstoneLinkCondition().slotsTargeted(), 2);
    });

    test('schedule: Entries, Cyclic and Progress only when positive', () {
      final s = Schedule.of(
        [
          entry(destination('A'), [
            [delay(5, TimeUnit.SECONDS), delay(1, TimeUnit.MINUTES)],
            [StationPoweredCondition()],
          ]),
          entry(ChangeTitleInstruction()..data.putString('Text', 'Line 1')),
        ],
        true,
        0,
      );
      var tag = s.write();
      expect(tag.contains('Progress'), isFalse);
      expect(tag.getBoolean('Cyclic'), isTrue);
      final entries = tag.getCompoundList('Entries');
      expect(entries, hasLength(2));
      expect(entries[0].getCompound('Instruction').getString('Id'), 'create:destination');
      final conditions = entries[0].getList('Conditions');
      expect(conditions, hasLength(2));
      expect(conditions[0].kind, NbtKind.list);
      expect((conditions[0].value as List<NbtValue>), hasLength(2));
      // the rename instruction takes no conditions: the key is not written
      expect(entries[1].contains('Conditions'), isFalse);

      s.savedProgress = 1;
      tag = s.write();
      expect(tag.getInt('Progress'), 1);
      final back = Schedule.fromTag(tag);
      expect(back.savedProgress, 1);
      expect(back.cyclic, isTrue);
      expect(back.entries, hasLength(2));
      expect(back.entries[0].conditions.map((c) => c.length), [2, 1]);
      expect(back.entries[0].conditions[0][1], isA<ScheduledDelay>());
      expect((back.entries[0].conditions[0][1] as ScheduledDelay).totalWaitTicks(), 60 * 20);
      expect(back.entries[1].instruction, isA<ChangeTitleInstruction>());
    });

    test('an empty tag is a non cyclic empty schedule; clone copies', () {
      final s = Schedule.fromTag(CTag());
      expect(s.entries, isEmpty);
      expect(s.cyclic, isFalse);
      final e = entry(destination('X'), [
        [delay(3, TimeUnit.TICKS)],
      ]);
      final c = e.clone();
      (c.instruction as DestinationInstruction).data.putString('Text', 'Y');
      expect((e.instruction as DestinationInstruction).getFilter(), 'X');
      expect(c.conditions[0][0], isNot(same(e.conditions[0][0])));
    });

    test('wire form of the edit packet round trips and survives network NBT', () {
      final s = Schedule.of(
        [
          entry(destination('A'), [
            [delay(5, TimeUnit.SECONDS)],
          ]),
          entry(ChangeThrottleInstruction()..data.putInt('Value', 50)),
        ],
        false,
        1,
      );
      final fields = ScheduleEditPacket(s).toFields();
      // through the bytes of the nbt tags
      final wire = (fields['schedule']! as Map<String, Object?>);
      final entries = (wire['entries']! as List<Object?>).cast<Map<String, Object?>>();
      for (final e in entries) {
        final instruction = e['instruction']! as NbtValue;
        e['instruction'] = NetworkNbt.decode(NetworkNbt.encode(instruction));
      }
      final packet = ScheduleEditPacket.fromFields(fields);
      expect(packet.schedule.cyclic, isFalse);
      expect(packet.schedule.savedProgress, 1);
      expect(packet.schedule.entries, hasLength(2));
      expect(packet.scheduleComponent(), isNotNull);
      expect(ScheduleEditPacket(Schedule()).scheduleComponent(), isNull);
    });

    test('the item component encodes and decodes', () {
      final s = Schedule.of([entry(destination('Home'))], true, 0);
      final bytes = ScheduleItem.encodeSchedule(s);
      final back = ScheduleItem.getSchedule(bytes)!;
      expect((back.entries.single.instruction as DestinationInstruction).getFilter(), 'Home');
      expect(ScheduleItem.getSchedule(null), isNull);
    });

    test('item thresholds keep their filter item and the frequencies their stacks', () {
      final item = ItemThresholdCondition()
        ..data.putString('Threshold', '64')
        ..setItem(
          0,
          CTag()
            ..putString('id', 'minecraft:iron_ingot')
            ..putInt('count', 1),
        );
      final back = ScheduleWaitCondition.fromTag(item.write())! as ItemThresholdCondition;
      expect(back.getItem(0).getString('id'), 'minecraft:iron_ingot');
      expect(back.getThreshold(), 64);

      final link = RedstoneLinkCondition()
        ..setItem(
          0,
          CTag()
            ..putString('id', 'minecraft:redstone')
            ..putInt('count', 7),
        )
        ..setItem(
          1,
          CTag()
            ..putString('id', 'minecraft:coal')
            ..putInt('count', 1),
        );
      expect(link.freq.first, Frequency.of('minecraft:redstone'));
      final written = link.write().getCompound('Data').getCompoundList('Frequency');
      expect(written, hasLength(2));
      expect(written[0].getInt('count'), 1);
      final backLink = ScheduleWaitCondition.fromTag(link.write())! as RedstoneLinkCondition;
      expect(backLink.freq.second, Frequency.of('minecraft:coal'));
      expect(backLink.freq.first, Frequency.of('minecraft:redstone'));
    });
  });

  group('glob filters', () {
    bool matches(String filter, String name) => javaMatches(destination(filter).getFilterForRegex(), name);

    test('wildcards, sets and groups', () {
      expect(matches('Central Station', 'Central Station'), isTrue);
      expect(matches('Central*', 'Central Station'), isTrue);
      expect(matches('*Station', 'Central Station'), isTrue);
      expect(matches('Central', 'Central Station'), isFalse);
      expect(matches('Stop ?', 'Stop 7'), isTrue);
      expect(matches('Stop ?', 'Stop 77'), isFalse);
      expect(matches('Stop [0-9]', 'Stop 5'), isTrue);
      expect(matches('Stop [0-9]', 'Stop x'), isFalse);
      expect(matches('{North,South} Gate', 'South Gate'), isTrue);
      expect(matches('{North,South} Gate', 'East Gate'), isFalse);
      expect(matches('A.B', 'A.B'), isTrue);
      expect(matches('A.B', 'AxB'), isFalse);
    });

    test('a malformed glob only matches the empty name', () {
      expect(matches('Bad [', ''), isTrue);
      expect(matches('Bad [', 'Bad ['), isFalse);
    });

    test('package retrieval treats a blank filter as everything', () {
      final f = FetchPackagesInstruction();
      expect(javaMatches(f.getFilterForRegex(), 'anything'), isTrue);
      f.data.putString('Text', 'Shop*');
      expect(javaMatches(f.getFilterForRegex(), 'Shop 3'), isTrue);
      expect(javaMatches(f.getFilterForRegex(), 'Mall'), isFalse);
    });

    test('package addresses match like PackageItem.matchAddress', () {
      expect(matchPackageAddress('', ' '), isTrue);
      expect(matchPackageAddress('x', ''), isFalse);
      expect(matchPackageAddress('Shop', '*'), isTrue);
      expect(matchPackageAddress('Shop 1', 'Shop*'), isTrue);
      expect(matchPackageAddress('Shop*', 'Shop 1'), isTrue);
      expect(matchPackageAddress('Home', 'Shop'), isFalse);
    });
  });

  group('timed conditions', () {
    test('scheduled delay counts ticks and completes', () {
      final c = delay(3, TimeUnit.TICKS);
      final train = makeTrain();
      final level = FakeLevel();
      final ctx = CTag();
      var ticks = 0;
      while (!c.tickCompletion(level, train, ctx)) {
        ticks++;
        expect(ticks, lessThan(10));
      }
      expect(ticks, 3);
      expect(ctx.getInt('Time'), 3);
    });

    test('status updates are requested every 5 seconds, then every minute', () {
      final c = delay(2, TimeUnit.MINUTES); // 2400 ticks
      final train = makeTrain();
      final ctx = CTag();
      c.tickCompletion(FakeLevel(), train, ctx); // time 0: 2400 left, a multiple of 1200
      expect(ctx.getInt('StatusVersion'), 1);
      for (var i = 0; i < 1199; i++) {
        c.tickCompletion(FakeLevel(), train, ctx);
      }
      expect(ctx.getInt('StatusVersion'), 1);
      c.tickCompletion(FakeLevel(), train, ctx); // time 1200: 1200 left
      expect(ctx.getInt('StatusVersion'), 2);
    });

    test('waiting status text of the delay', () {
      final train = makeTrain();
      final c = delay(30, TimeUnit.SECONDS); // 600 ticks
      expect(c.getWaitingStatus(FakeLevel(), train, CTag()..putInt('Time', 0)).plain, 'Departs in 30 Seconds');
      expect(c.getWaitingStatus(FakeLevel(), train, CTag()..putInt('Time', 500)).plain, 'Departs in 5 Seconds');
      expect(c.getWaitingStatus(FakeLevel(), train, CTag()..putInt('Time', 580)).plain, 'Departs in 5 Seconds');
      expect(c.getWaitingStatus(FakeLevel(), train, CTag()..putInt('Time', 599)).plain, 'Departs in 5 Seconds');
      final m = delay(3, TimeUnit.MINUTES);
      expect(m.getWaitingStatus(FakeLevel(), train, CTag()).plain, 'Departs in 3 Minutes');
      expect(m.getWaitingStatus(FakeLevel(), train, CTag()..putInt('Time', 3600 - 1200)).plain, 'Departs in 1 Minute');
    });

    test('idle cargo waits for the quietest carriage', () {
      final train = makeTrain(carriages: 2);
      (train.carriages[0].storage as FakeCargo).idle = 300;
      (train.carriages[1].storage as FakeCargo).idle = 50;
      final c = IdleCargoCondition()
        ..data.putInt('Value', 100)
        ..data.putInt('TimeUnit', TimeUnit.TICKS.index);
      final ctx = CTag();
      expect(c.tickCompletion(FakeLevel(), train, ctx), isFalse);
      expect(ctx.getInt('Time'), 50);
      (train.carriages[1].storage as FakeCargo).idle = 101;
      expect(c.tickCompletion(FakeLevel(), train, ctx), isTrue);
    });
  });

  group('time of day', () {
    final train = makeTrain();

    test('completes in the 40 tick window after the target', () {
      final c = TimeOfDayCondition()
        ..data.putInt('Hour', 8)
        ..data.putInt('Minute', 0)
        ..data.putInt('Rotation', 0); // every 24 hours
      // target ticks = ((8 + 18) % 24) * 1000 = 2000
      final level = FakeLevel();
      level.overworldClockTime = 24000 * 3 + 1999;
      expect(c.tickCompletion(level, train, CTag()), isFalse);
      level.overworldClockTime = 24000 * 3 + 2000;
      expect(c.tickCompletion(level, train, CTag()), isTrue);
      level.overworldClockTime = 24000 * 3 + 2040;
      expect(c.tickCompletion(level, train, CTag()), isTrue);
      level.overworldClockTime = 24000 * 3 + 2041;
      expect(c.tickCompletion(level, train, CTag()), isFalse);
    });

    test('minutes round up like the float arithmetic of Java', () {
      final c = TimeOfDayCondition()
        ..data.putInt('Hour', 6)
        ..data.putInt('Minute', 30)
        ..data.putInt('Rotation', 0);
      // (6+18)%24 = 0; 30/60f*1000 = 500
      expect(c.targetTicks(24000), 500);
      c.data.putInt('Minute', 59); // 983.33 -> 984
      expect(c.targetTicks(24000), 984);
      c.data.putInt('Minute', 1); // 16.67 -> 17
      expect(c.targetTicks(24000), 17);
    });

    test('rotation table', () {
      final c = TimeOfDayCondition();
      final expected = [24000, 12000, 6000, 4000, 3000, 2000, 1000, 750, 500, 250];
      for (var i = 0; i < expected.length; i++) {
        c.data.putInt('Rotation', i);
        expect(c.getRotation(), expected[i]);
      }
    });

    test('waiting status shows the departure time', () {
      final c = TimeOfDayCondition()
        ..data.putInt('Hour', 8)
        ..data.putInt('Minute', 0)
        ..data.putInt('Rotation', 0);
      final level = FakeLevel()..overworldClockTime = 1000;
      // departure at tick 2000 -> 8:00 am
      expect(c.getWaitingStatus(level, train, CTag()).plain, 'Departs at 8:00 am');
      c.data.putInt('Hour', 20);
      c.data.putInt('Minute', 15);
      // target ((20+18)%24)*1000 + 250 = 14250 -> hour (14+6)%24 = 20, minute 15 -> 8:15 pm
      expect(c.getWaitingStatus(level, train, CTag()).plain, 'Departs at 8:15 pm');
      expect(c.getDigitalDisplay(0, 5, true).plain, '12:05 am');
    });
  });

  group('cargo thresholds', () {
    test('item count and stacks', () {
      final train = makeTrain(carriages: 2);
      (train.carriages[0].storage as FakeCargo).items = [
        const CargoItem('minecraft:iron_ingot', 64),
        const CargoItem('minecraft:iron_ingot', 10),
        const CargoItem('minecraft:coal', 64),
        CargoItem.empty,
      ];
      (train.carriages[1].storage as FakeCargo)
        ..items = [const CargoItem('minecraft:iron_ingot', 30)]
        ..version = 5;
      final c = ItemThresholdCondition()
        ..data.putString('Threshold', '100')
        ..data.putInt('Operator', Ops.GREATER.index)
        ..setItem(0, CTag()..putString('id', 'minecraft:iron_ingot'));
      final ctx = CTag();
      // 64 + 10 + 30 = 104 > 100
      expect(c.tickCompletion(FakeLevel(), train, ctx), isTrue);
      expect(ctx.getInt('CurrentDisplay'), 104);
      expect(c.getWaitingStatus(FakeLevel(), train, ctx).plain, 'Cargo: 104/101 Items');

      // stacks: only full stacks count
      c.data.putInt('Measure', 1);
      c.data.putString('Threshold', '1');
      c.data.putInt('Operator', Ops.EQUAL.index);
      final ctx2 = CTag();
      expect(c.tickCompletion(FakeLevel(), train, ctx2), isTrue);
      expect(ctx2.getInt('CurrentDisplay'), 1);
      expect(c.getWaitingStatus(FakeLevel(), train, ctx2).plain, 'Cargo: 1/1 Stacks');
    });

    test('an empty filter counts everything; invalid thresholds read as 0', () {
      final train = makeTrain(carriages: 1);
      (train.carriages[0].storage as FakeCargo).items = [const CargoItem('minecraft:coal', 7)];
      final c = ItemThresholdCondition()
        ..data.putString('Threshold', 'abc')
        ..data.putInt('Operator', Ops.LESS.index);
      expect(c.getThreshold(), 0);
      expect(c.getData().getString('Threshold'), '0');
      c.data.putString('Threshold', '8');
      expect(c.tickCompletion(FakeLevel(), train, CTag()), isTrue);
    });

    test('lazy ticking: evaluated every 20 ticks and only when the cargo changed', () {
      final train = makeTrain(carriages: 1);
      final cargo = train.carriages[0].storage as FakeCargo;
      final c = ItemThresholdCondition()
        ..data.putString('Threshold', '5')
        ..data.putInt('Operator', Ops.GREATER.index);
      final ctx = CTag();
      cargo.items = [const CargoItem('minecraft:coal', 3)];
      expect(c.tickCompletion(FakeLevel(), train, ctx), isFalse); // evaluated (LastChecked -1 -> 0)
      expect(ctx.getInt('LastChecked'), 0);
      cargo.items = [const CargoItem('minecraft:coal', 30)];
      for (var i = 0; i < 25; i++) {
        expect(
          c.tickCompletion(FakeLevel(), train, ctx),
          isFalse,
          reason: 'tick $i: not evaluated or unchanged version',
        );
      }
      cargo.version = 1;
      var done = false;
      for (var i = 0; i < 25 && !done; i++) {
        done = c.tickCompletion(FakeLevel(), train, ctx);
      }
      expect(done, isTrue);
    });

    test('fluids are counted in buckets', () {
      final train = makeTrain(carriages: 1);
      (train.carriages[0].storage as FakeCargo).fluids = [
        const CargoFluid('minecraft:water', 2500),
        const CargoFluid('minecraft:lava', 1000),
      ];
      final c = FluidThresholdCondition()
        ..data.putString('Threshold', '3')
        ..data.putInt('Operator', Ops.GREATER.index);
      final ctx = CTag();
      expect(c.tickCompletion(FakeLevel(), train, ctx), isTrue); // 3500 mB > 3000
      expect(ctx.getInt('CurrentDisplay'), 3);
      expect(c.getWaitingStatus(FakeLevel(), train, ctx).plain, 'Cargo: 3/4 Buckets');
      c.setItem(0, CTag()..putString('id', 'minecraft:water'));
      expect(c.writeAndRead().getItem(0).getString('id'), 'minecraft:water');
      final ctx2 = CTag();
      train.carriages[0].storage as FakeCargo;
      (train.carriages[0].storage as FakeCargo).version = 9;
      expect(c.tickCompletion(FakeLevel(), train, ctx2), isFalse); // 2500 mB
      expect(ctx2.getInt('CurrentDisplay'), 2);
    });

    test('operators', () {
      expect(Ops.GREATER.test(2, 1), isTrue);
      expect(Ops.GREATER.test(1, 1), isFalse);
      expect(Ops.LESS.test(0, 1), isTrue);
      expect(Ops.EQUAL.test(1, 1), isTrue);
      expect([for (final o in Ops.values) o.formatted], ['>', '<', '=']);
    });
  });

  group('other conditions', () {
    test('redstone link follows the network power and the inverted flag', () {
      final handler = RedstoneLinkNetworkHandler(linkRange: () => 256);
      final key = Couple<Frequency>(Frequency.of('minecraft:redstone'), Frequency.of('minecraft:coal'));
      final tx = _Link((0, 64, 0), key, 15);
      handler.addToNetwork('minecraft:overworld', tx);
      final c = RedstoneLinkCondition()
        ..setItem(0, CTag()..putString('id', 'minecraft:redstone'))
        ..setItem(1, CTag()..putString('id', 'minecraft:coal'));
      final level = FakeLevel()..redstoneLinks = handler;
      final train = makeTrain();
      final ctx = CTag();
      expect(c.tickCompletion(level, train, ctx), isTrue);
      expect(ctx.getInt('LastChecked'), handler.globalPowerVersion);
      // unchanged power version: nothing re-evaluated
      expect(c.tickCompletion(level, train, ctx), isFalse);
      c.data.putInt('Inverted', 1);
      tx.strength = 0;
      handler.updateNetworkOf('minecraft:overworld', tx);
      expect(c.tickCompletion(level, train, ctx), isTrue);
      expect(RedstoneLinkCondition().tickCompletion(FakeLevel(), train, CTag()), isFalse);
    });

    test('powered and unloaded need a current station', () {
      final train = makeTrain();
      expect(StationPoweredCondition().tickCompletion(FakeLevel(), train, CTag()), isFalse);
      expect(StationUnloadedCondition().tickCompletion(FakeLevel(), train, CTag()), isFalse);
      expect(StationPoweredCondition().getWaitingStatus(FakeLevel(), train, CTag()).plain, 'Waiting for redstone');
      expect(StationUnloadedCondition().getWaitingStatus(FakeLevel(), train, CTag()).plain, 'Waiting for chunk unload');
    });

    test('player count', () {
      final train = makeTrain();
      final c = PlayerPassengerCondition()
        ..data.putInt('Count', 0)
        ..data.putInt('Exact', 0);
      final ctx = CTag();
      expect(c.tickCompletion(FakeLevel(), train, ctx), isTrue);
      c.data.putInt('Count', 2);
      expect(c.tickCompletion(FakeLevel(), train, ctx), isFalse);
      expect(c.getWaitingStatus(FakeLevel(), train, ctx).plain, 'Passengers: 0/2');
      expect(c.canOvershoot(), isFalse);
      c.data.putInt('Exact', 1);
      expect(c.canOvershoot(), isTrue);
    });
  });

  group('runtime', () {
    test('write / read keep the whole state', () {
      final train = makeTrain();
      final rt = train.runtime;
      final s = Schedule.of(
        [
          entry(destination('A'), [
            [delay(5, TimeUnit.SECONDS)],
            [delay(1, TimeUnit.MINUTES)],
          ]),
          entry(destination('B')),
        ],
        true,
        1,
      );
      rt.setSchedule(s, true);
      expect(rt.currentEntry, 1);
      expect(rt.paused, isFalse);
      expect(rt.predictionTicks, [-1, -1]);
      rt.state = State.POST_TRANSIT;
      rt.conditionProgress = [1, 0];
      rt.conditionContext = [CTag()..putInt('Time', 4), CTag()];
      rt.predictionTicks = [200, -1];

      final tag = rt.write();
      expect(tag.getString('State'), 'POST_TRANSIT');
      expect(tag.getIntArray('ConditionProgress'), [1, 0]);
      expect(tag.getIntArray('TransitTimes'), [200, -1]);
      expect(tag.getBoolean('AutoSchedule'), isTrue);
      expect(tag.getCompoundList('ConditionContext'), hasLength(2));

      final other = makeTrain().runtime;
      other.read(tag);
      expect(other.state, State.POST_TRANSIT);
      expect(other.currentEntry, 1);
      expect(other.isAutoSchedule, isTrue);
      expect(other.paused, isFalse);
      expect(other.conditionProgress, [1, 0]);
      expect(other.conditionContext[0].getInt('Time'), 4);
      expect(other.predictionTicks, [200, -1]);
      expect(other.schedule!.entries, hasLength(2));
    });

    test('read ignores transit times of another length', () {
      final rt = makeTrain().runtime;
      final tag = (makeTrain().runtime..setSchedule(Schedule.of([entry(destination('A'))], true, 0), false)).write();
      tag.putIntArray('TransitTimes', [1, 2, 3]);
      rt.read(tag);
      expect(rt.predictionTicks, [-1]);
    });

    test('rename and throttle run through without a path', () {
      final train = makeTrain();
      final rt = train.runtime;
      rt.setSchedule(
        Schedule.of(
          [
            entry(ChangeTitleInstruction()..data.putString('Text', 'Express')),
            entry(ChangeThrottleInstruction()..data.putInt('Value', 50)),
          ],
          false,
          0,
        ),
        false,
      );
      final level = FakeLevel();
      rt.tick(level);
      expect(rt.currentTitle, 'Express');
      expect(rt.currentEntry, 1);
      rt.tick(level);
      expect(train.throttle, closeTo(0.5, 1e-6));
      expect(rt.currentEntry, 2);
      // the end of a non cyclic schedule pauses and completes it
      rt.tick(level);
      expect(rt.paused, isTrue);
      expect(rt.completed, isTrue);
      expect(rt.currentEntry, 0);
    });

    test('a cyclic schedule wraps around', () {
      final train = makeTrain();
      final rt = train.runtime;
      rt.setSchedule(Schedule.of([entry(ChangeThrottleInstruction())], true, 0), false);
      final level = FakeLevel();
      rt.tick(level);
      expect(rt.currentEntry, 1);
      rt.tick(level);
      expect(rt.currentEntry, 0);
      expect(rt.paused, isFalse);
    });

    test('a train without a conductor waits and cools down', () {
      final train = makeTrain(carriages: 1, conductor: false);
      final rt = train.runtime;
      rt.setSchedule(Schedule.of([entry(destination('A'))], true, 0), false);
      final level = FakeLevel();
      rt.tick(level);
      expect(train.status.conductor, isTrue); // missingConductor was reported
      expect(rt.currentEntry, 0);
      // the cooldown (40 ticks) blocks the next attempt
      train.status.conductor = false;
      for (var i = 0; i < 39; i++) {
        rt.tick(level);
      }
      expect(train.status.conductor, isFalse);
      rt.tick(level);
      rt.tick(level);
      expect(train.status.conductor, isTrue);
    });

    test('conditions run in columns; the first finished column moves on', () {
      final train = makeTrain(carriages: 1);
      final rt = train.runtime;
      rt.setSchedule(
        Schedule.of(
          [
            entry(destination('A'), [
              [delay(5, TimeUnit.TICKS), delay(2, TimeUnit.TICKS)],
              [delay(1, TimeUnit.MINUTES)],
            ]),
            entry(ChangeThrottleInstruction()),
          ],
          true,
          0,
        ),
        false,
      );
      // pretend the train arrived
      rt.state = State.IN_TRANSIT;
      rt.destinationReached();
      expect(rt.state, State.POST_TRANSIT);
      expect(rt.conditionProgress, [0, 0]);
      expect((train.carriages[0].storage as FakeCargo).resetCalled, isTrue);
      final level = FakeLevel();
      var ticks = 0;
      while (rt.state == State.POST_TRANSIT) {
        rt.tick(level);
        ticks++;
        expect(ticks, lessThan(100));
      }
      // 5 ticks + 1 for finishing + 2 ticks + 1, then the finished column is noticed
      expect(rt.state, State.PRE_TRANSIT);
      expect(rt.currentEntry, 1);
      expect(rt.displayLinkUpdateRequested, isTrue);
    });

    test('the waiting status comes from the first column', () {
      final train = makeTrain();
      final rt = train.runtime;
      rt.setSchedule(
        Schedule.of(
          [
            entry(destination('A'), [
              [delay(30, TimeUnit.SECONDS)],
            ]),
          ],
          true,
          0,
        ),
        false,
      );
      expect(rt.getWaitingStatus(FakeLevel()).plain, ''); // no progress yet
      rt.state = State.IN_TRANSIT;
      rt.destinationReached();
      expect(rt.getWaitingStatus(FakeLevel()).plain, 'Departs in 30 Seconds');
    });

    test('returnSchedule saves the progress and gives nothing back for automatic schedules', () {
      final train = makeTrain();
      final rt = train.runtime;
      rt.setSchedule(Schedule.of([entry(destination('A')), entry(destination('B'))], true, 0), false);
      rt.currentEntry = 1;
      final tag = rt.returnSchedule()!;
      expect(tag.getInt('Progress'), 1);
      expect(rt.getSchedule(), isNull);
      expect(rt.paused, isTrue);

      rt.setSchedule(Schedule.of([entry(destination('A'))], true, 0), true);
      expect(rt.returnSchedule(), isNull);
      expect(rt.getSchedule(), isNull);
      expect(rt.returnSchedule(), isNull);
    });

    test('predictions: current station, upcoming ones and unknown times', () {
      final train = makeTrain();
      final rt = train.runtime;
      rt.setSchedule(
        Schedule.of(
          [
            entry(destination('Alpha'), [
              [delay(10, TimeUnit.SECONDS)],
            ]),
            entry(ChangeTitleInstruction()..data.putString('Text', 'Line 2')),
            entry(destination('Beta'), [
              [delay(5, TimeUnit.SECONDS)],
            ]),
          ],
          true,
          0,
        ),
        false,
      );
      rt.predictionTicks = [100, -1, 400];
      // no current station and not navigating: predictForEntry of the current entry
      final predictions = rt.submitPredictions();
      expect(predictions, isNotEmpty);
    });

    test('transitInterrupted goes back to PRE_TRANSIT', () {
      final rt = makeTrain().runtime;
      rt.setSchedule(Schedule.of([entry(destination('A'))], true, 0), false);
      rt.state = State.IN_TRANSIT;
      rt.transitInterrupted();
      expect(rt.state, State.PRE_TRANSIT);
      rt.state = State.POST_TRANSIT;
      rt.transitInterrupted();
      expect(rt.state, State.POST_TRANSIT);
    });
  });

  group('packages', () {
    test('delivery with no packages skips the entry', () {
      final train = makeTrain(carriages: 1);
      final rt = train.runtime;
      rt.setSchedule(
        Schedule.of([entry(DeliverPackagesInstruction()), entry(ChangeThrottleInstruction())], false, 0),
        false,
      );
      rt.tick(FakeLevel());
      expect(rt.currentEntry, 1);
      expect(rt.state, State.PRE_TRANSIT);
    });

    test('retrieval without a server does nothing; without stations it skips', () {
      final train = makeTrain(carriages: 1);
      final rt = train.runtime;
      rt.setSchedule(
        Schedule.of([entry(FetchPackagesInstruction()), entry(ChangeThrottleInstruction())], false, 0),
        false,
      );
      final noServer = FakeLevel()..hasServer = false;
      expect(FetchPackagesInstruction().start(rt, noServer), isNull);
      expect(rt.currentEntry, 0);
    });
  });

  group('station and offline buffer', () {
    CTag packageStack() => CTag()
      ..putString('id', 'create:cardboard_package_12x12')
      ..putInt('count', 1);

    CTag ingots(int count) => CTag()
      ..putString('id', 'minecraft:iron_ingot')
      ..putInt('count', count);

    test('the offline buffer keeps packages one per slot', () {
      // `CreateItemStackHandler.getCapacity` caps a slot at the item's own stack size, so the
      // (max stack 1) packages never merge; ordinary items still stack to 64.
      final buffer = OfflineBuffer();
      expect(buffer.insertItemStacked(packageStack()), isNull);
      expect(buffer.insertItemStacked(packageStack()), isNull);
      expect(buffer.getStackInSlot(0)!.getInt('count'), 1);
      expect(buffer.getStackInSlot(1)!.getInt('count'), 1);

      expect(buffer.insertItemStacked(ingots(70)), isNull);
      expect(buffer.getStackInSlot(2)!.getInt('count'), 64);
      expect(buffer.getStackInSlot(3)!.getInt('count'), 6);

      // a full buffer hands the remainder back instead of merging over the limit
      final full = OfflineBuffer(1)..setStackInSlot(0, ingots(64));
      final rest = full.insertItemStacked(ingots(5))!;
      expect(rest.getInt('count'), 5);
      expect(full.getStackInSlot(0)!.getInt('count'), 64);
    });

    test('the offline buffer round-trips the Size/Items layout of the Java handler', () {
      final buffer = OfflineBuffer()
        ..setStackInSlot(3, ingots(5))
        ..setStackInSlot(0, packageStack());
      final tag = buffer.serializeNBT();
      expect(tag.getInt('Size'), 18);
      final items = tag.getCompoundList('Items');
      expect([for (final i in items) i.getInt('Slot')], [0, 3]);
      expect(items.first.getString('id'), 'create:cardboard_package_12x12');

      final back = OfflineBuffer()..deserializeNBT(tag);
      expect(back.getSlots(), 18);
      expect(back.getStackInSlot(0)!.getString('id'), 'create:cardboard_package_12x12');
      expect(back.getStackInSlot(3)!.getInt('count'), 5);
      expect(back.getStackInSlot(3)!.contains('Slot'), isFalse);

      // a saved Size resizes the buffer, out of range slots are dropped
      back.deserializeNBT(
        CTag()
          ..putInt('Size', 2)
          ..putCompoundList('Items', [
            CTag()
              ..putInt('Slot', 1)
              ..putString('id', 'minecraft:stone')
              ..putInt('count', 3),
            CTag()
              ..putInt('Slot', 7)
              ..putString('id', 'minecraft:dirt')
              ..putInt('count', 1),
          ]),
      );
      expect(back.getSlots(), 2);
      expect(back.getStackInSlot(1)!.getString('id'), 'minecraft:stone');
    });

    test('a station reserves the nearest train and reports arrival and departure', () {
      final graph = TrackGraph('00000000-0000-4000-8000-0000000000f1');
      final a = TrackNode(TrackNodeLocation(0, 0, 0).inDimension(overworldId), 1, (0.0, 1.0, 0.0));
      final b = TrackNode(TrackNodeLocation(0, 0, 20).inDimension(overworldId), 2, (0.0, 1.0, 0.0));
      graph
        ..addNode(a)
        ..addNode(b);
      final edge = TrackEdge(a, b, null, TrackMaterial.ANDESITE);
      graph
        ..putConnection(a, b, edge)
        ..putConnection(b, a, TrackEdge(b, a, null, TrackMaterial.ANDESITE));
      final station = GlobalStation()
        ..setId('00000000-0000-4000-8000-0000000000f3')
        ..setLocation(Couple.create(a.location, b.location), 19.0)
        ..name = 'Central';
      station.setType(EdgePointType.STATION);
      graph.addPoint(EdgePointType.STATION, station);

      final block =
          AbstractBogeyBlock.byKey('create:small_bogey') ?? StandardBogeyBlock.registerStandardBlocks().first;
      Train trainOn(String id) {
        final c = Carriage(CarriageBogey(block, false, null), CarriageBogey(block, false, null), 3);
        c.storage = FakeCargo();
        c.presentConductors = Couple.create(true, true);
        return Train(id, null, graph, [c], <int>[], false, 0);
      }

      final near = trainOn('00000000-0000-4000-8000-0000000000a1')
        ..navigation.distanceToDestination = 10;
      final far = trainOn('00000000-0000-4000-8000-0000000000a2')
        ..navigation.distanceToDestination = 40;

      // `reserveFor` keeps the train that is closest to the station
      station.reserveFor(far);
      station.reserveFor(near);
      station.reserveFor(far);
      expect(station.getNearestTrain(), same(near));

      // `getImminentTrain` only reports a train that is navigating to the station within 30 blocks
      expect(station.getImminentTrain(), isNull);
      near.navigation.destination = station;
      expect(station.getImminentTrain(), same(near));
      near.navigation.distanceToDestination = 31;
      expect(station.getImminentTrain(), isNull);
      near.navigation.distanceToDestination = 10;

      // `getPresentTrain` requires the train to stand at this station
      expect(station.getPresentTrain(), isNull);
      near.setCurrentStation(station);
      expect(station.getPresentTrain(), same(near));
      expect(station.getImminentTrain(), same(near));

      // leaving the station forgets the reservation
      near.leaveStation();
      expect(near.getCurrentStation(), isNull);
      expect(station.getPresentTrain(), isNull);
      expect(station.getNearestTrain(), isNull);

      // an assembling station accepts no approaches and no paths through it
      expect(station.canApproachFrom(b), isTrue);
      expect(station.canNavigateVia(a), isTrue);
      station.assembling = true;
      expect(station.canApproachFrom(b), isFalse);
      expect(station.canNavigateVia(a), isFalse);
    });
  });

  group('item and conductor interaction', () {
    test('handScheduleTo outcomes', () {
      final train = makeTrain();
      final schedule = Schedule.of([entry(destination('A'))], true, 0);
      ScheduleCarriagePassenger p({bool seated = true, bool conductor = true, Train? t}) =>
          ScheduleCarriagePassenger(train: t ?? train, seated: seated, conductorSeat: conductor);
      expect(ScheduleItem.handScheduleTo(null, p()), HandScheduleOutcome.pass);
      expect(ScheduleItem.handScheduleTo(schedule, null), HandScheduleOutcome.pass);
      expect(
        ScheduleItem.handScheduleTo(
          schedule,
          const ScheduleCarriagePassenger(train: null, seated: true, conductorSeat: true),
        ),
        HandScheduleOutcome.success,
      );
      expect(ScheduleItem.handScheduleTo(schedule, p(seated: false)), HandScheduleOutcome.success);
      expect(ScheduleItem.handScheduleTo(schedule, p(conductor: false)), HandScheduleOutcome.nonControllingSeat);
      expect(ScheduleItem.handScheduleTo(Schedule(), p()), HandScheduleOutcome.noStops);
      expect(ScheduleItem.handScheduleTo(schedule, p()), HandScheduleOutcome.applied);
      expect(train.runtime.getSchedule(), same(schedule));
      expect(train.runtime.isAutoSchedule, isFalse);
      expect(ScheduleItem.handScheduleTo(schedule, p()), HandScheduleOutcome.removeWithEmptyHand);
    });

    test('clicking a conductor: resume, deny, take back', () {
      final train = makeTrain();
      final p = ScheduleCarriagePassenger(train: train, seated: true, conductorSeat: true);
      expect(interactWithConductor(p, handEmpty: true).outcome, ConductorClickOutcome.ignore); // no schedule
      train.runtime.setSchedule(Schedule.of([entry(destination('A'))], true, 0), false);
      train.runtime.paused = true;
      expect(interactWithConductor(p, handEmpty: true).outcome, ConductorClickOutcome.resumed);
      expect(train.runtime.paused, isFalse);
      expect(interactWithConductor(p, handEmpty: false).outcome, ConductorClickOutcome.denyHeldItem);
      final back = interactWithConductor(p, handEmpty: true);
      expect(back.outcome, ConductorClickOutcome.returned);
      expect(back.returned, isNotNull);
      expect(back.wasAuto, isFalse);
      expect(train.runtime.getSchedule(), isNull);
      // a completed schedule is not resumed but taken back
      train.runtime.setSchedule(Schedule.of([entry(destination('A'))], false, 0), true);
      train.runtime.paused = true;
      train.runtime.completed = true;
      final auto = interactWithConductor(p, handEmpty: true);
      expect(auto.outcome, ConductorClickOutcome.returned);
      expect(auto.returned, isNull);
      expect(auto.wasAuto, isTrue);
    });

    test('the menu keeps two ghost slots', () {
      final menu = ScheduleMenu('p');
      expect(menu.setGhost(1, const ItemStackData(5, 1)), isTrue);
      expect(menu.setGhost(2, const ItemStackData(5, 1)), isFalse);
      expect(menu.ghostInventory[1].itemId, 5);
      expect(menu.ghostInventory[0].isEmpty, isTrue);
      expect(menu.slotsActive, isTrue);
      expect(menu.targetSlotsActive, 1);
    });
  });

  group('train edit packet', () {
    test('renames, changes icon and colour, and answers', () {
      final train = makeTrain();
      Create.RAILWAYS.trains[train.id] = train;
      addTearDown(() => Create.RAILWAYS.trains.remove(train.id));
      final reply = TrainEditPacket.fromFields({
        'id': train.id,
        'name': 'Orient Express',
        'iconType': 'create:modern',
        'mapColor': 7,
      }).handleServer();
      expect(reply, isNotNull);
      expect(train.name.plain, 'Orient Express');
      expect(train.icon.id, 'create:modern');
      expect(train.mapColorIndex, 7);
      expect(reply!.toFields()['mapColor'], 7);

      // a blank name keeps the old one
      TrainEditPacket(train.id, '  ', 'create:electric', 2).handleServer();
      expect(train.name.plain, 'Orient Express');
      expect(train.icon.id, 'create:electric');
      expect(TrainEditPacket('00000000-0000-4000-8000-0000000000ff', 'x', 'create:modern', 0).handleServer(), isNull);
    });
  });

  group('hat info', () {
    test('parses the JSON of the data files', () {
      final errors = TrainHatInfoReloadListener.registerOffsetOverrides({
        'minecraft:train_hat_info/pig.json': '{"model_part":"body/head","offset":[0.0,3.0,0.0],"scale":0.75}',
        'minecraft:train_hat_info/cow.json': '{"offset":[1,2,3]}',
        'minecraft:train_hat_info/bad.json': '{"model_part":"x"}',
        'minecraft:train_hat_info/ghost_type.json': '{"offset":[0,0,0]}',
      }, (id) => id != 'minecraft:ghost_type');
      expect(errors, hasLength(2));
      expect(TrainHatInfoReloadListener.size, 2);
      final pig = TrainHatInfoReloadListener.getHatInfoFor('minecraft:pig');
      expect(pig.part, 'body/head');
      expect(pig.offset, (0.0, 3.0, 0.0));
      expect(pig.scale, 0.75);
      final cow = TrainHatInfoReloadListener.getHatInfoFor('minecraft:cow');
      expect(cow.part, '');
      expect(cow.cubeIndex, 0);
      expect(cow.offset, (1.0, 2.0, 3.0));
      expect(cow.scale, 1.0);
      final unknown = TrainHatInfoReloadListener.getHatInfoFor('minecraft:zombie');
      expect(unknown.offset, (0.0, 0.0, 0.0));
      final snow = TrainHatInfoReloadListener.getHatInfoFor('minecraft:snow_golem', snowGolemHasPumpkin: true);
      expect(snow.offset, (0.0, -3.0, 0.0));
      expect(snow.scale, 1.18);
      expect(TrainHatInfoReloadListener.getHatInfoFor('minecraft:snow_golem').scale, 1.0);
    });

    test('the model is value equal', () {
      expect(TrainHatInfo.of('a', 1, (0, 1, 2), 1), TrainHatInfo.of('a', 1, (0, 1, 2), 1));
    });
  });
}

class _Link extends RedstoneLinkable {
  _Link(this.location, this.networkKey, this.strength);

  @override
  Pos location;
  @override
  NetworkKey networkKey;
  int strength;

  @override
  int get transmittedStrength => strength;
  @override
  void setReceivedStrength(int power) {}
  @override
  bool get isListening => false;
  @override
  bool get isAlive => true;
}

extension on FluidThresholdCondition {
  FluidThresholdCondition writeAndRead() => ScheduleWaitCondition.fromTag(write())! as FluidThresholdCondition;
}

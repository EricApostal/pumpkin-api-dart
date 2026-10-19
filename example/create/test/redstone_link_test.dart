import 'package:create/src/common/common.dart';
import 'package:create/src/redstone/link/controller_items.dart';
import 'package:create/src/redstone/link/controller_server.dart';
import 'package:create/src/redstone/link/frequency.dart';
import 'package:create/src/redstone/link/link_network.dart';
import 'package:create/src/redstone/link/link_slots.dart';
import 'package:create/src/protocol/item_stack.dart';
import 'package:test/test.dart';

/// A link for tests: a transmitter or a receiver with a fixed key.
class FakeLink extends RedstoneLinkable {
  FakeLink(this.location, this.networkKey, {this.transmit = 0, this.listening = false, this.alive = true});

  @override
  Pos location;
  @override
  NetworkKey networkKey;
  int transmit;
  bool listening;
  bool alive;
  int received = -1;
  int actorUpdates = 0;

  @override
  int get transmittedStrength => listening ? 0 : transmit;

  @override
  void setReceivedStrength(int power) => received = power;

  @override
  bool get isListening => listening;

  @override
  bool get isAlive => alive;

  @override
  void onActorNetworkUpdate(int power) {
    actorUpdates++;
    if (listening) received = power; // LinkBehaviour: the receiver that triggered the update
  }
}

NetworkKey key(String a, String b) =>
    Couple<Frequency>(Frequency.of('minecraft:$a'), b.isEmpty ? Frequency.empty : Frequency.of('minecraft:$b'));

void main() {
  late RedstoneLinkNetworkHandler handler;
  var range = 256;

  setUp(() {
    range = 256;
    handler = RedstoneLinkNetworkHandler(linkRange: () => range)..onLoadWorld('w');
  });

  group('Frequency', () {
    test('equal by item and colour only', () {
      expect(Frequency.of('minecraft:redstone'), Frequency.of('minecraft:redstone'));
      expect(Frequency.of('minecraft:leather_boots', color: 1), isNot(Frequency.of('minecraft:leather_boots', color: 2)));
      expect(Frequency.of('minecraft:air'), Frequency.empty);
      expect(Frequency.of(null).isEmpty, isTrue);
      expect(Frequency.of('a:b').hashCode, Frequency.of('a:b').hashCode);
    });

    test('network keys are map keys', () {
      final m = {key('a', 'b'): 1};
      expect(m[key('a', 'b')], 1);
      expect(m[key('b', 'a')], isNull);
    });
  });

  group('RedstoneLinkNetworkHandler', () {
    test('a receiver gets the strength of a transmitter on the same key', () {
      final tx = FakeLink((0, 0, 0), key('x', 'y'), transmit: 11);
      final rx = FakeLink((5, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', rx);
      handler.addToNetwork('w', tx);
      expect(rx.received, 11);
    });

    test('other frequencies do not mix', () {
      final tx = FakeLink((0, 0, 0), key('x', 'y'), transmit: 15);
      final rx = FakeLink((1, 0, 0), key('x', 'z'), listening: true);
      handler.addToNetwork('w', rx);
      handler.addToNetwork('w', tx);
      expect(rx.received, 0);
    });

    test('the strongest of several transmitters wins and removal drops it', () {
      final a = FakeLink((0, 0, 0), key('x', 'y'), transmit: 3);
      final b = FakeLink((1, 0, 0), key('x', 'y'), transmit: 9);
      final rx = FakeLink((2, 0, 0), key('x', 'y'), listening: true);
      for (final l in [a, b, rx]) {
        handler.addToNetwork('w', l);
      }
      expect(rx.received, 9);
      handler.removeFromNetwork('w', b);
      expect(rx.received, 3);
    });

    test('updateNetworkOf recomputes when a transmitter changes', () {
      final tx = FakeLink((0, 0, 0), key('x', 'y'), transmit: 4);
      final rx = FakeLink((2, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', tx);
      handler.addToNetwork('w', rx);
      expect(rx.received, 4);
      tx.transmit = 12;
      handler.updateNetworkOf('w', tx);
      expect(rx.received, 12);
      tx.transmit = 0;
      handler.updateNetworkOf('w', tx);
      expect(rx.received, 0);
    });

    test('range: links farther than linkRange do not hear each other', () {
      range = 10;
      final tx = FakeLink((0, 0, 0), key('x', 'y'), transmit: 15);
      final near = FakeLink((9, 0, 0), key('x', 'y'), listening: true);
      final far = FakeLink((10, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', near);
      handler.addToNetwork('w', far);
      // The transmitter joins last: its update reaches the receivers within its range.
      handler.addToNetwork('w', tx);
      expect(near.received, 15);
      expect(far.received, isNot(15)); // closerThan is strict: 10 is not closer than 10
    });

    test('dead linkables are dropped and do not transmit', () {
      final tx = FakeLink((0, 0, 0), key('x', 'y'), transmit: 15);
      final rx = FakeLink((1, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', tx);
      handler.addToNetwork('w', rx);
      expect(rx.received, 15);
      tx.alive = false;
      handler.updateNetworkOf('w', rx);
      expect(handler.getNetworkOf('w', rx), isNot(contains(tx)));
      expect(rx.actorUpdates, greaterThan(0));
    });

    test('the actor itself is told in updateNetworkOf (loading order fix)', () {
      final rx = FakeLink((1, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', rx);
      expect(rx.actorUpdates, 1);
    });

    test('worlds are separate and unloading forgets them', () {
      handler.onLoadWorld('n');
      final a = FakeLink((0, 0, 0), key('x', 'y'), transmit: 7);
      final b = FakeLink((0, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', a);
      handler.addToNetwork('n', b);
      expect(b.received, 0);
      expect(handler.hasAnyLoadedPower(key('x', 'y')), isTrue);
      handler.onUnloadWorld('w');
      expect(handler.hasAnyLoadedPower(key('x', 'y')), isFalse);
    });

    test('globalPowerVersion counts recomputations', () {
      final before = handler.globalPowerVersion;
      handler.addToNetwork('w', FakeLink((0, 0, 0), key('x', 'y')));
      expect(handler.globalPowerVersion, before + 1);
    });
  });

  group('LinkedControllerServerHandler', () {
    test('a pressed button transmits 15 for 30 ticks and a press renews it', () {
      final rx = FakeLink((3, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', rx);
      final ctl = LinkedControllerServerHandler(handler);
      ctl.receivePressed('w', (0, 0, 0), 'p1', [key('x', 'y')], pressed: true);
      expect(rx.received, 15);

      for (var i = 0; i < 29; i++) {
        ctl.tick('w');
      }
      // renewed by the client's repeated input
      ctl.receivePressed('w', (1, 0, 0), 'p1', [key('x', 'y')], pressed: true);
      for (var i = 0; i < 29; i++) {
        ctl.tick('w');
      }
      expect(rx.received, 15);
      ctl.tick('w');
      ctl.tick('w');
      expect(rx.received, 0);
    });

    test('release ends the press at the next tick', () {
      final rx = FakeLink((3, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', rx);
      final ctl = LinkedControllerServerHandler(handler);
      ctl.receivePressed('w', (0, 0, 0), 'p1', [key('x', 'y')], pressed: true);
      ctl.receivePressed('w', (0, 0, 0), 'p1', [key('x', 'y')], pressed: false);
      ctl.tick('w');
      expect(rx.received, 0);
      expect(ctl.receivedInputs, isEmpty);
    });

    test('a release of a button that was never pressed does nothing', () {
      final ctl = LinkedControllerServerHandler(handler);
      ctl.receivePressed('w', (0, 0, 0), 'p1', [key('x', 'y')], pressed: false);
      expect(handler.networksIn('w'), isEmpty);
    });

    test('the receiver callback fires when a press reaches a receiver', () {
      final rx = FakeLink((3, 0, 0), key('x', 'y'), listening: true);
      handler.addToNetwork('w', rx);
      final awarded = <String>[];
      final ctl = LinkedControllerServerHandler(handler, onReceiverActivated: awarded.add);
      ctl.receivePressed('w', (0, 0, 0), 'p1', [key('x', 'y'), key('q', 'y')], pressed: true);
      expect(awarded, ['p1']);
    });
  });

  group('ControllerItems', () {
    final ids = ItemIdResolver.vanilla();

    test('round trips and trims trailing empty slots', () {
      final redstone = ids.idOf('minecraft:redstone')!;
      final items = ControllerItems.empty.withSlot(0, ItemTemplate(redstone)).withSlot(3, ItemTemplate(redstone));
      final bytes = items.encode();
      final back = ControllerItems.decode(bytes);
      expect(back.slots.length, 4);
      expect(back.slot(0), ItemTemplate(redstone));
      expect(back.slot(1), isNull);
      expect(back.frequencyAt(3, ids), Frequency.of('minecraft:redstone'));
      expect(ControllerItems.empty.encode(), [0]);
    });

    test('toFrequency pairs slot 2n and 2n+1', () {
      final a = ids.idOf('minecraft:redstone')!;
      final b = ids.idOf('minecraft:stick')!;
      final items = ControllerItems.empty.withSlot(2, ItemTemplate(a)).withSlot(3, ItemTemplate(b));
      expect(items.toFrequency(1, ids), key('redstone', 'stick'));
      expect(items.toFrequency(0, ids), emptyNetworkKey());
    });

    test('the wire format is list of optional (id, count, patch)', () {
      final a = ids.idOf('minecraft:redstone')!;
      final bytes = ControllerItems([null, ItemTemplate(a)]).encode();
      // size 2; slot 0 absent; slot 1 present, id (VarInt), count 1, empty patch.
      expect(bytes.first, 2);
      expect(bytes[1], 0);
      expect(bytes[2], 1);
      expect(bytes.sublist(bytes.length - 3), [1, 0, 0]);
    });

    test('unreadable bytes give an empty container', () {
      Object? error;
      final r = ControllerItems.decode([5, 1, 1], error: (e) => error = e);
      expect(r.slots, isEmpty);
      expect(error, isNotNull);
    });
  });

  group('Frequency slot geometry', () {
    test('the two slots of a link facing north are 5 pixels apart', () {
      final first = frequencySlotOffset(Direction.north, first: true);
      final second = frequencySlotOffset(Direction.north, first: false);
      expect((first.$2 - second.$2).abs(), closeTo(5 / 16, 1e-6));
    });

    test('a hit on a slot center selects that slot only', () {
      for (final facing in Direction.values) {
        final first = frequencySlotOffset(facing, first: true);
        final second = frequencySlotOffset(facing, first: false);
        expect(frequencySlotHit(facing, first, first: true), isTrue, reason: '$facing first');
        expect(frequencySlotHit(facing, first, first: false), isFalse, reason: '$facing first vs second');
        expect(frequencySlotHit(facing, second, first: false), isTrue, reason: '$facing second');
      }
    });
  });
}

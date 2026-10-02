import 'package:teleport/src/model.dart';
import 'package:test/test.dart';

const home = Location(world: 'minecraft:overworld', x: 10.5, y: 64, z: -3, yaw: 90);

void main() {
  test('locations round trip through JSON', () {
    final copy = Location.fromJson(home.toJson());
    expect(copy.world, home.world);
    expect(copy.x, 10.5);
    expect(copy.yaw, 90);
    expect(home.describe(), 'overworld 10, 64, -3');
  });

  test('config uses defaults for missing values', () {
    final config = TeleportConfig.fromJson({'maxHomes': 5});
    expect(config.maxHomes, 5);
    expect(config.cooldown, const Duration(seconds: 5));
    expect(TeleportConfig.fromJson(config.toJson()).maxHomes, 5);
  });

  test('names', () {
    expect(isValidName('base_1'), isTrue);
    expect(isValidName('my home'), isFalse);
    expect(isValidName(''), isFalse);
    expect(isValidName('x' * 33), isFalse);
  });

  group('homes', () {
    test('are per player and case insensitive', () {
      final book = HomeBook();
      book.set('a', 'Base', home);
      expect(book.get('a', 'base'), isNotNull);
      expect(book.get('b', 'base'), isNull);
      expect(book.count('a'), 1);
      expect(book.has('a', 'BASE'), isTrue);
    });

    test('can be replaced and removed', () {
      final book = HomeBook();
      book.set('a', 'base', home);
      book.set('a', 'BASE', const Location(world: 'w', x: 1, y: 2, z: 3));
      expect(book.count('a'), 1);
      expect(book.get('a', 'base')!.world, 'w');
      expect(book.remove('a', 'Base'), isTrue);
      expect(book.remove('a', 'base'), isFalse);
    });

    test('round trip through JSON', () {
      final book = HomeBook()
        ..set('a', 'one', home)
        ..set('a', 'two', home)
        ..set('b', 'x', home);
      final copy = HomeBook.fromJson(book.toJson({'a': 'Steve'}));
      expect(copy.count('a'), 2);
      expect(copy.get('b', 'x')!.x, 10.5);
      expect(book.toJson({'a': 'Steve'})['a'], containsPair('name', 'Steve'));
    });

    test('players without homes are not written', () {
      final book = HomeBook()..set('a', 'x', home);
      book.remove('a', 'x');
      expect(book.toJson({}), isEmpty);
    });
  });

  test('warps', () {
    final warps = WarpBook()
      ..set('Shop', home)
      ..set('arena', home);
    expect(warps.names, ['arena', 'shop']);
    expect(warps.get('SHOP'), isNotNull);
    final copy = WarpBook.fromJson(warps.toJson());
    expect(copy.names, ['arena', 'shop']);
    expect(warps.remove('shop'), isTrue);
    expect(warps.get('shop'), isNull);
  });

  group('teleport requests', () {
    late DateTime now;
    late TpaRequests requests;

    setUp(() {
      now = DateTime.utc(2026, 1, 1);
      requests = TpaRequests(timeout: const Duration(seconds: 60), now: () => now);
    });

    TpaRequest request(String from, String to, [TpaKind kind = TpaKind.to]) =>
        requests.create(fromUuid: from, fromName: from.toUpperCase(), toUuid: to, kind: kind);

    test('are delivered to the target, newest first', () {
      request('a', 'x');
      final newer = request('b', 'x');
      request('c', 'y');
      expect(requests.incoming('x').first, same(newer));
      expect(requests.incoming('x'), hasLength(2));
      expect(requests.pending('x', fromName: 'a')!.fromUuid, 'a');
      expect(requests.pending('x', fromName: 'nobody'), isNull);
    });

    test('a sender has one open request', () {
      request('a', 'x');
      request('a', 'y');
      expect(requests.incoming('x'), isEmpty);
      expect(requests.outgoing('a')!.toUuid, 'y');
    });

    test('expire', () {
      request('a', 'x');
      now = now.add(const Duration(seconds: 59));
      expect(requests.incoming('x'), hasLength(1));
      now = now.add(const Duration(seconds: 1));
      expect(requests.incoming('x'), isEmpty);
      expect(requests.outgoing('a'), isNull);
    });

    test('can be removed, and dropped for a player who left', () {
      final a = request('a', 'x');
      request('b', 'a');
      requests.remove(a);
      expect(requests.incoming('x'), isEmpty);
      requests.removeAllFor('a');
      expect(requests.incoming('a'), isEmpty);
    });
  });

  test('cooldowns', () {
    var now = DateTime.utc(2026, 1, 1);
    final cooldowns = Cooldowns(now: () => now);
    const wait = Duration(seconds: 5);
    expect(cooldowns.remaining('a', wait), isNull);
    cooldowns.mark('a');
    expect(cooldowns.remaining('a', wait), const Duration(seconds: 5));
    now = now.add(const Duration(seconds: 3));
    expect(cooldowns.remaining('a', wait), const Duration(seconds: 2));
    expect(cooldowns.remaining('b', wait), isNull);
    now = now.add(const Duration(seconds: 2));
    expect(cooldowns.remaining('a', wait), isNull);
  });
}

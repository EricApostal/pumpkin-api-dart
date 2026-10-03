import 'package:pumpkin_api/src/data_keys.dart';
import 'package:test/test.dart';

void main() {
  late TypedData d;
  setUp(() => d = TypedData(MemoryDataStore()));

  test('defaults and updates', () {
    final kills = DataKey<int>('kills', defaultValue: 0);
    expect(d.get(kills), 0);
    expect(d.has(kills), isFalse);
    expect(d.update(kills, (o) => o + 3), 3);
    expect(d.get(kills), 3);
    d.remove(kills);
    expect(d.get(kills), 0);
  });

  test('missing without default', () {
    final nick = DataKey<String>('nick');
    expect(d.getOrNull(nick), isNull);
    expect(() => d.get(nick), throwsStateError);
    d.set(nick, 'eric');
    expect(d.get(nick), 'eric');
  });

  test('bool, double, list', () {
    final b = DataKey<bool>('b');
    final x = DataKey<double>('x');
    final l = DataKey<List<String>>('l', defaultValue: const []);
    d.set(b, true);
    d.set(x, 1.5);
    d.set(l, ['a', 'b"c']);
    expect(d.get(b), true);
    expect(d.get(x), 1.5);
    expect(d.get(l), ['a', 'b"c']);
  });

  test('custom codec and bad data', () {
    final k = DataKey<(int, int)>.custom(
      'pos',
      encode: (v) => '${v.$1},${v.$2}',
      decode: (t) {
        final p = t.split(',');
        return (int.parse(p[0]), int.parse(p[1]));
      },
      defaultValue: (0, 0),
    );
    d.set(k, (3, 4));
    expect(d.get(k), (3, 4));
    d.store.writeString('pos', 'garbage');
    expect(d.get(k), (0, 0));
  });

  test('const keys', constKeys);

  test('unsupported builtin type', () {
    expect(() => DataKey<DateTime>('t'), throwsArgumentError);
  });

  test('type mismatch reads as missing', () {
    d.store.writeString('n', 'x');
    expect(d.getOrNull(DataKey<int>('n')), isNull);
  });
}

const _constKey = IntKey('c', defaultValue: 7);
const _constList = StringListKey('cl', defaultValue: []);

void constKeys() {
  final d = TypedData(MemoryDataStore());
  expect(d.get(_constKey), 7);
  d.set(_constList, ['x']);
  expect(d.get(_constList), ['x']);
}

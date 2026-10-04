import 'package:commons/src/load_order.dart' as order;
import 'package:test/test.dart';

final class Fake {
  final String name;
  final List<String> dependsOn;

  Fake(this.name, [this.dependsOn = const []]);
}

List<Fake> loadOrder(List<Fake> items) =>
    order.loadOrder(items, name: (m) => m.name, dependsOn: (m) => m.dependsOn);

void main() {
  test('dependencies load first', () {
    final order = loadOrder([
      Fake('chat', ['economy', 'mail']),
      Fake('mail', ['economy']),
      Fake('economy'),
    ]).map((m) => m.name).toList();
    expect(order, ['economy', 'mail', 'chat']);
  });

  test('independent modules keep their order', () {
    final order = loadOrder([Fake('a'), Fake('b'), Fake('c')]);
    expect(order.map((m) => m.name), ['a', 'b', 'c']);
  });

  test('unknown dependency, cycle and duplicate names are errors', () {
    expect(
      () => loadOrder([
        Fake('a', ['x']),
      ]),
      throwsStateError,
    );
    expect(
      () => loadOrder([
        Fake('a', ['b']),
        Fake('b', ['a']),
      ]),
      throwsStateError,
    );
    expect(() => loadOrder([Fake('a'), Fake('a')]), throwsStateError);
  });
}

import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:lonsdaleite/src/omnitool.dart';
import 'package:lonsdaleite/src/registrar.dart';
import 'package:test/test.dart';

final class _FakeRegistrar implements ItemRegistrar {
  final registered = <ItemDefinition>[];

  @override
  int register(ItemDefinition item) {
    registered.add(item);
    return registered.length - 1;
  }
}

final class _FakePort implements BlockTransformerPort {
  final Set<String> applicable;
  final tried = <String>[];

  _FakePort(this.applicable);

  @override
  bool apply(String transformer) {
    tried.add(transformer);
    return applicable.contains(transformer);
  }
}

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);

  group('registration', () {
    test('registers every item once, in registration order', () {
      final registrar = _FakeRegistrar();
      final ids = registerManifestItems(manifest, registrar);
      expect(ids, List.generate(32, (i) => i));
      expect(
        registrar.registered.map((i) => i.id),
        manifest.items.map((i) => i.id),
      );
      expect({for (final i in registrar.registered) i.id}, hasLength(32));
    });

    test('the definition carries the server view of the components', () {
      final registrar = _FakeRegistrar()
        ..register(
          ItemDefinition.fromManifest(
            manifest.item('lonsdaleite:perfect_lonsdaleite_omnitool')!,
          ),
        );
      final definition = registrar.registered.single;
      expect(definition.maxStackSize, 1);
      final rules =
          ((definition.components['minecraft:tool']! as Json)['rules']!
              as List<Object?>);
      expect(rules, hasLength(6));
    });

    test(
      'stackable materials stack to 64 and the wardframe item knows its block',
      () {
        final raw = ItemDefinition.fromManifest(
          manifest.item('lonsdaleite:raw_lonsdaleite')!,
        );
        expect(raw.maxStackSize, 64);
        expect(raw.block, isNull);
        final frame = ItemDefinition.fromManifest(
          manifest.item('lonsdaleite:lonsdaleite_wardframe')!,
        );
        expect(frame.block, 'lonsdaleite:lonsdaleite_wardframe');
      },
    );
  });

  group('omnitool', () {
    test('tries the axe, then the hoe, then the shovel', () {
      expect(omnitoolOrder(sneaking: false), [
        Transformers.axe,
        Transformers.hoe,
        Transformers.shovel,
      ]);
    });

    test('sneaking swaps the hoe and the shovel', () {
      expect(omnitoolOrder(sneaking: true), [
        Transformers.axe,
        Transformers.shovel,
        Transformers.hoe,
      ]);
    });

    test('dirt is tilled normally and made into a path while sneaking', () {
      final dirt = {Transformers.hoe, Transformers.shovel};
      expect(useOmnitool(_FakePort(dirt), sneaking: false), Transformers.hoe);
      expect(useOmnitool(_FakePort(dirt), sneaking: true), Transformers.shovel);
    });

    test('a log is stripped without trying anything else', () {
      final port = _FakePort({Transformers.axe});
      expect(useOmnitool(port, sneaking: false), Transformers.axe);
      expect(port.tried, [Transformers.axe]);
    });

    test('nothing applying leaves the click alone', () {
      final port = _FakePort({});
      expect(useOmnitool(port, sneaking: false), isNull);
      expect(port.tried, hasLength(3));
    });
  });
}

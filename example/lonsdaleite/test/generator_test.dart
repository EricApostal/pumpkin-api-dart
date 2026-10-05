import 'dart:convert';
import 'dart:io';

import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:test/test.dart';

import '../tool/src/build_manifest.dart';
import '../tool/src/java_text.dart';
import '../tool/src/mod_data.dart';
import '../tool/src/mod_source.dart';
import '../tool/src/vanilla.dart';
import '../tool/src/verify_vanilla.dart';

void main() {
  group('Java text', () {
    test('splits arguments at top level only', () {
      expect(splitTopLevel('A, f(b, c), "x,y", (s, l) -> false, new W(1, 2)'), [
        'A',
        'f(b, c)',
        '"x,y"',
        '(s, l) -> false',
        'new W(1, 2)',
      ]);
      expect(splitTopLevel(''), isEmpty);
    });

    test('parses a call chain across lines', () {
      final chain = parseCallChain('''
p.pickaxe(M.A, 5, -2.8F)
    .component(DataComponents.WEAPON, new Weapon(1))
    .enchantable(15)''');
      expect(chain.root, 'p');
      expect(
        [for (final c in chain.calls) c.name],
        ['pickaxe', 'component', 'enchantable'],
      );
      expect(chain.calls[1].args, ['DataComponents.WEAPON', 'new Weapon(1)']);
    });

    test('rejects what it does not model', () {
      expect(() => parseCallChain('p.field'), throwsA(isA<JavaParseError>()));
      expect(() => parseJavaNumber('1.5f * 2'), throwsA(isA<JavaParseError>()));
    });

    test('floats are rounded to 32 bits, doubles are not', () {
      expect(parseJavaNumber('-2.8F').value, -2.799999952316284);
      expect(parseJavaNumber('-3.4').value, -3.4);
      expect(parseJavaNumber('15').asInt, 15);
      expect(floatField(parseJavaNumber('8.2F').value), 8.2);
    });

    test('comments are removed but strings kept', () {
      expect(stripJavaComments('a // b\n/* c */d "// e"'), 'a \nd "// e"');
    });

    test('seconds become ticks like a float product cut to an int', () {
      expect(ticks(1.15), 23);
      expect(ticks(0.4), 8);
      expect(ticks(8.75), 175);
      expect(ticks(5.5), 110);
    });
  });

  group('vanilla builders', () {
    final fixture = jsonDecode(
      File('test/fixtures/vanilla_items_subset.json').readAsStringSync(),
    ) as Json;

    test('reproduce the vanilla items of the extractor dump', () {
      final report = verifyAgainstVanilla(fixture);
      expect(report.mismatches, isEmpty);
      expect(report.failedChecks, isEmpty);
      expect(
        report.matched,
        containsAll([
          'netherite_pickaxe',
          'netherite_axe',
          'netherite_shovel',
          'netherite_hoe',
          'netherite_sword',
          'netherite_spear',
          'wooden_spear',
          'netherite_helmet',
          'netherite_boots',
          'diamond_chestplate',
          'golden_helmet',
          'flint',
          'stone',
        ]),
      );
    });

    test('a changed formula is caught', () {
      final broken = jsonDecode(jsonEncode(fixture)) as Json;
      final components =
          (broken['netherite_pickaxe']! as Json)['components']! as Json;
      ((components['minecraft:tool']! as Json)['rules']!
          as List<Object?>)[1] = {
        'blocks': '#minecraft:mineable/pickaxe',
        'speed': 8.0,
        'correct_for_drops': true,
      };
      expect(
        verifyAgainstVanilla(broken).mismatches.single,
        startsWith('netherite_pickaxe'),
      );
    });

    test("the mace's tool properties are vanilla's", () {
      final vanillaMace =
          ((fixture['mace']! as Json)['components']! as Json)['minecraft:tool'];
      expect(maceToolProperties(), vanillaMace);
    });
  });

  // Needs a checkout of the mod, so it only runs when LONSDALEITE_SRC is set.
  test(
    'the manifest is what the generator makes from the mod sources',
    () {
      final path = Platform.environment['LONSDALEITE_SRC'];
      final root = Directory(path ?? '');
      final source = ModSource(root);
      final manifest = buildManifest(
        source: source,
        data: ModData.read(Directory('${root.path}/shared-resources')),
        modInfo: readModInfo(root, source.modId),
      );
      expect(jsonEncode(manifest), lonsdaleiteManifestJson);
    },
    skip: Platform.environment['LONSDALEITE_SRC'] == null
        ? 'LONSDALEITE_SRC is not set'
        : false,
  );
}

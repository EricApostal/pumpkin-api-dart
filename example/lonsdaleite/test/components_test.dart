import 'package:lonsdaleite/src/components.dart';
import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:test/test.dart';

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);

  test('typed components write back exactly what they read', () {
    var checked = 0;
    for (final item in manifest.items) {
      final c = item.components;
      final typed = <String, Object?>{
        'minecraft:tool': c.tool?.toJson(),
        'minecraft:weapon': c.weapon?.toJson(),
        'minecraft:equippable': c.equippable?.toJson(),
        'minecraft:kinetic_weapon': c.kineticWeapon?.toJson(),
        'minecraft:piercing_weapon': c.piercingWeapon?.toJson(),
        'minecraft:attribute_modifiers': [
          for (final m in c.attributeModifiers) m.toJson(),
        ],
      };
      typed.forEach((key, json) {
        if (json == null) return;
        expect(json, c.raw[key], reason: '${item.id} $key');
        checked++;
      });
    }
    expect(checked, 80);
  });

  test('tool rules pick the first rule that matches', () {
    const tool = ToolComponent(
      rules: [
        ToolRule(blocks: '#a', correctForDrops: false),
        ToolRule(blocks: '#b', speed: 9, correctForDrops: true),
        ToolRule(blocks: '#c', speed: 3),
      ],
    );
    bool only(String tag, String blocks) => blocks == tag;
    expect(tool.miningSpeed((b) => only('#b', b)), 9);
    expect(tool.miningSpeed((b) => only('#c', b)), 3);
    expect(
      tool.miningSpeed((b) => only('#a', b)),
      1.0,
      reason: 'a rule without a speed is skipped',
    );
    expect(tool.isCorrectForDrops((b) => only('#a', b)), isFalse);
    expect(tool.isCorrectForDrops((b) => only('#b', b)), isTrue);
    expect(
      tool.isCorrectForDrops((b) => only('#c', b)),
      isFalse,
      reason: 'no verdict means not correct',
    );
  });

  test('the omnitool mines every tool family at full speed on the server', () {
    final omnitool = manifest.item('lonsdaleite:lonsdaleite_omnitool')!;
    bool matches(Set<String> tags, String blocks) => tags.contains(blocks);
    final onDirt = {'#minecraft:mineable/shovel'};
    expect(
      omnitool.components.tool!.miningSpeed((b) => matches(onDirt, b)),
      1.0,
      reason: 'the client-side Tool component alone has pickaxe rules only',
    );
    expect(
      omnitool.serverView.tool!.miningSpeed((b) => matches(onDirt, b)),
      8.2,
    );
    expect(
      omnitool.serverView.tool!.miningSpeed(
        (b) => matches({'#minecraft:mineable/pickaxe'}, b),
      ),
      8.2,
    );
    expect(
      omnitool.serverView.tool!.miningSpeed(
        (b) => matches({'#minecraft:wool'}, b),
      ),
      1.0,
    );
  });

  test('missing fields are reported', () {
    expect(() => ToolRule.fromJson({'speed': 1}), throwsFormatException);
    expect(() => ToolComponent.fromJson({'rules': 1}), throwsFormatException);
  });
}

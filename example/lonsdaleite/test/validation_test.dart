import 'dart:convert';

import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:lonsdaleite/src/validation.dart';
import 'package:test/test.dart';

Json _fresh() => jsonDecode(lonsdaleiteManifestJson) as Json;

List<String> _issuesAfter(void Function(Json json) edit) {
  final json = _fresh();
  edit(json);
  return validateManifest(Manifest.fromJson(json));
}

void main() {
  test('the real manifest is consistent', () {
    expect(validateManifest(Manifest.parse(lonsdaleiteManifestJson)), isEmpty);
  });

  test('a tag that lists an unknown item is reported', () {
    final issues = _issuesAfter((json) {
      final tags = json['tags']! as Json;
      final axes =
          ((tags['item']! as Json)['minecraft:axes']! as Json)['values']!
              as List<Object?>;
      axes.add('lonsdaleite:lonsdaleite_scythe');
    });
    expect(issues, [
      'item tag minecraft:axes lists the unknown item lonsdaleite:lonsdaleite_scythe',
    ]);
  });

  test('a repair tag that does not exist is reported', () {
    final issues = _issuesAfter((json) {
      final tags = json['tags']! as Json;
      (tags['item']! as Json).remove('lonsdaleite:repairs_lonsdaleite_tools');
    });
    expect(
      issues,
      contains(
        'lonsdaleite:lonsdaleite_pickaxe: repair tag #lonsdaleite:repairs_lonsdaleite_tools is missing',
      ),
    );
  });

  test('components that disagree with the material are reported', () {
    final issues = _issuesAfter((json) {
      final items = json['items']! as List<Object?>;
      final pickaxe = items.cast<Json>().firstWhere(
        (i) => i['id'] == 'lonsdaleite:lonsdaleite_pickaxe',
      );
      (pickaxe['components']! as Json)['minecraft:max_damage'] = 2000;
    });
    expect(issues, [
      'lonsdaleite:lonsdaleite_pickaxe: max_damage 2000 != 2800',
    ]);
  });

  test('a recipe for a missing item is reported', () {
    final issues = _issuesAfter((json) {
      final recipes = (json['recipes']! as Json)['entries']! as List<Object?>;
      final recipe = recipes.cast<Json>().first['json']! as Json;
      (recipe['result']! as Json)['id'] = 'lonsdaleite:nothing';
    });
    expect(
      issues,
      anyElement(contains('makes the unknown item lonsdaleite:nothing')),
    );
  });

  test('an item missing from the creative tab is reported', () {
    final issues = _issuesAfter((json) {
      final own = (json['creative_tabs']! as Json)['own']! as Json;
      (own['items']! as List<Object?>).remove('lonsdaleite:lonsdaleite_mace');
    });
    expect(issues, ['Creative tab does not list lonsdaleite:lonsdaleite_mace']);
  });

  test('an insertion after an item that is not inserted yet is reported', () {
    final issues = _issuesAfter((json) {
      final insertions =
          (json['creative_tabs']! as Json)['insertions']! as List<Object?>;
      final first = insertions.removeAt(0);
      insertions.add(first);
    });
    expect(issues, anyElement(contains('which is not inserted before it')));
  });

  test('a block with the wrong state count is reported', () {
    final issues = _issuesAfter((json) {
      (((json['block']! as Json)['block_state']! as Json))['state_count'] = 32;
    });
    expect(
      issues,
      contains(
        'lonsdaleite:lonsdaleite_wardframe: 32 states for 6 boolean properties',
      ),
    );
  });

  test('external references list what the host has to know', () {
    final refs = externalReferences(Manifest.parse(lonsdaleiteManifestJson));
    expect(
      refs.items,
      containsAll([
        'minecraft:stick',
        'minecraft:diamond',
        'minecraft:obsidian',
        'minecraft:coal_block',
        'minecraft:gunpowder',
        'minecraft:breeze_rod',
        'minecraft:raw_gold',
        'minecraft:netherite_boots',
      ]),
    );
    expect(refs.items.every((i) => i.startsWith('minecraft:')), isTrue);
    expect(
      refs.itemTags,
      containsAll([
        'minecraft:axes',
        'minecraft:swords',
        'minecraft:doors',
        'minecraft:enchantable/mace',
      ]),
    );
    expect(
      refs.blockTags,
      containsAll([
        'minecraft:mineable/pickaxe',
        'minecraft:needs_diamond_tool',
        'minecraft:mineable/hoe',
        'minecraft:sword_efficient',
        'minecraft:incorrect_for_netherite_tool',
      ]),
    );
    expect(refs.blocks, {'minecraft:cobweb'});
  });
}

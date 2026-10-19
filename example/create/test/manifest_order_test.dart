// The extracted content manifest must stay usable as the canonical registration
// order: unique, dense indices and namespaced-path keys (the registries prefix
// `create:`). A duplicate or a gap here would shift the ids a real Create client
// compares against.
import 'package:test/test.dart';

import 'package:create/src/manifest/manifest.dart';

void _expectUnique(Iterable<String> keys, String what) {
  final seen = <String>{};
  for (final key in keys) {
    expect(seen.add(key), isTrue, reason: 'duplicate $what `$key`');
  }
}

void _expectPathKeys(Iterable<String> keys, String what) {
  for (final key in keys) {
    expect(
      key.contains(':'),
      isFalse,
      reason: '$what key `$key` is not a path',
    );
    expect(key, isNotEmpty, reason: 'empty $what key');
  }
}

void main() {
  test('block manifest indices are unique and dense', () {
    final indices = [for (final b in kBlocks) b.index]..sort();
    expect(
      indices.toSet().length,
      kBlocks.length,
      reason: 'duplicate block index',
    );
    expect(indices.first, 0);
    expect(indices.last, kBlocks.length - 1, reason: 'gap in block indices');
  });

  test('item manifest indices are unique and dense', () {
    final indices = [for (final i in kItems) i.index]..sort();
    expect(
      indices.toSet().length,
      kItems.length,
      reason: 'duplicate item index',
    );
    expect(indices.first, 0);
    expect(indices.last, kItems.length - 1, reason: 'gap in item indices');
  });

  test('every block item of the manifest is an item', () {
    final items = {for (final i in kItems) i.key};
    for (final block in kBlocks) {
      final item = block.blockItem;
      if (item != null) {
        expect(
          items,
          contains(item),
          reason: 'block `${block.key}` names item `$item`',
        );
      }
    }
  });

  test('block and item keys are unique paths', () {
    _expectUnique([for (final b in kBlocks) b.key], 'block');
    _expectPathKeys([for (final b in kBlocks) b.key], 'block');
    _expectUnique([for (final i in kItems) i.key], 'item');
    _expectPathKeys([for (final i in kItems) i.key], 'item');
  });

  test('registry keys are unique paths', () {
    _expectUnique([
      for (final e in kBlockEntityTypes) e.key,
    ], 'block entity type');
    _expectPathKeys([
      for (final e in kBlockEntityTypes) e.key,
    ], 'block entity type');
    _expectUnique([for (final e in kEntityTypes) e.key], 'entity type');
    _expectPathKeys([for (final e in kEntityTypes) e.key], 'entity type');
    _expectUnique([for (final e in kMenuTypes) e.key], 'menu');
    _expectUnique([for (final e in kDataComponents) e.key], 'data component');
    _expectUnique([for (final e in kDamageTypes) e.key], 'damage type');
    _expectUnique([for (final e in kParticleTypes) e.key], 'particle type');
    _expectUnique([for (final e in kRecipeTypes) e.key], 'recipe type');
  });

  test('fluid source and flowing keys are unique', () {
    _expectUnique([
      for (final f in kFluids) ...[
        'create:${f.sourceKey}',
        'create:${f.flowingKey}',
      ],
    ], 'fluid');
  });

  test('sound event keys are unique', () {
    _expectUnique([
      for (final s in kSoundEvents)
        for (final e in s.registeredEvents) 'create:$e',
    ], 'sound event');
  });
}

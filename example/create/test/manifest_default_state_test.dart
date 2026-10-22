// The generated manifest's default states, including the two that used to be
// folded wrong from the Java constructors:
//
// * `create:packager` - `PackagerBlock` sets `LINKED=false` on a local before
//   `registerDefaultState`, and `linked=true` is `stateDefinition.any()`;
// * `create:{andesite,brass,copper}_table_cloth` - registered with
//   `TableClothBlock(Properties, String)`, which registers no default state, so
//   they keep `any()` (`entity=true`) while the 16 dye cloths (the `DyeColor`
//   constructor) register `HAS_BE=false`.
//
// A wrong default state is silent: the block places as the `_linked` model,
// `useItemOn` refuses the stock link / the block entity is not created, and the
// state id a client sees is off. `defaultStateIndex` is the port's own
// numbering (`docs/block-registry.md`), so a `setblock` with no state must
// produce these indices.
import 'package:create/src/manifest/blocks.g.dart';
import 'package:create/src/manifest/types_blocks.dart';
import 'package:test/test.dart';

import '../tool/src/blocks_props.dart';

int _indexOf(String key) {
  final b = kBlocks.firstWhere((b) => b.key == key);
  return defaultStateIndex(
    b.defaultState,
    [for (final p in b.properties) PropDef(p.name, p.type, p.values)],
  );
}

ManifestBlock _block(String key) => kBlocks.firstWhere((b) => b.key == key);

void main() {
  test('packager defaults to linked=false (Java: LINKED is not set to true)', () {
    final b = _block('packager');
    expect(b.defaultState['linked'], 'false');
    expect(b.defaultState['powered'], 'false');
    expect(b.defaultState['facing'], 'north');
    // facing north (0) * 4 + linked false (1) * 2 + powered false (1) = 3.
    expect(_indexOf('packager'), 3);
    expect(b.stateCount, 24);
  });

  test('the three metal table cloths keep entity=true (String constructor)', () {
    for (final key in const ['andesite_table_cloth', 'brass_table_cloth', 'copper_table_cloth']) {
      expect(_block(key).defaultState['entity'], 'true', reason: key);
      expect(_indexOf(key), 0, reason: key);
    }
  });

  test('the dye table cloths register entity=false', () {
    for (final key in const ['white_table_cloth', 'red_table_cloth', 'black_table_cloth']) {
      expect(_block(key).defaultState['entity'], 'false', reason: key);
      expect(_indexOf(key), 1, reason: key);
    }
  });

  test('no block has an unresolved default value', () {
    for (final b in kBlocks) {
      for (final e in b.defaultState.entries) {
        expect(e.value, isNot('?'), reason: '${b.key}.${e.key}');
      }
    }
  });
}
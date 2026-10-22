// Unit tests for the generator's default-state folding
// (`tool/src/blocks_props.dart`).
//
// The folding is what turns Create's
// `createBlockStateDefinition` / `registerDefaultState` constructors into the
// `defaultState` map of the generated manifest. Two shapes it must get right,
// both of which were silently wrong before:
//
// * `PackagerBlock` stages its default on a local variable
//   (`BlockState s = defaultBlockState(); if (s.hasProperty(LINKED)) s =
//   s.setValue(LINKED, false); registerDefaultState(s.setValue(POWERED, false));`)
//   - folding only the `registerDefaultState(...)` argument drops `LINKED`;
// * `TableClothBlock`'s `String type` constructor registers nothing, so those
//   blocks keep `stateDefinition.any()` (`entity=true`) - the default is not the
//   one its *other* (`DyeColor`) constructor registers.
//
// These cases need the Java sources, so the folder takes its interpreter as
// callbacks and is tested directly.
import 'package:test/test.dart';

import '../tool/src/blocks_props.dart';

/// A tiny stand-in for the property declarations the folder resolves.
final Map<String, PropDef> _props = {
  'entity': PropDef('entity', 'bool', const ['true', 'false']),
  'linked': PropDef('linked', 'bool', const ['true', 'false']),
  'powered': PropDef('powered', 'bool', const ['true', 'false']),
  'waterlogged': PropDef('waterlogged', 'bool', const ['true', 'false']),
  'axis': PropDef('axis', 'enum', const ['x', 'y', 'z']),
};

PropDef? _resolve(String expr, [String owner = 'T']) {
  final last = expr.trim().split('.').last.toLowerCase();
  if (last == 'has_be') return _props['entity']; // TableClothBlock.HAS_BE
  return _props[last];
}

String? _value(PropDef p, String expr) {
  final e = expr.trim();
  switch (e) {
    case 'false':
    case 'true':
      return e;
  }
  if (e == 'Direction.Axis.Y') return 'y';
  if (e == 'Direction.Axis.X') return 'x';
  return null;
}

Map<String, String> _fold(String body, [Map<String, String> start = const {}]) {
  final notes = <String>[];
  final problems = <String>[];
  final out = foldConstructorDefaults(
    body,
    start,
    ownerName: 'TestBlock',
    resolveProp: _resolve,
    valueOf: _value,
    declares: (n) => _props.containsKey(n),
    note: notes.add,
    problem: problems.add,
  );
  expect(problems, isEmpty, reason: 'unexpected problem: $problems');
  return out;
}

void main() {
  group('PackagerBlock', () {
    const body = '''
      super(properties);
      BlockState defaultBlockState = defaultBlockState();
      if (defaultBlockState.hasProperty(LINKED))
          defaultBlockState = defaultBlockState.setValue(LINKED, false);
      registerDefaultState(defaultBlockState.setValue(POWERED, false));
    ''';

    test('folds a default staged on a local variable', () {
      final state = _fold(body, const {'facing': 'north'});
      expect(state['linked'], 'false', reason: 'LINKED=false must not be dropped');
      expect(state['powered'], 'false');
      expect(state['facing'], 'north', reason: 'the inherited default is kept');
    });

    test('the local variable shadows the defaultBlockState() method', () {
      // `defaultBlockState` is both the method and the local's name; reading the
      // method instead of the staged local would lose LINKED.
      final state = _fold('BlockState defaultBlockState = defaultBlockState();\n'
          'defaultBlockState = defaultBlockState.setValue(LINKED, false);\n'
          'registerDefaultState(defaultBlockState);');
      expect(state, {'linked': 'false'});
    });

    test('a false condition skips the setValue', () {
      final state = _fold('BlockState s = defaultBlockState();\n'
          'if (SharedConstants.IS_RUNNING_IN_IDE && false) s = s.setValue(LINKED, false);\n'
          'registerDefaultState(s.setValue(POWERED, false));');
      expect(state, {'powered': 'false'});
    });
  });

  group('TableClothBlock', () {
    test('the String constructor registers nothing and keeps any()', () {
      // Java: `public TableClothBlock(Properties p, String type) { super(p); }`
      expect(_fold('super(properties);'), isEmpty);
    });

    test('the DyeColor constructor registers HAS_BE=false', () {
      final state = _fold('super(properties);\n'
          'registerDefaultState(defaultBlockState().setValue(HAS_BE, false));');
      expect(state, {'entity': 'false'});
    });
  });

  group('state expression roots', () {
    test('`this.defaultBlockState()` starts from the inherited state', () {
      final state = _fold('super(properties);\n'
          'this.registerDefaultState(this.defaultBlockState().setValue(AXIS, Direction.Axis.Y));',
          const {'waterlogged': 'true'});
      expect(state, {'waterlogged': 'true', 'axis': 'y'});
    });

    test('`stateDefinition.any()` starts from any()', () {
      final state = _fold('registerDefaultState(stateDefinition.any().setValue(AXIS, Direction.Axis.X));',
          const {'waterlogged': 'true'});
      expect(state, {'axis': 'x'}, reason: 'any() resets the inherited state');
    });

    test('`super.defaultBlockState()` starts from the inherited state', () {
      final state = _fold('registerDefaultState(super.defaultBlockState().setValue(WATERLOGGED, false));',
          const {'axis': 'y'});
      expect(state, {'axis': 'y', 'waterlogged': 'false'});
    });
  });

  group('statement splitting', () {
    test('keeps an `if` and its body together', () {
      final segs = splitJavaStatements('if (a) b = b.setValue(ONE, false);\nc = 1;');
      expect(segs, ['if (a) b = b.setValue(ONE, false);', 'c = 1;']);
    });

    test('ends a braced block without a semicolon', () {
      final segs = splitJavaStatements('if (a) { b = 1; } c = 2;');
      expect(segs, ['if (a) { b = 1; }', 'c = 2;']);
    });

    test('does not split inside parentheses', () {
      expect(splitJavaStatements('a(b, c);'), ['a(b, c);']);
    });
  });

  test('topLevelAssignment ignores comparisons and compound assignments', () {
    expect(topLevelAssignment('a == b'), -1);
    expect(topLevelAssignment('a += b'), -1);
    expect(topLevelAssignment('a.b = c'), 'a.b = c'.indexOf('='));
  });
}
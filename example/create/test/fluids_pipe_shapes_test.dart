// The pipe-like fluid blocks must register a real selection shape: the 8-voxel core and arms of
// `PipeBlock` (the plain pipe), the poles of the glass pipe and the valve and the smart pipe's
// shaper. A hairline shape (a `4 / 16f` pipe width) or an empty one leaves the block unbreakable:
// the ray never hits it, so the outline never appears and no break packet is sent.
import 'dart:io';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart';
import 'package:create/src/fluids/pipe_blocks.dart';
import 'package:create/src/fluids/pipe_shapes.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show BlockBox, BlockShape, EmptyShape, ShapeRule;
import 'package:test/test.dart';

/// The manifest entry of `create:<path>`.
ManifestBlock _manifest(String path) =>
    kBlocks.firstWhere((b) => b.key == path);

/// Every state of [block] as property name -> value, in the manifest's value order.
List<Map<String, String>> _states(ManifestBlock block) {
  var states = <Map<String, String>>[{}];
  for (final property in block.properties) {
    states = [
      for (final s in states)
        for (final value in property.values) {...s, property.name: value},
    ];
  }
  return states;
}

/// Whether a rule matches [state] (the host's `shape_rule_matches`).
bool _matches(ShapeRule rule, Map<String, String> state) =>
    rule.when.entries.every((e) => state[e.key] == e.value);

/// The extent of [boxes] on [axis] (0 = x, 1 = y, 2 = z).
double _span(List<BlockBox> boxes, int axis) {
  final min = [
    for (final b in boxes) axis == 0 ? b.minX : (axis == 1 ? b.minY : b.minZ),
  ].reduce((a, b) => a < b ? a : b);
  final max = [
    for (final b in boxes) axis == 0 ? b.maxX : (axis == 1 ? b.maxY : b.maxZ),
  ].reduce((a, b) => a > b ? a : b);
  return max - min;
}

/// The blocks that carry a pipe shape, with their manifest path.
const Map<String, String> _pipes = {
  'fluid_pipe': PipeKeys.fluidPipe,
  'encased_fluid_pipe': PipeKeys.encasedPipe,
  'glass_fluid_pipe': PipeKeys.glassPipe,
  'smart_fluid_pipe': PipeKeys.smartPipe,
  'fluid_valve': PipeKeys.valve,
};

/// The body of `CreateBlock <name>(...)` in the fluid block library.
String _functionBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature is missing');
  // Skip the parameter list, whose closing brace is at the start of a line too.
  final body = source.indexOf(') {', start);
  expect(body, isNot(-1), reason: '$signature has no body');
  final end = source.indexOf('\n}', body);
  expect(end, isNot(-1), reason: '$signature has no end');
  return source.substring(body, end);
}

void main() {
  test('every pipe-like block registers a non-empty selection shape', () {
    for (final entry in _pipes.entries) {
      final spec = pipeShapeSpec(entry.value);
      expect(spec, isNotNull, reason: entry.key);
      final shape = spec!.selectionShape;
      expect(
        shape,
        isNot(isA<EmptyShape>()),
        reason: '${entry.key} registers an empty selection shape',
      );
      expect(
        boxesOf(shape),
        isNotEmpty,
        reason: '${entry.key} registers a selection shape without boxes',
      );
    }
  });

  test('every state of every pipe-like block has a non-empty shape', () {
    for (final entry in _pipes.entries) {
      final manifest = _manifest(entry.key);
      final spec = pipeShapeSpec(entry.value)!;
      final states = _states(manifest);
      expect(states, hasLength(manifest.stateCount), reason: entry.key);
      for (final state in states) {
        for (final selection in [true, false]) {
          final boxes = boxesOf(shapeOf(spec, state, selection: selection));
          expect(
            boxes,
            isNotEmpty,
            reason: '${entry.key} $state selection=$selection',
          );
        }
      }
    }
  });

  test('no pipe is a hairline: every state is at least 8 voxels on two axes', () {
    for (final entry in _pipes.entries) {
      final spec = pipeShapeSpec(entry.value)!;
      for (final state in _states(_manifest(entry.key))) {
        final boxes = boxesOf(shapeOf(spec, state));
        final wide = [
          for (var axis = 0; axis < 3; axis++) _span(boxes, axis),
        ].where((span) => span >= 0.5 - 1e-9).length;
        expect(
          wide,
          greaterThanOrEqualTo(2),
          reason:
              '${entry.key} $state is thinner than 8 voxels on two axes: '
              '${[for (var a = 0; a < 3; a++) _span(boxes, a)]}',
        );
      }
    }
  });

  test('the plain pipe is the 8-voxel core plus an arm per open side', () {
    final spec = pipeShapeSpec(PipeKeys.fluidPipe)!;
    final closed = shapeOf(spec, {
      for (final d in Direction.values) d.serializedName: 'false',
    });
    final core = boxesOf(closed);
    expect(core, hasLength(1));
    expect(
      [core.single.minX, core.single.minY, core.single.minZ],
      [0.25, 0.25, 0.25],
    );
    expect(
      [core.single.maxX, core.single.maxY, core.single.maxZ],
      [0.75, 0.75, 0.75],
    );

    final open = shapeOf(spec, {
      for (final d in Direction.values) d.serializedName: 'true',
    });
    expect(boxesOf(open), hasLength(7), reason: 'core plus six arms');
    // Every arm reaches the face it opens onto and is 8 voxels wide.
    for (final d in Direction.values) {
      final arm = boxesOf(open).firstWhere(
        (b) => switch (d) {
          Direction.down => b.minY == 0,
          Direction.up => b.maxY == 1,
          Direction.north => b.minZ == 0,
          Direction.south => b.maxZ == 1,
          Direction.west => b.minX == 0,
          Direction.east => b.maxX == 1,
        },
        orElse: () => throw StateError('no arm towards ${d.serializedName}'),
      );
      // An arm is 8 voxels wide across its two short axes.
      expect(arm.maxX - arm.minX, closeTo(0.5, 1e-9));
      expect(arm.maxY - arm.minY, closeTo(0.5, 1e-9));
      expect(arm.maxZ - arm.minZ, closeTo(0.5, 1e-9));
    }

    // One open side keeps only that arm.
    final northOnly = shapeOf(spec, {
      for (final d in Direction.values)
        d.serializedName: d == Direction.north ? 'true' : 'false',
    });
    expect(boxesOf(northOnly), hasLength(2));
    expect(boxesOf(northOnly).last.minZ, 0);
    expect(boxesOf(northOnly).last.maxZ, 0.5);
  });

  test('the glass pipe and the valve follow their axis', () {
    final glass = pipeShapeSpec(PipeKeys.glassPipe)!;
    for (final axis in Axis.values) {
      final boxes = boxesOf(shapeOf(glass, {'axis': axis.serializedName}));
      expect(boxes, hasLength(1));
      final index = Axis.values.indexOf(axis);
      expect(_span(boxes, index), 1, reason: 'the pole runs along ${axis.name}');
      for (var other = 0; other < 3; other++) {
        if (other == index) continue;
        expect(_span(boxes, other), closeTo(0.5, 1e-9));
      }
    }

    final valve = pipeShapeSpec(PipeKeys.valve)!;
    for (final facing in Direction.values) {
      for (final alongFirst in const [true, false]) {
        final state = {
          'facing': facing.serializedName,
          'axis_along_first': alongFirst ? 'true' : 'false',
        };
        final axis = PipeBlocks.valvePipeAxis(
          BState(PipeKeys.valve, state),
        );
        final boxes = boxesOf(shapeOf(valve, state));
        expect(_span(boxes, Axis.values.indexOf(axis)), 1);
      }
    }
  });

  test('the smart pipe turns with its facing and points its nub by face', () {
    final smart = pipeShapeSpec(PipeKeys.smartPipe)!;
    List<BlockBox> shape(String face, Direction facing) =>
        boxesOf(shapeOf(smart, {
          'face': face,
          'facing': facing.serializedName,
        }));

    // The floor shaper's nub reaches above the block, the ceiling's below it, the wall's to the
    // side the pipe faces.
    double top(List<BlockBox> boxes) =>
        boxes.map((b) => b.maxY).reduce((a, b) => a > b ? a : b);
    double bottom(List<BlockBox> boxes) =>
        boxes.map((b) => b.minY).reduce((a, b) => a < b ? a : b);
    expect(top(shape('floor', Direction.south)), greaterThan(1));
    expect(bottom(shape('ceiling', Direction.south)), lessThan(0));
    double farZ(List<BlockBox> boxes) =>
        boxes.map((b) => b.maxZ).reduce((a, b) => a > b ? a : b);
    double nearZ(List<BlockBox> boxes) =>
        boxes.map((b) => b.minZ).reduce((a, b) => a < b ? a : b);
    expect(farZ(shape('wall', Direction.south)), greaterThan(1));
    expect(nearZ(shape('wall', Direction.north)), lessThan(0));
    double farX(List<BlockBox> boxes) =>
        boxes.map((b) => b.maxX).reduce((a, b) => a > b ? a : b);
    double nearX(List<BlockBox> boxes) =>
        boxes.map((b) => b.minX).reduce((a, b) => a < b ? a : b);
    expect(farX(shape('wall', Direction.east)), greaterThan(1));
    expect(nearX(shape('wall', Direction.west)), lessThan(0));
    // The floor and ceiling poles lie along the facing axis.
    for (final face in const ['floor', 'ceiling']) {
      expect(_span(shape(face, Direction.east), 0), 1);
      expect(_span(shape(face, Direction.north), 2), 1);
    }
  });

  test('the shape rules cover every state of the shaped pipes', () {
    for (final entry in _pipes.entries) {
      final spec = pipeShapeSpec(entry.value)!;
      if (spec.shapeRules.isEmpty) continue;
      for (final state in _states(_manifest(entry.key))) {
        expect(
          spec.shapeRules.any((rule) => _matches(rule, state)),
          isTrue,
          reason: '${entry.key} $state falls back to the base shape',
        );
      }
    }
  });

  test('the shapes stay within the host limits', () {
    // `MAX_SHAPE_RULES` and `MAX_BOXES` of `crates/pumpkin-data/src/block_registry.rs`.
    for (final entry in _pipes.entries) {
      final spec = pipeShapeSpec(entry.value)!;
      expect(spec.shapeRules.length, lessThanOrEqualTo(64));
      for (final shape in [
        spec.collisionShape,
        spec.selectionShape,
        for (final rule in spec.shapeRules) ...[
          rule.collisionShape!,
          rule.selectionShape!,
        ],
      ]) {
        expect(boxesOf(shape).length, lessThanOrEqualTo(64));
        for (final b in boxesOf(shape)) {
          for (final v in [b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ]) {
            expect(v.isFinite, isTrue);
          }
          expect(b.minX <= b.maxX && b.minY <= b.maxY && b.minZ <= b.maxZ, isTrue);
        }
      }
    }
  });

  test('the encased pipe keeps the full cube of Block.getShape', () {
    final spec = pipeShapeSpec(PipeKeys.encasedPipe)!;
    expect(spec.selectionShape, BlockShape.fullCube);
    expect(spec.collisionShape, BlockShape.fullCube);
    expect(spec.shapeRules, isEmpty);
  });

  test('a non-pipe block has no pipe shape spec', () {
    expect(pipeShapeSpec('create:fluid_tank'), isNull);
  });

  test('the pipe blocks pass the pipe shapes into manifestBlock', () {
    // `fluid_blocks.dart` imports the host bindings (`dart:wasm`), so a VM test cannot build the
    // blocks; check the wiring in the source instead, like `placement_parity_test.dart` does for
    // placement rules.
    final source = File('lib/src/fluids/fluid_blocks.dart').readAsStringSync();

    // `_pipeBlock` registers the plain, encased, glass and smart pipes.
    final pipe = _functionBody(source, 'CreateBlock _pipeBlock(');
    expect(pipe, contains("final shapes = pipeShapeSpec('create:\$key');"));
    expect(pipe, contains('collisionShape: shapes?.collisionShape,'));
    expect(pipe, contains('selectionShape: shapes?.selectionShape,'));
    expect(pipe, contains('shapeRules: shapes?.shapeRules ?? const [],'));

    // The pump and the valve carry theirs the same way.
    for (final signature in [
      'CreateBlock pumpBlock()',
      'CreateBlock valveBlock()',
    ]) {
      final body = _functionBody(source, signature);
      expect(
        body,
        contains('collisionShape: shapes?.collisionShape,'),
        reason: signature,
      );
      expect(
        body,
        contains('selectionShape: shapes?.selectionShape,'),
        reason: signature,
      );
      expect(
        body,
        contains('shapeRules: shapes?.shapeRules ?? const [],'),
        reason: signature,
      );
    }
  });

  test('manifestBlock keeps the selection shape and the rules', () {
    // The pipe shapes are only useful if `manifestBlock` forwards both: the selection shape is
    // the one a ray hits, and the per-state rules are what turn a state into its arms.
    final source = File('lib/src/api/blocks.dart').readAsStringSync();
    expect(source, contains('selectionShape: selectionShape ?? BlockShape.fullCube,'));
    expect(source, contains('shapeRules: shapeRules,'));
    expect(source, contains('collisionShape:'));
  });
}

// The `pocket` API's Lua layer, driven on the Dart Lua machine (no host, no
// wasm): the global's shape, the sides each method asks for, the values a
// `pocket_response` turns into, and that the global is absent without a host.
import 'package:cc_tweaked/src/lua/lua.dart';
import 'package:cc_tweaked/src/machine/api/pocket_api.dart';
import 'package:cc_tweaked/src/machine/lua_machine.dart';
import 'package:test/test.dart';

/// A [PocketHost] that records requests and answers them when the test says.
final class _FakePocket implements PocketHost {
  /// `(side, equip)` per request, in id order (`id` is the index + 1).
  final List<(PocketSide, bool)> requests = [];

  /// When true, [equip] and [unequip] refuse (the queue is full).
  bool full = false;

  void Function(String name, List<Object?> args)? _send;

  @override
  set queueEvent(void Function(String name, List<Object?> args)? send) => _send = send;

  @override
  int? equip(PocketSide side) => _enqueue(side, true);

  @override
  int? unequip(PocketSide side) => _enqueue(side, false);

  int? _enqueue(PocketSide side, bool equip) {
    if (full) return null;
    requests.add((side, equip));
    return requests.length;
  }

  /// Answers request [id] the way the plugin tick would.
  void answer(int id, bool ok, [String? reason]) => _send?.call('pocket_response', [id.toDouble(), ok, reason]);
}

/// Runs `bios` until it finishes, answering every request with [answers] (the
/// nth request gets `answers[n]`).
List<List<Object?>> _run(String bios, _FakePocket pocket, List<List<Object?>> answers) {
  final recorded = <List<Object?>>[];
  final api = LuaTable()
    ..setString('push', NativeFunction('push', (args) {
      recorded.add(List<Object?>.of(args));
      return noValues;
    }));
  final machine = LuaMachine.create(
    cache: ProtoCache(),
    bios: bios,
    apis: {'report': api},
    vmApis: {'pocket': pocketApiBuilder(pocket)},
    hostString: 'test',
    defaultSettings: '',
  );

  machine.handleEvent(null, const []);
  for (var i = 0; i < answers.length; i++) {
    final id = i + 1;
    expect(pocket.requests, hasLength(id), reason: 'the program should have queued request $id');
    final answer = answers[i];
    pocket.answer(
      id,
      answer.first as bool,
      answer.length > 1 ? answer[1] as String? : null,
    );
    machine.handleEvent('pocket_response', [id.toDouble(), ...answer]);
  }
  // The BIOS below returns when it is done, which this machine reports as a
  // finished main coroutine (an error with no message): nothing to assert.
  return recorded;
}

/// The four methods, in the order the BIOS below calls them.
const String _bios = r'''
report.push("global", type(pocket))
report.push("methods", pocket.equipBack ~= nil, pocket.equipTop ~= nil, pocket.unequipBack ~= nil, pocket.unequipTop ~= nil)
report.push("equipBack", pocket.equipBack())
report.push("equipTop", pocket.equipTop())
report.push("unequipBack", pocket.unequipBack())
report.push("unequipTop", pocket.unequipTop())
''';

void main() {
  test('the four methods ask for the right side and return what the host answers', () {
    final pocket = _FakePocket();
    final recorded = _run(_bios, pocket, [
      [true],
      [false, 'Cannot find a valid upgrade'],
      [false, 'Nothing to unequip'],
      [true],
    ]);

    expect(pocket.requests, [
      (PocketSide.back, true),
      (PocketSide.top, true),
      (PocketSide.back, false),
      (PocketSide.top, false),
    ]);
    expect(recorded, [
      ['global', 'table'],
      ['methods', true, true, true, true],
      ['equipBack', true],
      ['equipTop', false, 'Cannot find a valid upgrade'],
      ['unequipBack', false, 'Nothing to unequip'],
      ['unequipTop', true],
    ]);
  });

  test('a full request queue answers false with a reason, as a turtle queue does', () {
    final pocket = _FakePocket()..full = true;
    final recorded = _run('report.push("equipBack", pocket.equipBack())', pocket, const []);
    expect(recorded, [
      ['equipBack', false, 'Too many ongoing pocket requests'],
    ]);
  });

  test('there is no pocket global without a host (bios.lua tests for presence)', () {
    final machine = LuaMachine.create(
      cache: ProtoCache(),
      bios: 'report.push("global", pocket)',
      apis: {
        'report': LuaTable()
          ..setString('push', NativeFunction('push', (args) {
            expect(args, ['global', null]);
            return noValues;
          })),
      },
      hostString: 'test',
      defaultSettings: '',
    );
    machine.handleEvent(null, const []);
  });
}
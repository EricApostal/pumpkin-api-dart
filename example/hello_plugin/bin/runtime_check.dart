// Exercises the parts of the Dart core libraries that standalone dart2wasm
// needs host support for, as `/t <name>` commands. Run it with
// `tool/runtime_check.sh`.
import 'dart:convert';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

enum Color { red, green }

class Thing {
  final int v;
  Thing(this.v);
  @override
  String toString() => 'Thing($v)';
}

final Map<String, Object? Function()> tests = {
  'print': () {
    print('printed from dart: ${1.5 + 1}');
    return 1;
  },
  'objhash': () => Object().hashCode != 0,
  'objset': () => {Thing(1), Thing(2)}.length,
  'objmap': () => (<Object, int>{}..[Thing(1)] = 1).length,
  'enumhash': () => Color.red.hashCode >= 0,
  'enummap': () => {Color.red: 1, Color.green: 2}[Color.green],
  'dbl_tostring': () => 1.5.toString(),
  'dbl_fixed': () => 3.14159.toStringAsFixed(2),
  'dbl_precision': () => 2.5.toStringAsPrecision(3),
  'dbl_parse': () => double.parse('1.5'),
  'dbl_tryparse': () => double.tryParse('2.25'),
  'int_parse': () => int.parse('42'),
  'replaceAll': () => 'a-b-c'.replaceAll('-', '+'),
  'replaceFirst': () => 'a-b-c'.replaceFirst('-', '+'),
  'replaceRange': () => 'abcdef'.replaceRange(1, 3, 'X'),
  'codeUnits': () => 'abc'.codeUnits.length,
  'fromCharCode': () => String.fromCharCode(65),
  'runes': () => 'héllo'.runes.length,
  'split_trim': () => ' a,b '.trim().split(',').length,
  'upper_pad': () => 'ab'.toUpperCase().padLeft(5, '.'),
  'regexp': () => RegExp('a+').hasMatch('caat'),
  'regexp_replace': () => 'a1b22'.replaceAll(RegExp(r'\d+'), '#'),
  'datetime': () => DateTime.now().millisecondsSinceEpoch > 0,
  'stopwatch': () => (Stopwatch()..start()).elapsedMicroseconds >= 0,
  'sqrt': () => math.sqrt(2.0),
  'pow': () => math.pow(2, 10),
  'sin': () => math.sin(1.0),
  'log': () => math.log(10),
  'exp': () => math.exp(1.0),
  'random': () => math.Random().nextInt(10) < 10,
  'randomsecure': () => math.Random.secure().nextInt(10) < 10,
  'expando': () {
    final e = Expando<int>();
    final k = Object();
    e[k] = 5;
    return e[k];
  },
  'weakref': () => WeakReference(Object()).target != null,
  'json_encode': () => jsonEncode({'a': 1, 'b': [true, 'x']}),
  'json_decode': () => jsonDecode('{"a":1}'),
  'runtimeType': () => Object().runtimeType.toString(),
  'interp': () => '${Thing(3)}',
  'list_sort': () => (<int>[3, 1, 2]..sort()).first,
  'bigint': () => BigInt.from(1 << 40).toString(),
  'duration': () => const Duration(seconds: 90).toString(),
  'uri': () => Uri.parse('https://a.b/c?d=e').host,
  'utf8': () => utf8.encode('héllo').length,
};

void main() => runPlugin(Probe());

final class Probe extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(name: 'runtime_check', version: '0.0.1');

  @override
  void onLoad(Context context) {
    final command = Command.create(names: ['t'], description: 'p');
    final name = CommandNode.argument(name: 'name', type: ArgumentTypes.word)
      ..execute((sender, server, args) {
        final key = args.string('name');
        try {
          final r = tests[key]!();
          logger.info('RT OK $key => $r');
        } catch (e) {
          logger.info('RT FAIL $key: $e');
        }
        return 1;
      });
    command.then(node: name);
    context.registerCommand(command: command, permission: 'probe:x');
  }
}

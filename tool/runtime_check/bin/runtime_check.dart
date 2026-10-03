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

late DataFolder _data;

final Map<String, Object? Function()> tests = {
  'fs_text': () {
    _data.writeAsString('check.txt', 'héllo');
    _data.writeAsString('check.txt', ' wörld', append: true);
    return _data.readAsString('check.txt');
  },
  'fs_json': () {
    _data.writeJson('check.json', {'a': 1, 'b': [true, 'x']});
    return _data.readJson('check.json');
  },
  'fs_dirs': () {
    _data.createDirectory('check_dir/inner');
    _data.writeAsString('check_dir/inner/f.txt', 'x');
    final listed = _data.list('check_dir/inner').map((e) => e.name).toList();
    _data.delete('check_dir', recursive: true);
    return '$listed ${_data.exists('check_dir')}';
  },
  'fs_large': () {
    _data.writeAsBytes('check.bin', List.filled(200000, 7));
    return _data.readAsBytes('check.bin').length;
  },
  'fs_missing': () {
    try {
      _data.readAsString('does_not_exist');
      return 'no error';
    } on FileException catch (e) {
      return e.isNotFound;
    }
  },
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
  'str_compare': () =>
      ['apple'.compareTo('banana') < 0, 'b'.compareTo('a') > 0, 'ab'.compareTo('abc') < 0, 'x'.compareTo('x') == 0],
  'sort_strings': () => (['shop', 'arena', 'Zoo', 'abc']..sort()),
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

void main() => runPlugin(RuntimeCheck());

final class RuntimeCheck extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'runtime_check',
    version: '0.0.1',
    permissions: [Permissions.fsWriteData],
  );

  @override
  void onLoad(Context context) {
    _data = context.files;
    final command = Command.create(names: ['t'], description: 'Runs a check');
    final name = CommandNode.argument(name: 'name', type: ArgumentTypes.word)
      ..execute((sender, server, args) {
        final key = args.string('name');
        try {
          logger.info('RT OK $key => ${tests[key]!()}');
        } catch (e) {
          logger.info('RT FAIL $key: $e');
        }
        return 1;
      });
    command.then(node: name);
    context.registerCommand(command: command, permission: 'runtime_check:t');
  }
}

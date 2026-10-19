// Exercises the parts of the Dart core libraries that standalone dart2wasm
// needs host support for, as `/t <name>` commands. Run it with
// `tool/runtime_check.sh`.
import 'dart:async';
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
late CommandSender _sender;
late Server _server;

final Map<String, FutureOr<Object?> Function()> tests = {
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
  'uri_base': () => Uri.base.toString(),
  'utf8': () => utf8.encode('héllo').length,
  // Async host calls and the event loop, see docs/async.md.
  'async_microtask': () async {
    final a = await Future.value(2);
    final b = await Future(() => 3);
    return a + b;
  },
  'async_host_call': () async {
    final stack = ItemStack.create(registryKey: 'minecraft:diamond', count: 3);
    final before = await stack.getCount();
    await stack.setCount(count: 7);
    final after = await stack.getCount();
    final max = await stack.getMaxCount();
    final key = await stack.getRegistryKey();
    stack.dispose();
    return '$before $after $max $key';
  },
  'async_parallel': () async {
    final stack = ItemStack.create(registryKey: 'minecraft:stone', count: 5);
    final results = await Future.wait([
      stack.getCount(),
      stack.getMaxCount(),
      stack.getRegistryKey(),
    ]);
    stack.dispose();
    return results;
  },
  'async_values': () async {
    final stack = ItemStack.create(registryKey: 'minecraft:diamond_sword', count: 1);
    await stack.setCustomName(name: TextComponent.text(plain: 'Excalibur'));
    await stack.addLore(line: TextComponent.text(plain: 'first'));
    await stack.addLore(line: TextComponent.text(plain: 'second'));
    await stack.addEnchantment(enchantment: Enchantment.sharpness, level: 5);
    final name = (await stack.getCustomName())?.getText();
    final lore = await stack.getLore();
    final enchantments = await stack.getEnchantments();
    stack.dispose();
    return '$name ${lore.length} ${enchantments.single.level}';
  },
  'async_sequence': () async {
    final stack = ItemStack.create(registryKey: 'minecraft:stone', count: 1);
    var sum = 0;
    for (var i = 1; i <= 200; i++) {
      await stack.setCount(count: i % 64 + 1);
      sum += await stack.getCount();
    }
    stack.dispose();
    return sum;
  },
  'async_unawaited': () async {
    final stack = ItemStack.create(registryKey: 'minecraft:stone', count: 1);
    unawaited(stack.setCount(count: 9));
    // The task waits for the call, so the stack may be read after it.
    await Future<void>.value();
    final count = await stack.getCount();
    stack.dispose();
    return count;
  },
  'async_permission': () async => _sender.hasPermission(node: 'runtime_check:t'),
  'async_broadcast': () async {
    await _server.broadcast(message: 'async broadcast works');
    return true;
  },
  'async_timer': () async {
    final start = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return DateTime.now().difference(start).inMilliseconds >= 150;
  },
  'async_timer_then_host': () async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final stack = ItemStack.create(registryKey: 'minecraft:stone', count: 4);
    final count = await stack.getCount();
    stack.dispose();
    return count;
  },
  'async_error': () async {
    try {
      await Future<void>.delayed(Duration.zero);
      throw StateError('boom');
    } on StateError catch (e) {
      return e.message;
    }
  },
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
      ..execute((sender, server, args) async {
        final key = args.string('name');
        _sender = sender;
        _server = server;
        try {
          logger.info('RT OK $key => ${await tests[key]!()}');
        } catch (e) {
          logger.info('RT FAIL $key: $e');
        }
        return 1;
      });
    command.then(node: name);
    context.registerCommand(command: command, permission: 'runtime_check:t');
  }
}

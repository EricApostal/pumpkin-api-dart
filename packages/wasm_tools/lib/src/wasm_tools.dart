import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';

import 'compiler/command.dart';

Future<void> runCli(Logger logger, List<String> args) async {
  final runner = CommandRunner<void>(
    'wasm_tools',
    'Tools to interop between Dart and WebAssembly components.',
  )..addCommand(CompileCommand(logger));
  await runner.run(args);
}

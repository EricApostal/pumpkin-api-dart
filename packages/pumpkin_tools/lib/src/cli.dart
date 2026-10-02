import 'package:args/command_runner.dart';

import 'build_command.dart';
import 'new_command.dart';

/// Runs the `pumpkin` command line tool, returning its exit code.
Future<int> runPumpkinCli(List<String> args) async {
  final runner = CommandRunner<int>(
    'pumpkin',
    'Create and build Pumpkin plugins written in Dart.',
  )..addCommand(BuildCommand())..addCommand(NewCommand());

  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    print(e);
    return 64;
  }
}

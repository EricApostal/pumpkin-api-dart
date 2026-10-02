import 'dart:io';

import 'package:pumpkin_tools/pumpkin_tools.dart';

Future<void> main(List<String> args) async {
  exitCode = await runPumpkinCli(args);
}

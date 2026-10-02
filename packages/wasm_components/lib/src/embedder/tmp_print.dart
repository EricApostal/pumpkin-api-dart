import 'string.dart';

/// Receives everything the program prints. Plugins route this to the server's
/// log, by default it is dropped (WASI stdout is not wired up).
void Function(String message)? printHandler;

void printImpl(WasmStringImplementation string) {
  final handler = printHandler;
  if (handler == null) return;
  handler(
    String.fromCharCodes(
      List<int>.generate(
        string.length,
        string.codeUnitAtUnchecked,
        growable: false,
      ),
    ),
  );
}

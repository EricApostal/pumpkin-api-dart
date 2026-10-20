/// Sable's Create compatibility layer, host half.
///
/// This entry point imports Create's block entity classes, which pull in the
/// wasm host API, so it is separate from `sable.dart` (that one stays loadable
/// on the plain Dart VM). A plugin imports this library to install the
/// adapters: `CreateHostCompat.install()`.
library;

export 'src/compat/create/create_host.dart';

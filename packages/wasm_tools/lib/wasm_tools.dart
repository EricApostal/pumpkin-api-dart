/// Compiles Dart programs to WebAssembly components.
library;

export 'src/compiler/compiler.dart' show ComponentCompiler, CompilerOptions, CompilerFailure;
export 'src/compiler/hooks/builder.dart' show CoreModuleInput;
export 'src/failure.dart';

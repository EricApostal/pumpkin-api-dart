// The `coroutine` library. `resume`, `yield` and the functions made by `wrap`
// are handled inside the VM, which switches stacks instead of recursing.
import '../value.dart';
import '../vm.dart';
import 'args.dart';

void installCoroutine(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('coroutine', lib);

  define(lib, 'create', (list) {
    final function = Args('create', list).function(0);
    return one(vm.newCoroutine(function));
  });

  lib.setString(
    'resume',
    NativeFunction(
      'resume',
      (_) => throw StateError('resume is handled by the VM'),
      kind: NativeKind.resume,
    ),
  );

  lib.setString(
    'yield',
    NativeFunction(
      'yield',
      (_) => throw StateError('yield is handled by the VM'),
      kind: NativeKind.yield,
    ),
  );

  define(lib, 'wrap', (list) {
    final function = Args('wrap', list).function(0);
    final co = vm.newCoroutine(function);
    return one(
      NativeFunction(
        'wrap',
        (_) => throw StateError('wrap is handled by the VM'),
        kind: NativeKind.wrap,
        data: co,
      ),
    );
  });

  define(lib, 'status', (list) {
    final value = Args('status', list)[0];
    if (value is! Coroutine) Args('status', list).wrongType(0, 'coroutine');
    if (identical(value, vm.current)) return one('running');
    return one(switch (value.status) {
      CoStatus.fresh || CoStatus.suspended || CoStatus.preempted => 'suspended',
      CoStatus.running => 'running',
      CoStatus.normal => 'normal',
      CoStatus.dead => 'dead',
    });
  });

  define(lib, 'running', (_) {
    final co = vm.current;
    return <Object?>[co, identical(co, vm.rootCoroutine)];
  });

  define(lib, 'isyieldable', (_) {
    final co = vm.current;
    return one(co != null && co.nativeDepth == 0);
  });
}

import 'package:test/test.dart';
import 'package:wasm_components/src/runtime/resource.dart';

final class _Res extends Resource {
  _Res.own(int handle, List<int> drops)
    : super.owned(handle, (h) => drops.add(h));
  _Res.borrowed(int handle) : super.borrowed(handle);
}

void main() {
  late List<int> drops;
  setUp(() => drops = []);

  test('owned resources are dropped when the scope exits', () {
    final scope = ResourceScope.enter();
    final a = _Res.own(1, drops);
    final b = _Res.own(2, drops);
    expect(drops, isEmpty);
    scope.exit();
    expect(drops, [1, 2]);
    expect(a.isValid, isFalse);
    expect(b.isValid, isFalse);
  });

  test('borrowed resources are invalidated but not dropped', () {
    final scope = ResourceScope.enter();
    final borrowed = _Res.borrowed(7);
    expect(borrowed.resourceHandle, 7);
    scope.exit();
    expect(drops, isEmpty);
    expect(borrowed.isValid, isFalse);
    expect(() => borrowed.resourceHandle, throwsStateError);
  });

  test('transferring ownership invalidates without dropping', () {
    final scope = ResourceScope.enter();
    final resource = _Res.own(3, drops);
    expect(resource.takeHandle(), 3);
    expect(resource.isValid, isFalse);
    scope.exit();
    expect(drops, isEmpty);
  });

  test('keep() survives the scope until disposed', () {
    final scope = ResourceScope.enter();
    final kept = _Res.own(4, drops).keep();
    scope.exit();
    expect(drops, isEmpty);
    expect(kept.isValid, isTrue);
    kept.dispose();
    kept.dispose(); // Idempotent.
    expect(drops, [4]);
  });

  test('borrowed resources cannot be kept', () {
    final scope = ResourceScope.enter();
    expect(() => _Res.borrowed(1).keep(), throwsStateError);
    scope.exit();
  });

  test('a borrowed resource cannot be given away', () {
    final scope = ResourceScope.enter();
    expect(() => _Res.borrowed(1).takeHandle(), throwsStateError);
    scope.exit();
  });

  test('scopes nest', () {
    final outer = ResourceScope.enter();
    final a = _Res.own(1, drops);
    final inner = ResourceScope.enter();
    _Res.own(2, drops);
    expect(ResourceScope.current, same(inner));
    inner.exit();
    expect(drops, [2]);
    expect(ResourceScope.current, same(outer));
    expect(a.isValid, isTrue);
    outer.exit();
    expect(drops, [2, 1]);
    expect(ResourceScope.current, isNull);
  });

  test('held scopes keep owned resources until released', () {
    final scope = ResourceScope.enter();
    final owned = _Res.own(5, drops);
    final borrowed = _Res.borrowed(6);
    scope.hold();
    scope.exit();
    expect(drops, isEmpty);
    expect(owned.isValid, isTrue);
    expect(borrowed.isValid, isFalse);
    scope.release();
    expect(drops, [5]);
  });

  test('resources created while running inside a held scope belong to it', () {
    final scope = ResourceScope.enter();
    scope.hold();
    scope.exit();

    final late = scope.run(() => _Res.own(8, drops));
    expect(drops, isEmpty);
    scope.release();
    expect(drops, [8]);
    expect(late.isValid, isFalse);
  });

  test('resources created outside of any scope are untracked', () {
    final resource = _Res.own(9, drops);
    expect(ResourceScope.current, isNull);
    resource.dispose();
    expect(drops, [9]);
  });
}

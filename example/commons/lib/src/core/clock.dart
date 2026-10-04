/// A source of the current time, so time-dependent logic can be tested.
abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock that only moves when told to, for tests.
final class FakeClock implements Clock {
  DateTime _now;

  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 1, 1);

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
  void set(DateTime to) => _now = to;
}

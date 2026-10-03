import 'package:pumpkin_api/src/command_help.dart';
import 'package:test/test.dart';

void main() {
  test('cooldown tracker', () {
    var now = DateTime.utc(2026, 1, 1);
    final tracker = CooldownTracker(now: () => now);
    const cooldown = Duration(seconds: 30);

    expect(tracker.remaining('a', cooldown), isNull);
    tracker.mark('a');
    expect(tracker.remaining('a', cooldown), const Duration(seconds: 30));
    expect(tracker.remaining('b', cooldown), isNull);

    now = now.add(const Duration(seconds: 12));
    expect(tracker.remaining('a', cooldown), const Duration(seconds: 18));
    expect(formatDuration(tracker.remaining('a', cooldown)!), '18s');

    now = now.add(const Duration(seconds: 18));
    expect(tracker.remaining('a', cooldown), isNull);

    tracker.mark('a');
    tracker.clear('a');
    expect(tracker.remaining('a', cooldown), isNull);
    tracker.mark('a');
    tracker.reset();
    expect(tracker.remaining('a', cooldown), isNull);
  });
}

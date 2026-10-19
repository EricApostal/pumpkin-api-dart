// The English texts of the waiting statuses (`CreateLang.translateDirect`), rendered on the
// server because display links write plain strings. Pure.
import '../../redstone/support/text.dart' show Txt;

const Map<String, String> kScheduleEnglish = {
  'generic.daytime.am': 'am',
  'generic.daytime.pm': 'pm',
  'generic.daytime.second': 'Second',
  'generic.daytime.minute': 'Minute',
  'generic.unit.seconds': 'Seconds',
  'generic.unit.minutes': 'Minutes',
  'schedule.condition.delay.status': 'Departs in %1\$s',
  'schedule.condition.idle.status': 'Cargo Idle for %1\$s',
  'schedule.condition.player_count.status': 'Passengers: %1\$s/%2\$s',
  'schedule.condition.powered.status': 'Waiting for redstone',
  'schedule.condition.redstone_link.status': 'Waiting for redstone link',
  'schedule.condition.threshold.status': 'Cargo: %1\$s/%2\$s %3\$s',
  'schedule.condition.threshold.items': 'Items',
  'schedule.condition.threshold.stacks': 'Stacks',
  'schedule.condition.threshold.buckets': 'Buckets',
  'schedule.condition.time_of_day.digital_format': '%1\$s:%3\$s %4\$s',
  'schedule.condition.time_of_day.status': 'Departs at ',
  'schedule.condition.unloaded.status': 'Waiting for chunk unload',
};

/// `CreateLang.translateDirect(key, args)` for the keys of [kScheduleEnglish], as a literal text.
/// An unknown key renders as `create.<key>`.
Txt translateDirect(String key, [List<Object> args = const []]) {
  final template = kScheduleEnglish[key];
  if (template == null) return Txt.literal('create.$key');
  var i = 0;
  final text = template.replaceAllMapped(RegExp(r'%(?:(\d+)\$)?([sd%])'), (m) {
    if (m.group(2) == '%') return '%';
    final index = m.group(1) != null ? int.parse(m.group(1)!) - 1 : i++;
    return index >= 0 && index < args.length ? _plain(args[index]) : '';
  });
  return Txt.literal(text);
}

String _plain(Object o) => o is Txt ? o.plain : '$o';

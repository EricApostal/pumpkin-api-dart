import 'bindings.g.dart' hide Text;
import 'messages.dart';
import 'pagination.dart';

export 'pagination.dart';

/// A position, as the generated API uses it.
typedef FeedbackPos = (double, double, double);

/// Sounds and particles for a player.
extension FeedbackPlayer on Player {
  /// Plays [sound] to this player, at their position or [at].
  ///
  /// ```dart
  /// player.sound(Sound.entityPlayerLevelup);
  /// ```
  void sound(
    Sound sound, {
    SoundCategory category = SoundCategory.master,
    double volume = 1,
    double pitch = 1,
    FeedbackPos? at,
  }) {
    if (at == null) {
      playSound(sound: sound, category: category, volume: volume, pitch: pitch);
    } else {
      playSoundAt(pos: at, sound: sound, category: category, volume: volume, pitch: pitch);
    }
  }

  /// Plays a resource pack sound by id (like `mypack:ding`) to this player.
  void customSound(
    String name, {
    SoundCategory category = SoundCategory.master,
    double volume = 1,
    double pitch = 1,
    FeedbackPos? at,
  }) {
    if (at == null) {
      playCustomSound(soundName: name, category: category, volume: volume, pitch: pitch);
    } else {
      playCustomSoundAt(pos: at, soundName: name, category: category, volume: volume, pitch: pitch);
    }
  }

  /// Spawns [particle] that only this player sees, at their position or [at].
  /// [offset] spreads the particles, [speed] is their max speed.
  void particle(
    Particle particle, {
    FeedbackPos? at,
    int count = 1,
    FeedbackPos offset = (0, 0, 0),
    double speed = 0,
  }) => spawnParticles(
    particle: particle,
    pos: at ?? getPosition(),
    count: count,
    offset: offset,
    maxSpeed: speed,
  );
}

/// Sounds and particles for everyone in a world.
extension FeedbackWorld on World {
  /// Plays [sound] at [at] for all players in the world.
  void sound(
    Sound sound,
    FeedbackPos at, {
    SoundCategory category = SoundCategory.master,
    double volume = 1,
    double pitch = 1,
  }) => playSound(sound: sound, category: category, pos: at, volume: volume, pitch: pitch);

  /// Spawns [particle] at [at] for all players in the world.
  ///
  /// ```dart
  /// world.particle(Particle.flame, (x, y, z), count: 10, offset: (0.3, 0.3, 0.3));
  /// ```
  void particle(
    Particle particle,
    FeedbackPos at, {
    int count = 1,
    FeedbackPos offset = (0, 0, 0),
    double speed = 0,
  }) => spawnParticle(
    particle: particle,
    pos: at,
    offset: offset,
    maxSpeed: speed,
    count: count,
  );
}

/// Sending paginated lists.
extension FeedbackPages on CommandSender {
  /// Sends page [number] (1-based, clamped) of [pages]: a header like
  /// `§e--- Homes (1/3) ---`, a line per item from [format], and a footer.
  ///
  /// With [command] (a template containing `{page}`, like `/homes {page}`) the
  /// footer has clickable previous/next buttons.
  ///
  /// ```dart
  /// sender.sendPage(Paginator(names, pageSize: 8), 1, title: 'Homes',
  ///     format: (name, i) => '&7${i + 1}. &f$name', command: '/homes {page}');
  /// ```
  void sendPage<T>(
    Paginator<T> pages,
    int number, {
    required String title,
    required String Function(T item, int index) format,
    String? command,
  }) {
    final page = pages.page(number);
    final r = renderPage(page, title: title, format: format);
    send(r.header);
    for (final line in r.lines) {
      send(line);
    }
    if (command != null && page.count > 1) {
      final footer = Text.empty();
      footer.add(page.hasPrevious
          ? Text('« Prev').yellow().runCommand(MessageFormat.format(command, {'page': page.number - 1}))
          : Text('« Prev').darkGray());
      footer.add(Text(' | ').gray());
      footer.add(page.hasNext
          ? Text('Next »').yellow().runCommand(MessageFormat.format(command, {'page': page.number + 1}))
          : Text('Next »').darkGray());
      send(footer);
    } else {
      send(r.footer);
    }
  }
}

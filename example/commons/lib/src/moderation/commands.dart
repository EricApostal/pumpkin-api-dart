/// Registers the moderation commands. They only translate between the server
/// and `ModerationService`: parse the arguments, ask the service, then tell
/// the staff and carry the punishment out on the player.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/clock.dart';
import 'enforcement.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'span.dart';

/// Lengths offered by tab completion.
const _suggestedLengths = ['30m', '1h', '12h', '1d', '7d', '30d'];

/// The moderation commands.
final class ModerationCommands {
  final ModerationService service;
  final ModerationMessages messages;
  final Enforcement enforcement;
  final Clock clock;

  ModerationCommands({
    required this.service,
    required this.messages,
    required this.enforcement,
    required this.clock,
  });

  /// Registers every command on [context].
  void register(Context context) {
    _registerPunishments(context);
    _registerRevocations(context);
    _registerLookups(context);
    _registerStaffTools(context);
  }

  // -- Helpers ----------------------------------------------------------------

  Never _fail(String key, [Map<String, Object?> values = const {}]) =>
      throw CommandException(messages.error(key, values));

  Actor _actor(CommandContext ctx) => ctx.isPlayer
      ? Actor(ctx.player.uuidString, ctx.senderName)
      : Actor.console(ctx.senderName);

  /// The player named by the argument [key]: someone who joined before, or
  /// who is online right now.
  Target _target(CommandContext ctx, String key) {
    final name = ctx.string(key);
    var target = service.find(name);
    if (target == null) {
      final online = ctx.server.getPlayerByName(name: name);
      if (online != null) target = Target(online.uuidString, online.getName());
    }
    if (target == null) _fail('player.unknown', {'name': name});
    enforcement.refreshProtection(ctx.server, target.uuid);
    return target;
  }

  /// The new punishment of [result], or a message saying why there is none.
  Punishment _issued(IssueResult result, Target target) {
    final punishment = result.punishment;
    if (punishment != null) return punishment;
    final existing = result.existing;
    final values = {
      'name': target.name,
      'remaining': existing == null
          ? ''
          : messages.remaining(existing, clock.now()),
    };
    switch (result.refusal!) {
      case Refusal.self:
        _fail('issue.self');
      case Refusal.protected:
        _fail('issue.protected', values);
      case Refusal.alreadyMuted:
        _fail('issue.alreadyMuted', values);
      case Refusal.alreadyBanned:
        _fail('issue.alreadyBanned', values);
    }
  }

  /// Tells staff about a new punishment and carries it out on the player.
  void _carryOut(
    CommandContext ctx,
    Actor issuer,
    Punishment punishment, {
    Punishment? escalation,
  }) {
    enforcement.announce(
      ctx.server,
      ctx.sender,
      issuer,
      messages.notice(punishment),
    );
    enforcement.enforce(ctx.server, punishment);
    if (escalation != null) {
      enforcement.notifyStaff(ctx.server, messages.notice(escalation));
      enforcement.enforce(ctx.server, escalation);
    }
  }

  Iterable<String> _knownNames(SuggestionContext _) => service.knownNames;

  Iterable<String> _onlineNames(SuggestionContext s) => [
    for (final player in s.server.getAllPlayers()) player.getName(),
  ];

  Iterable<String> Function(SuggestionContext) _namesWith(
    PunishmentType type,
  ) =>
      (_) => service.namesWith(type);

  /// A length argument: `30m`, `12h`, `7d` (and `perm` where [allowPermanent]).
  ArgType _lengthArgument({required bool allowPermanent}) => ArgType(
    ArgumentTypes.word,
    label: 'duration',
    choices: [..._suggestedLengths, if (allowPermanent) permanentWords.first],
    validate: (raw) {
      final span = parseSpan(raw);
      if (span == null) _fail('duration.invalid', {'input': raw});
      if (span.length == null && !allowPermanent) _fail('duration.finite');
      return raw;
    },
  );

  // -- Punishing --------------------------------------------------------------

  void _registerPunishments(Context context) {
    context.command(
      'warn',
      description: 'Warn a player',
      permission: ModerationPerms.warn.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _knownNames,
        build: (p) => p.arg('reason', ArgumentTypes.greedyString, runs: _warn),
      ),
    );

    context.command(
      'mute',
      description: 'Mute a player, for a while or for good',
      permission: ModerationPerms.mute.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _knownNames,
        runs: _mute,
        build: (p) => p.arg(
          'details',
          const ArgType(
            ArgumentTypes.greedyString,
            label: 'duration reason...',
          ),
          optional: true,
          // The first word is a length when it looks like one, see _mute.
          suggestsWith: (s) => s.typed.contains(' ')
              ? const []
              : [..._suggestedLengths, permanentWords.first],
          runs: _mute,
        ),
      ),
    );

    context.command(
      'ban',
      description: 'Ban a player permanently',
      permission: ModerationPerms.ban.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _knownNames,
        runs: (ctx) => _ban(ctx, lengthText: null),
        build: (p) => p.arg(
          'reason',
          ArgumentTypes.greedyString,
          optional: true,
          runs: (ctx) => _ban(ctx, lengthText: null),
        ),
      ),
    );

    context.command(
      'tempban',
      description: 'Ban a player for a while',
      permission: ModerationPerms.tempban.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _knownNames,
        build: (p) => p.arg(
          'duration',
          _lengthArgument(allowPermanent: false),
          runs: (ctx) => _ban(ctx, lengthText: ctx.string('duration')),
          build: (d) => d.arg(
            'reason',
            ArgumentTypes.greedyString,
            optional: true,
            runs: (ctx) => _ban(ctx, lengthText: ctx.string('duration')),
          ),
        ),
      ),
    );

    context.command(
      'kick',
      description: 'Remove a player from the server',
      permission: ModerationPerms.kick.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _onlineNames,
        runs: _kick,
        build: (p) => p.arg(
          'reason',
          ArgumentTypes.greedyString,
          optional: true,
          runs: _kick,
        ),
      ),
    );
  }

  void _warn(CommandContext ctx) {
    final issuer = _actor(ctx);
    final target = _target(ctx, 'player');
    final result = service.warn(
      issuer,
      target,
      reason: ctx.stringOrNull('reason'),
    );
    _carryOut(
      ctx,
      issuer,
      _issued(result, target),
      escalation: result.escalation,
    );
  }

  void _mute(CommandContext ctx) {
    final issuer = _actor(ctx);
    final target = _target(ctx, 'player');
    final typed = splitSpanAndReason(ctx.stringOrNull('details'));
    final length = typed.span == null
        ? service.config.defaultMuteLength
        : typed.span!.length;
    final result = service.mute(
      issuer,
      target,
      duration: length,
      reason: typed.reason,
    );
    _carryOut(ctx, issuer, _issued(result, target));
  }

  /// Bans for [lengthText] (already validated, as typed) or permanently when
  /// it is `null`.
  void _ban(CommandContext ctx, {required String? lengthText}) {
    final issuer = _actor(ctx);
    final target = _target(ctx, 'player');
    final result = service.ban(
      issuer,
      target,
      duration: lengthText == null ? null : parseSpan(lengthText)!.length,
      reason: ctx.stringOrNull('reason'),
    );
    _carryOut(ctx, issuer, _issued(result, target));
  }

  void _kick(CommandContext ctx) {
    final issuer = _actor(ctx);
    final target = _target(ctx, 'player');
    if (enforcement.online(ctx.server, target.uuid) == null) {
      _fail('player.offline', {'name': target.name});
    }
    final result = service.kick(
      issuer,
      target,
      reason: ctx.stringOrNull('reason'),
    );
    _carryOut(ctx, issuer, _issued(result, target));
  }

  // -- Taking punishments back ------------------------------------------------

  void _registerRevocations(Context context) {
    context.command(
      'unmute',
      description: 'Lift a mute',
      permission: ModerationPerms.unmute.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _namesWith(PunishmentType.mute),
        runs: (ctx) => _revoke(ctx, 'revoke.notMuted', service.unmute),
      ),
    );

    context.command(
      'unban',
      description: 'Lift a ban',
      permission: ModerationPerms.unban.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _namesWith(PunishmentType.ban),
        runs: (ctx) => _revoke(ctx, 'revoke.notBanned', service.unban),
      ),
    );

    context.command(
      'unwarn',
      description:
          'Take back the latest warning, or the warning with the given id',
      permission: ModerationPerms.unwarn.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _namesWith(PunishmentType.warn),
        runs: _unwarn,
        build: (p) => p.arg(
          'id',
          ArgumentTypes.integer(min: 1),
          optional: true,
          runs: _unwarn,
        ),
      ),
    );
  }

  void _revoke(
    CommandContext ctx,
    String missingKey,
    Punishment? Function(Actor by, String uuid) revoke,
  ) {
    final issuer = _actor(ctx);
    final target = _target(ctx, 'player');
    final revoked = revoke(issuer, target.uuid);
    if (revoked == null) _fail(missingKey, {'name': target.name});
    enforcement.announce(
      ctx.server,
      ctx.sender,
      issuer,
      messages.revokeNotice(revoked, issuer.name),
    );
    if (revoked.type == PunishmentType.mute) {
      enforcement
          .online(ctx.server, target.uuid)
          ?.send(messages.chat('target.unmute'));
    }
  }

  void _unwarn(CommandContext ctx) {
    final issuer = _actor(ctx);
    final target = _target(ctx, 'player');
    final id = ctx.integerOrNull('id');
    final revoked = service.unwarn(issuer, target.uuid, id: id);
    if (revoked == null) {
      if (id == null) _fail('revoke.noWarning', {'name': target.name});
      _fail('revoke.warningNotFound', {'name': target.name, 'id': id});
    }
    enforcement.announce(
      ctx.server,
      ctx.sender,
      issuer,
      messages.revokeNotice(revoked, issuer.name),
    );
  }

  // -- Looking things up ------------------------------------------------------

  void _registerLookups(Context context) {
    context.command(
      'history',
      description: 'Show the punishments of a player',
      permission: ModerationPerms.history.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _knownNames,
        runs: _history,
        build: (p) => p.arg(
          'page',
          ArgumentTypes.integer(min: 1),
          optional: true,
          runs: _history,
        ),
      ),
    );

    context.command(
      'punishments',
      description:
          'List recent punishments, or only the mutes and bans in force',
      permission: ModerationPerms.punishments.node,
      (c) => c
        ..arg(
          'page',
          ArgumentTypes.integer(min: 1),
          optional: true,
          runs: (ctx) => _recent(ctx, activeOnly: false),
        )
        ..sub(
          'active',
          description: 'Only the mutes and bans in force',
          runs: (ctx) => _recent(ctx, activeOnly: true),
          build: (s) => s.arg(
            'page',
            ArgumentTypes.integer(min: 1),
            optional: true,
            runs: (ctx) => _recent(ctx, activeOnly: true),
          ),
        ),
    );

    context.command(
      'checkban',
      description: 'Show the ban, mute and warnings of a player',
      permission: ModerationPerms.checkban.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        suggestsWith: _knownNames,
        runs: _checkBan,
      ),
    );
  }

  void _history(CommandContext ctx) {
    final target = _target(ctx, 'player');
    final records = service.history(target.uuid);
    if (records.isEmpty) {
      ctx.sender.send(
        messages.chat('history.empty', {
          'name': MessageFormat.escape(target.name),
        }),
      );
      return;
    }
    final now = clock.now();
    ctx.sender.sendPage(
      Paginator(records, pageSize: service.config.pageSize),
      ctx.integerOrNull('page') ?? 1,
      title: messages.plain('history.title', {
        'name': MessageFormat.escape(target.name),
      }),
      format: (record, _) => messages.historyLine(record, now),
      command: '/history ${target.name} {page}',
    );
  }

  void _recent(CommandContext ctx, {required bool activeOnly}) {
    final records = activeOnly ? service.activePunishments() : service.recent();
    final which = activeOnly ? 'active' : 'recent';
    if (records.isEmpty) {
      ctx.sender.send(messages.chat('punishments.empty.$which'));
      return;
    }
    final now = clock.now();
    ctx.sender.sendPage(
      Paginator(records, pageSize: service.config.pageSize),
      ctx.integerOrNull('page') ?? 1,
      title: messages.plain('punishments.title.$which'),
      format: (record, _) => messages.punishmentsLine(record, now),
      command: activeOnly
          ? '/punishments active {page}'
          : '/punishments {page}',
    );
  }

  void _checkBan(CommandContext ctx) {
    final target = _target(ctx, 'player');
    final lines = messages.check(
      name: target.name,
      ban: service.activeBan(target.uuid),
      mute: service.activeMuteRecord(target.uuid),
      activeWarns: service.activeWarns(target.uuid).length,
      totalPunishments: service.history(target.uuid).length,
      now: clock.now(),
    );
    for (final line in lines) {
      ctx.sender.send(line);
    }
  }

  // -- Staff tools ------------------------------------------------------------

  void _registerStaffTools(Context context) {
    context.command(
      'vanish',
      description: 'Hide from other players, or show yourself again',
      aliases: ['v'],
      permission: ModerationPerms.vanish.node,
      (c) => c
        ..requirePlayer()
        ..arg(
          'state',
          ArgumentTypes.oneOf(['on', 'off']),
          optional: true,
          runs: _vanish,
        ),
    );

    context.command(
      'staffchat',
      description: 'Talk to staff only: toggle it, or send one message',
      aliases: ['sc'],
      permission: ModerationPerms.staffchat.node,
      (c) => c
        ..runs(_toggleStaffChat)
        ..arg('message', ArgumentTypes.greedyString, runs: _staffMessage),
    );
  }

  void _vanish(CommandContext ctx) {
    final player = ctx.player;
    final uuid = player.uuidString;
    final wanted = switch (ctx.stringOrNull('state')) {
      'on' => true,
      'off' => false,
      _ => !service.isVanished(uuid),
    };
    if (wanted == service.isVanished(uuid)) {
      ctx.reply(
        wanted ? 'You are already vanished.' : 'You are already visible.',
      );
      return;
    }
    enforcement.setVanished(player, vanished: wanted);
    ctx.sender.send(messages.chat(wanted ? 'vanish.on' : 'vanish.off'));
    enforcement.notifyStaff(
      ctx.server,
      messages.chat(wanted ? 'notice.vanish.on' : 'notice.vanish.off', {
        'player': MessageFormat.escape(player.getName()),
      }),
      except: uuid,
    );
  }

  void _toggleStaffChat(CommandContext ctx) {
    final uuid = ctx.player.uuidString;
    final joined = enforcement.staffChatMembers.add(uuid);
    if (!joined) enforcement.staffChatMembers.remove(uuid);
    ctx.sender.send(messages.chat(joined ? 'staffchat.on' : 'staffchat.off'));
  }

  void _staffMessage(CommandContext ctx) => enforcement.sendStaffChat(
    ctx.server,
    ctx.senderName,
    ctx.string('message'),
  );
}

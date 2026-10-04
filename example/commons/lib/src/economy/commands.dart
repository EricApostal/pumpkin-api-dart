import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/players.dart';
import 'amount.dart';
import 'messages.dart';
import 'permissions.dart';
import 'service.dart';

typedef _Who = ({String uuid, String name});

/// A large payment waiting for `/pay confirm`. Only data, no player handles.
typedef _Payment = ({String to, int amount});

String _uuidOf(Player player) => player.asEntity().getUuid().asString;

/// `/balance`, `/pay`, `/baltop` and `/eco`.
final class EconomyCommands {
  final EconomyService _economy;
  final PlayerDirectory _players;
  final MessageCatalog _messages;
  final ModuleHost _host;
  final ConfirmationManager<_Payment> _confirmations;

  EconomyCommands(this._host, this._economy, this._players)
    : _messages = _host.messages(economyMessages),
      _confirmations = ConfirmationManager(
        defaultTtl: _economy.config.confirmTimeout,
        now: _host.clock.now,
      );

  void register() {
    final context = _host.context;
    context.command(
      'balance',
      description: 'Show your balance',
      aliases: ['bal'],
      permission: EconomyPerms.balance.node,
      (c) => c
        ..arg(
          'player',
          ArgumentTypes.word,
          optional: true,
          suggestsWith: (s) => _players.names,
          runs: _balance,
          build: (a) => a.requirePermission(EconomyPerms.balanceOthers.node),
        )
        ..sub(
          'history',
          description: 'Show recent transactions',
          build: (h) => h.arg(
            'player',
            ArgumentTypes.word,
            optional: true,
            suggestsWith: (s) => _players.names,
            runs: _history,
            build: (a) => a.requirePermission(EconomyPerms.balanceOthers.node),
          ),
        ),
    );

    context.command(
      'pay',
      description: 'Pay another player',
      permission: EconomyPerms.pay.node,
      (c) => c
        ..requirePlayer()
        ..runs((ctx) => ctx.failUsage())
        ..sub('confirm', description: 'Confirm a large payment', runs: _confirm)
        ..sub('cancel', description: 'Cancel a large payment', runs: _cancel)
        ..arg(
          'player',
          ArgumentTypes.word,
          suggestsWith: (s) => [
            for (final name in _players.names)
              if (name != s.senderName) name,
          ],
          build: (p) => p.arg(
            'amount',
            ArgumentTypes.word,
            suggests: const ['10', '100', '1k'],
            runs: _payCommand,
          ),
        ),
    );

    context.command(
      'baltop',
      description: 'Show the richest players',
      aliases: ['balancetop'],
      permission: EconomyPerms.baltop.node,
      (c) => c.arg(
        'page',
        ArgumentTypes.integer(min: 1),
        optional: true,
        runs: _baltop,
      ),
    );

    context.command(
      'eco',
      description: 'Manage player balances',
      aliases: ['economy'],
      permission: EconomyPerms.admin.node,
      (c) => c
        ..runs((ctx) => ctx.failUsage())
        ..sub(
          'give',
          description: 'Give money to a player',
          build: (s) => _adminSub(s, _give),
        )
        ..sub(
          'take',
          description: 'Take money from a player',
          build: (s) => _adminSub(s, _take),
        )
        ..sub(
          'set',
          description: 'Set the balance of a player',
          build: (s) => _adminSub(s, _setBalance),
        )
        ..sub(
          'reset',
          description: 'Give a player the starting balance again',
          build: (s) => s.arg(
            'player',
            ArgumentTypes.word,
            suggestsWith: (_) => _players.names,
            runs: _reset,
          ),
        ),
    );
  }

  void _adminSub(CommandBuilder sub, CommandBody run) => sub.arg(
    'player',
    ArgumentTypes.word,
    suggestsWith: (_) => _players.names,
    build: (p) => p.arg(
      'amount',
      ArgumentTypes.word,
      suggests: const ['100', '1k', '10k'],
      runs: run,
    ),
  );

  // -- /balance ---------------------------------------------------------------

  void _balance(CommandContext ctx) {
    final name = ctx.stringOrNull('player');
    final who = name == null ? _self(ctx, 'balance') : _find(name);
    final key = name == null || who.uuid == _selfUuid(ctx)
        ? 'balance.self'
        : 'balance.other';
    ctx.sender.sendTemplate(_messages, key, {
      'player': MessageFormat.escape(who.name),
      'balance': _economy.format(_economy.balance(who.uuid)),
    });
  }

  void _history(CommandContext ctx) {
    final name = ctx.stringOrNull('player');
    final who = name == null ? _self(ctx, 'balance history') : _find(name);
    final values = {'player': MessageFormat.escape(who.name)};
    final entries = _economy.history(who.uuid, limit: 10);
    if (entries.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'history.empty', values);
      return;
    }
    ctx.sender.sendTemplate(_messages, 'history.header', values);
    final now = _host.clock.now();
    for (final entry in entries) {
      final other = entry.other == null
          ? ''
          : MessageFormat.escape(_players.nameOf(entry.other!) ?? 'unknown');
      final kind = _messages['history.${entry.kind.name}'].format({
        'other': other,
      });
      final reason = entry.reason == null
          ? ''
          : ' (${MessageFormat.escape(entry.reason!)})';
      ctx.sender.sendTemplate(_messages, 'history.line', {
        'age': formatDuration(now.difference(entry.at)),
        'change':
            '${entry.change < 0 ? '&c' : '&a'}${_economy.formatChange(entry.change)}',
        'detail': '$kind$reason',
      });
    }
  }

  // -- /pay -------------------------------------------------------------------

  void _payCommand(CommandContext ctx) {
    final payer = _self(ctx, 'pay');
    final target = _find(ctx.string('player'));
    final amount = _amount(ctx);
    _checkPayment(payer, target.uuid, amount);
    if (_economy.needsConfirmation(amount)) {
      _confirmations.request(payer.uuid, (to: target.uuid, amount: amount));
      _askToConfirm(ctx.player, target, amount);
      return;
    }
    _pay(ctx, payer, target, amount);
  }

  void _confirm(CommandContext ctx) {
    final payer = _self(ctx, 'pay');
    final pending = _confirmations.confirm(payer.uuid);
    if (pending == null) _fail('pay.nothing');
    final target = _players.byUuid(pending.to);
    if (target == null) _fail('pay.failed');
    // The money may have moved since the player was asked.
    _checkPayment(payer, pending.to, pending.amount);
    _pay(ctx, payer, (uuid: target.uuid, name: target.name), pending.amount);
  }

  void _cancel(CommandContext ctx) {
    if (!_confirmations.cancel(_self(ctx, 'pay').uuid)) _fail('pay.nothing');
    ctx.sender.sendTemplate(_messages, 'pay.cancelled');
  }

  void _checkPayment(_Who payer, String to, int amount) {
    final problem = _economy.payProblem(payer.uuid, to, amount);
    if (problem == null) return;
    final recipient = _players.nameOf(to) ?? 'unknown';
    _fail(
      switch (problem) {
        PayProblem.self => 'pay.self',
        PayProblem.unknownRecipient => 'player.unknown',
        PayProblem.belowMinimum => 'pay.minimum',
        PayProblem.insufficientFunds => 'pay.insufficient',
        PayProblem.recipientFull => 'pay.full',
      },
      {
        'player': recipient,
        'minimum': _economy.format(_economy.config.payMinimum),
        'balance': _economy.format(_economy.balance(payer.uuid)),
      },
    );
  }

  void _askToConfirm(Player payer, _Who target, int amount) {
    final values = {
      'amount': _economy.format(amount),
      'player': MessageFormat.escape(target.name),
      'seconds': _economy.config.confirmSeconds,
    };
    payer.sendTemplate(_messages, 'pay.confirm', values);
    payer.send(
      Text.join([
        Text(_messages['pay.button.confirm'].format())
            .green()
            .bold()
            .runCommand('/pay confirm')
            .hover(_messages['pay.hover.confirm'].format(values)),
        Text(_messages['pay.button.cancel'].format())
            .red()
            .bold()
            .runCommand('/pay cancel'),
      ], separator: ' '),
    );
  }

  void _pay(CommandContext ctx, _Who payer, _Who target, int amount) {
    final result = _economy.transfer(
      payer.uuid,
      target.uuid,
      amount,
      reason: 'Payment',
    );
    if (!result.isOk) _fail('pay.failed');
    final values = {
      'amount': _economy.format(amount),
      'balance': _economy.format(result.balance),
    };
    ctx.sender.sendTemplate(_messages, 'pay.sent', {
      ...values,
      'player': MessageFormat.escape(target.name),
    });
    final received = {
      'amount': values['amount'],
      'balance': _economy.format(_economy.balance(target.uuid)),
      'player': MessageFormat.escape(payer.name),
    };
    _withPlayer(ctx.server, target.uuid, (player) {
      player.sendTemplate(_messages, 'pay.received', received);
      player.actionBar(_messages.text('pay.received.bar', received));
    });
    _host.log.info('${payer.name} paid ${target.name} $amount');
  }

  // -- /baltop ----------------------------------------------------------------

  void _baltop(CommandContext ctx) {
    final board = _economy.leaderboard();
    if (board.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'baltop.empty');
      return;
    }
    ctx.sender.sendPage(
      Paginator(board, pageSize: 10),
      ctx.integerOrNull('page') ?? 1,
      title: _messages['baltop.title'].format(),
      command: '/baltop {page}',
      format: (entry, index) => _messages['baltop.line'].format({
        'rank': index + 1,
        'player': MessageFormat.escape(entry.name),
        'balance': _economy.format(entry.balance),
      }),
    );
    ctx.sender.sendTemplate(_messages, 'baltop.total', {
      'total': _economy.format(_economy.totalSupply),
    });
    if (ctx.isPlayer) {
      final uuid = _uuidOf(ctx.player);
      final rank = _economy.rankOf(uuid);
      if (rank != null) {
        ctx.sender.sendTemplate(_messages, 'baltop.you', {
          'rank': rank,
          'balance': _economy.format(_economy.balance(uuid)),
        });
      }
    }
  }

  // -- /eco -------------------------------------------------------------------

  void _give(CommandContext ctx) {
    final target = _find(ctx.string('player'));
    final amount = _amount(ctx, min: 1);
    final result = _economy.deposit(
      target.uuid,
      amount,
      reason: _admin(ctx, 'give'),
    );
    if (!result.isOk) _failEco(result, target);
    _adminDone(ctx, 'give', target, amount: amount, balance: result.balance);
  }

  void _take(CommandContext ctx) {
    final target = _find(ctx.string('player'));
    final amount = _amount(ctx, min: 1);
    final result = _economy.withdraw(
      target.uuid,
      amount,
      reason: _admin(ctx, 'take'),
    );
    if (!result.isOk) _failEco(result, target);
    _adminDone(ctx, 'take', target, amount: amount, balance: result.balance);
  }

  void _setBalance(CommandContext ctx) {
    final target = _find(ctx.string('player'));
    final amount = _amount(ctx);
    final result = _economy.set(
      target.uuid,
      amount,
      reason: _admin(ctx, 'set'),
    );
    if (!result.isOk) _failEco(result, target);
    _adminDone(ctx, 'set', target, amount: amount, balance: result.balance);
  }

  void _reset(CommandContext ctx) {
    final target = _find(ctx.string('player'));
    final result = _economy.reset(target.uuid, reason: _admin(ctx, 'reset'));
    if (!result.isOk) _failEco(result, target);
    _adminDone(ctx, 'reset', target, amount: 0, balance: result.balance);
  }

  String _admin(CommandContext ctx, String action) =>
      'Admin ${ctx.senderName}: $action';

  void _failEco(Transaction result, _Who target) {
    final key = switch (result.failure!) {
      TransactionFailure.insufficientFunds => 'eco.insufficient',
      TransactionFailure.invalidAmount => 'eco.tooMuch',
      TransactionFailure.unknownAccount => 'player.unknown',
    };
    _fail(key, {
      'player': target.name,
      'balance': _economy.format(result.balance),
      'max': _economy.format(_economy.config.maxBalance),
    });
  }

  void _adminDone(
    CommandContext ctx,
    String action,
    _Who target, {
    required int amount,
    required int balance,
  }) {
    ctx.sender.sendTemplate(_messages, 'eco.$action', {
      'player': MessageFormat.escape(target.name),
      'amount': _economy.format(amount),
      'balance': _economy.format(balance),
    });
    _host.log.info(
      '${ctx.senderName} used /eco $action on ${target.name} ($amount): balance $balance',
    );
    final notify = switch (action) {
      'give' || 'take' || 'set' => 'eco.notify.$action',
      _ => null,
    };
    if (notify == null || target.uuid == _selfUuid(ctx)) return;
    _withPlayer(ctx.server, target.uuid, (player) {
      player.sendTemplate(_messages, notify, {
        'amount': _economy.format(amount),
        'balance': _economy.format(balance),
      });
    });
  }

  // -- Helpers ----------------------------------------------------------------

  /// The sending player. The console is told to name a player instead.
  _Who _self(CommandContext ctx, String command) {
    if (!ctx.isPlayer) _fail('console.needsPlayer', {'command': command});
    final player = ctx.player;
    return (uuid: _uuidOf(player), name: player.getName());
  }

  String? _selfUuid(CommandContext ctx) =>
      ctx.isPlayer ? _uuidOf(ctx.player) : null;

  /// The player called [name], online or not.
  _Who _find(String name) {
    final record = _players.byName(name);
    if (record == null) _fail('player.unknown', {'player': name});
    return (uuid: record.uuid, name: record.name);
  }

  /// The amount argument, at least [min].
  int _amount(CommandContext ctx, {int min = 0}) {
    final int amount;
    try {
      amount = parseAmount(ctx.string('amount'));
    } on AmountException catch (e) {
      ctx.fail(e.message);
    }
    if (amount < min) ctx.fail('The amount must be at least $min.');
    return amount;
  }

  /// Fails the command with the plain text of message [key].
  Never _fail(String key, [Map<String, Object?> values = const {}]) {
    final escaped = {
      for (final MapEntry(:key, :value) in values.entries)
        key: value is String ? MessageFormat.escape(value) : value,
    };
    throw CommandException(
      MessageFormat.stripColors(_messages[key].format(escaped)),
    );
  }

  void _withPlayer(
    Server server,
    String uuid,
    void Function(Player player) deliver,
  ) {
    final player = server.getPlayerByUuid(id: Uuids.parse(uuid));
    if (player != null) deliver(player);
  }
}

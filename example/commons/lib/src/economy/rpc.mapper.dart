// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'rpc.dart';

class EconomyErrorCodeMapper extends EnumMapper<EconomyErrorCode> {
  EconomyErrorCodeMapper._();

  static EconomyErrorCodeMapper? _instance;
  static EconomyErrorCodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EconomyErrorCodeMapper._());
    }
    return _instance!;
  }

  static EconomyErrorCode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  EconomyErrorCode decode(dynamic value) {
    switch (value) {
      case r'unknown_player':
        return EconomyErrorCode.unknownPlayer;
      case r'unknown_account':
        return EconomyErrorCode.unknownAccount;
      case r'insufficient_funds':
        return EconomyErrorCode.insufficientFunds;
      case r'invalid_amount':
        return EconomyErrorCode.invalidAmount;
      case r'disabled':
        return EconomyErrorCode.disabled;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(EconomyErrorCode self) {
    switch (self) {
      case EconomyErrorCode.unknownPlayer:
        return r'unknown_player';
      case EconomyErrorCode.unknownAccount:
        return r'unknown_account';
      case EconomyErrorCode.insufficientFunds:
        return r'insufficient_funds';
      case EconomyErrorCode.invalidAmount:
        return r'invalid_amount';
      case EconomyErrorCode.disabled:
        return r'disabled';
    }
  }
}

extension EconomyErrorCodeMapperExtension on EconomyErrorCode {
  String toValue() {
    EconomyErrorCodeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<EconomyErrorCode>(this) as String;
  }
}

class BalanceQueryMapper extends ClassMapperBase<BalanceQuery> {
  BalanceQueryMapper._();

  static BalanceQueryMapper? _instance;
  static BalanceQueryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BalanceQueryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'BalanceQuery';

  static String _$player(BalanceQuery v) => v.player;
  static const Field<BalanceQuery, String> _f$player = Field(
    'player',
    _$player,
  );

  @override
  final MappableFields<BalanceQuery> fields = const {#player: _f$player};
  @override
  final bool ignoreNull = true;

  static BalanceQuery _instantiate(DecodingData data) {
    return BalanceQuery(player: data.dec(_f$player));
  }

  @override
  final Function instantiate = _instantiate;

  static BalanceQuery fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BalanceQuery>(map);
  }

  static BalanceQuery fromJson(String json) {
    return ensureInitialized().decodeJson<BalanceQuery>(json);
  }
}

mixin BalanceQueryMappable {
  String toJson() {
    return BalanceQueryMapper.ensureInitialized().encodeJson<BalanceQuery>(
      this as BalanceQuery,
    );
  }

  Map<String, dynamic> toMap() {
    return BalanceQueryMapper.ensureInitialized().encodeMap<BalanceQuery>(
      this as BalanceQuery,
    );
  }

  BalanceQueryCopyWith<BalanceQuery, BalanceQuery, BalanceQuery> get copyWith =>
      _BalanceQueryCopyWithImpl<BalanceQuery, BalanceQuery>(
        this as BalanceQuery,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BalanceQueryMapper.ensureInitialized().stringifyValue(
      this as BalanceQuery,
    );
  }

  @override
  bool operator ==(Object other) {
    return BalanceQueryMapper.ensureInitialized().equalsValue(
      this as BalanceQuery,
      other,
    );
  }

  @override
  int get hashCode {
    return BalanceQueryMapper.ensureInitialized().hashValue(
      this as BalanceQuery,
    );
  }
}

extension BalanceQueryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BalanceQuery, $Out> {
  BalanceQueryCopyWith<$R, BalanceQuery, $Out> get $asBalanceQuery =>
      $base.as((v, t, t2) => _BalanceQueryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BalanceQueryCopyWith<$R, $In extends BalanceQuery, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? player});
  BalanceQueryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _BalanceQueryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BalanceQuery, $Out>
    implements BalanceQueryCopyWith<$R, BalanceQuery, $Out> {
  _BalanceQueryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BalanceQuery> $mapper =
      BalanceQueryMapper.ensureInitialized();
  @override
  $R call({String? player}) =>
      $apply(FieldCopyWithData({if (player != null) #player: player}));
  @override
  BalanceQuery $make(CopyWithData data) =>
      BalanceQuery(player: data.get(#player, or: $value.player));

  @override
  BalanceQueryCopyWith<$R2, BalanceQuery, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BalanceQueryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class MoneyRequestMapper extends ClassMapperBase<MoneyRequest> {
  MoneyRequestMapper._();

  static MoneyRequestMapper? _instance;
  static MoneyRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MoneyRequestMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'MoneyRequest';

  static String _$player(MoneyRequest v) => v.player;
  static const Field<MoneyRequest, String> _f$player = Field(
    'player',
    _$player,
  );
  static int _$amount(MoneyRequest v) => v.amount;
  static const Field<MoneyRequest, int> _f$amount = Field('amount', _$amount);
  static String? _$reason(MoneyRequest v) => v.reason;
  static const Field<MoneyRequest, String> _f$reason = Field(
    'reason',
    _$reason,
    opt: true,
  );

  @override
  final MappableFields<MoneyRequest> fields = const {
    #player: _f$player,
    #amount: _f$amount,
    #reason: _f$reason,
  };
  @override
  final bool ignoreNull = true;

  static MoneyRequest _instantiate(DecodingData data) {
    return MoneyRequest(
      player: data.dec(_f$player),
      amount: data.dec(_f$amount),
      reason: data.dec(_f$reason),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MoneyRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MoneyRequest>(map);
  }

  static MoneyRequest fromJson(String json) {
    return ensureInitialized().decodeJson<MoneyRequest>(json);
  }
}

mixin MoneyRequestMappable {
  String toJson() {
    return MoneyRequestMapper.ensureInitialized().encodeJson<MoneyRequest>(
      this as MoneyRequest,
    );
  }

  Map<String, dynamic> toMap() {
    return MoneyRequestMapper.ensureInitialized().encodeMap<MoneyRequest>(
      this as MoneyRequest,
    );
  }

  MoneyRequestCopyWith<MoneyRequest, MoneyRequest, MoneyRequest> get copyWith =>
      _MoneyRequestCopyWithImpl<MoneyRequest, MoneyRequest>(
        this as MoneyRequest,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MoneyRequestMapper.ensureInitialized().stringifyValue(
      this as MoneyRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return MoneyRequestMapper.ensureInitialized().equalsValue(
      this as MoneyRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return MoneyRequestMapper.ensureInitialized().hashValue(
      this as MoneyRequest,
    );
  }
}

extension MoneyRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MoneyRequest, $Out> {
  MoneyRequestCopyWith<$R, MoneyRequest, $Out> get $asMoneyRequest =>
      $base.as((v, t, t2) => _MoneyRequestCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MoneyRequestCopyWith<$R, $In extends MoneyRequest, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? player, int? amount, String? reason});
  MoneyRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MoneyRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MoneyRequest, $Out>
    implements MoneyRequestCopyWith<$R, MoneyRequest, $Out> {
  _MoneyRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MoneyRequest> $mapper =
      MoneyRequestMapper.ensureInitialized();
  @override
  $R call({String? player, int? amount, Object? reason = $none}) => $apply(
    FieldCopyWithData({
      if (player != null) #player: player,
      if (amount != null) #amount: amount,
      if (reason != $none) #reason: reason,
    }),
  );
  @override
  MoneyRequest $make(CopyWithData data) => MoneyRequest(
    player: data.get(#player, or: $value.player),
    amount: data.get(#amount, or: $value.amount),
    reason: data.get(#reason, or: $value.reason),
  );

  @override
  MoneyRequestCopyWith<$R2, MoneyRequest, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MoneyRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TransferRequestMapper extends ClassMapperBase<TransferRequest> {
  TransferRequestMapper._();

  static TransferRequestMapper? _instance;
  static TransferRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TransferRequestMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TransferRequest';

  static String _$from(TransferRequest v) => v.from;
  static const Field<TransferRequest, String> _f$from = Field('from', _$from);
  static String _$to(TransferRequest v) => v.to;
  static const Field<TransferRequest, String> _f$to = Field('to', _$to);
  static int _$amount(TransferRequest v) => v.amount;
  static const Field<TransferRequest, int> _f$amount = Field(
    'amount',
    _$amount,
  );
  static String? _$reason(TransferRequest v) => v.reason;
  static const Field<TransferRequest, String> _f$reason = Field(
    'reason',
    _$reason,
    opt: true,
  );

  @override
  final MappableFields<TransferRequest> fields = const {
    #from: _f$from,
    #to: _f$to,
    #amount: _f$amount,
    #reason: _f$reason,
  };
  @override
  final bool ignoreNull = true;

  static TransferRequest _instantiate(DecodingData data) {
    return TransferRequest(
      from: data.dec(_f$from),
      to: data.dec(_f$to),
      amount: data.dec(_f$amount),
      reason: data.dec(_f$reason),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TransferRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TransferRequest>(map);
  }

  static TransferRequest fromJson(String json) {
    return ensureInitialized().decodeJson<TransferRequest>(json);
  }
}

mixin TransferRequestMappable {
  String toJson() {
    return TransferRequestMapper.ensureInitialized()
        .encodeJson<TransferRequest>(this as TransferRequest);
  }

  Map<String, dynamic> toMap() {
    return TransferRequestMapper.ensureInitialized().encodeMap<TransferRequest>(
      this as TransferRequest,
    );
  }

  TransferRequestCopyWith<TransferRequest, TransferRequest, TransferRequest>
  get copyWith =>
      _TransferRequestCopyWithImpl<TransferRequest, TransferRequest>(
        this as TransferRequest,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TransferRequestMapper.ensureInitialized().stringifyValue(
      this as TransferRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return TransferRequestMapper.ensureInitialized().equalsValue(
      this as TransferRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return TransferRequestMapper.ensureInitialized().hashValue(
      this as TransferRequest,
    );
  }
}

extension TransferRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TransferRequest, $Out> {
  TransferRequestCopyWith<$R, TransferRequest, $Out> get $asTransferRequest =>
      $base.as((v, t, t2) => _TransferRequestCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TransferRequestCopyWith<$R, $In extends TransferRequest, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? from, String? to, int? amount, String? reason});
  TransferRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TransferRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TransferRequest, $Out>
    implements TransferRequestCopyWith<$R, TransferRequest, $Out> {
  _TransferRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TransferRequest> $mapper =
      TransferRequestMapper.ensureInitialized();
  @override
  $R call({String? from, String? to, int? amount, Object? reason = $none}) =>
      $apply(
        FieldCopyWithData({
          if (from != null) #from: from,
          if (to != null) #to: to,
          if (amount != null) #amount: amount,
          if (reason != $none) #reason: reason,
        }),
      );
  @override
  TransferRequest $make(CopyWithData data) => TransferRequest(
    from: data.get(#from, or: $value.from),
    to: data.get(#to, or: $value.to),
    amount: data.get(#amount, or: $value.amount),
    reason: data.get(#reason, or: $value.reason),
  );

  @override
  TransferRequestCopyWith<$R2, TransferRequest, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TransferRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class EconomyReplyMapper extends ClassMapperBase<EconomyReply> {
  EconomyReplyMapper._();

  static EconomyReplyMapper? _instance;
  static EconomyReplyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EconomyReplyMapper._());
      EconomyErrorCodeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EconomyReply';

  static bool _$ok(EconomyReply v) => v.ok;
  static const Field<EconomyReply, bool> _f$ok = Field('ok', _$ok);
  static EconomyErrorCode? _$error(EconomyReply v) => v.error;
  static const Field<EconomyReply, EconomyErrorCode> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static int? _$balance(EconomyReply v) => v.balance;
  static const Field<EconomyReply, int> _f$balance = Field(
    'balance',
    _$balance,
    opt: true,
  );
  static String? _$formatted(EconomyReply v) => v.formatted;
  static const Field<EconomyReply, String> _f$formatted = Field(
    'formatted',
    _$formatted,
    opt: true,
  );

  @override
  final MappableFields<EconomyReply> fields = const {
    #ok: _f$ok,
    #error: _f$error,
    #balance: _f$balance,
    #formatted: _f$formatted,
  };
  @override
  final bool ignoreNull = true;

  static EconomyReply _instantiate(DecodingData data) {
    return EconomyReply(
      ok: data.dec(_f$ok),
      error: data.dec(_f$error),
      balance: data.dec(_f$balance),
      formatted: data.dec(_f$formatted),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EconomyReply fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EconomyReply>(map);
  }

  static EconomyReply fromJson(String json) {
    return ensureInitialized().decodeJson<EconomyReply>(json);
  }
}

mixin EconomyReplyMappable {
  String toJson() {
    return EconomyReplyMapper.ensureInitialized().encodeJson<EconomyReply>(
      this as EconomyReply,
    );
  }

  Map<String, dynamic> toMap() {
    return EconomyReplyMapper.ensureInitialized().encodeMap<EconomyReply>(
      this as EconomyReply,
    );
  }

  EconomyReplyCopyWith<EconomyReply, EconomyReply, EconomyReply> get copyWith =>
      _EconomyReplyCopyWithImpl<EconomyReply, EconomyReply>(
        this as EconomyReply,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return EconomyReplyMapper.ensureInitialized().stringifyValue(
      this as EconomyReply,
    );
  }

  @override
  bool operator ==(Object other) {
    return EconomyReplyMapper.ensureInitialized().equalsValue(
      this as EconomyReply,
      other,
    );
  }

  @override
  int get hashCode {
    return EconomyReplyMapper.ensureInitialized().hashValue(
      this as EconomyReply,
    );
  }
}

extension EconomyReplyValueCopy<$R, $Out>
    on ObjectCopyWith<$R, EconomyReply, $Out> {
  EconomyReplyCopyWith<$R, EconomyReply, $Out> get $asEconomyReply =>
      $base.as((v, t, t2) => _EconomyReplyCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class EconomyReplyCopyWith<$R, $In extends EconomyReply, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({bool? ok, EconomyErrorCode? error, int? balance, String? formatted});
  EconomyReplyCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _EconomyReplyCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, EconomyReply, $Out>
    implements EconomyReplyCopyWith<$R, EconomyReply, $Out> {
  _EconomyReplyCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<EconomyReply> $mapper =
      EconomyReplyMapper.ensureInitialized();
  @override
  $R call({
    bool? ok,
    Object? error = $none,
    Object? balance = $none,
    Object? formatted = $none,
  }) => $apply(
    FieldCopyWithData({
      if (ok != null) #ok: ok,
      if (error != $none) #error: error,
      if (balance != $none) #balance: balance,
      if (formatted != $none) #formatted: formatted,
    }),
  );
  @override
  EconomyReply $make(CopyWithData data) => EconomyReply(
    ok: data.get(#ok, or: $value.ok),
    error: data.get(#error, or: $value.error),
    balance: data.get(#balance, or: $value.balance),
    formatted: data.get(#formatted, or: $value.formatted),
  );

  @override
  EconomyReplyCopyWith<$R2, EconomyReply, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _EconomyReplyCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class CurrencyInfoMapper extends ClassMapperBase<CurrencyInfo> {
  CurrencyInfoMapper._();

  static CurrencyInfoMapper? _instance;
  static CurrencyInfoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CurrencyInfoMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'CurrencyInfo';

  static String _$singular(CurrencyInfo v) => v.singular;
  static const Field<CurrencyInfo, String> _f$singular = Field(
    'singular',
    _$singular,
  );
  static String _$plural(CurrencyInfo v) => v.plural;
  static const Field<CurrencyInfo, String> _f$plural = Field(
    'plural',
    _$plural,
  );
  static String _$symbol(CurrencyInfo v) => v.symbol;
  static const Field<CurrencyInfo, String> _f$symbol = Field(
    'symbol',
    _$symbol,
  );
  static int _$maxBalance(CurrencyInfo v) => v.maxBalance;
  static const Field<CurrencyInfo, int> _f$maxBalance = Field(
    'maxBalance',
    _$maxBalance,
  );

  @override
  final MappableFields<CurrencyInfo> fields = const {
    #singular: _f$singular,
    #plural: _f$plural,
    #symbol: _f$symbol,
    #maxBalance: _f$maxBalance,
  };

  static CurrencyInfo _instantiate(DecodingData data) {
    return CurrencyInfo(
      singular: data.dec(_f$singular),
      plural: data.dec(_f$plural),
      symbol: data.dec(_f$symbol),
      maxBalance: data.dec(_f$maxBalance),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static CurrencyInfo fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<CurrencyInfo>(map);
  }

  static CurrencyInfo fromJson(String json) {
    return ensureInitialized().decodeJson<CurrencyInfo>(json);
  }
}

mixin CurrencyInfoMappable {
  String toJson() {
    return CurrencyInfoMapper.ensureInitialized().encodeJson<CurrencyInfo>(
      this as CurrencyInfo,
    );
  }

  Map<String, dynamic> toMap() {
    return CurrencyInfoMapper.ensureInitialized().encodeMap<CurrencyInfo>(
      this as CurrencyInfo,
    );
  }

  CurrencyInfoCopyWith<CurrencyInfo, CurrencyInfo, CurrencyInfo> get copyWith =>
      _CurrencyInfoCopyWithImpl<CurrencyInfo, CurrencyInfo>(
        this as CurrencyInfo,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return CurrencyInfoMapper.ensureInitialized().stringifyValue(
      this as CurrencyInfo,
    );
  }

  @override
  bool operator ==(Object other) {
    return CurrencyInfoMapper.ensureInitialized().equalsValue(
      this as CurrencyInfo,
      other,
    );
  }

  @override
  int get hashCode {
    return CurrencyInfoMapper.ensureInitialized().hashValue(
      this as CurrencyInfo,
    );
  }
}

extension CurrencyInfoValueCopy<$R, $Out>
    on ObjectCopyWith<$R, CurrencyInfo, $Out> {
  CurrencyInfoCopyWith<$R, CurrencyInfo, $Out> get $asCurrencyInfo =>
      $base.as((v, t, t2) => _CurrencyInfoCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class CurrencyInfoCopyWith<$R, $In extends CurrencyInfo, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? singular, String? plural, String? symbol, int? maxBalance});
  CurrencyInfoCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _CurrencyInfoCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, CurrencyInfo, $Out>
    implements CurrencyInfoCopyWith<$R, CurrencyInfo, $Out> {
  _CurrencyInfoCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<CurrencyInfo> $mapper =
      CurrencyInfoMapper.ensureInitialized();
  @override
  $R call({
    String? singular,
    String? plural,
    String? symbol,
    int? maxBalance,
  }) => $apply(
    FieldCopyWithData({
      if (singular != null) #singular: singular,
      if (plural != null) #plural: plural,
      if (symbol != null) #symbol: symbol,
      if (maxBalance != null) #maxBalance: maxBalance,
    }),
  );
  @override
  CurrencyInfo $make(CopyWithData data) => CurrencyInfo(
    singular: data.get(#singular, or: $value.singular),
    plural: data.get(#plural, or: $value.plural),
    symbol: data.get(#symbol, or: $value.symbol),
    maxBalance: data.get(#maxBalance, or: $value.maxBalance),
  );

  @override
  CurrencyInfoCopyWith<$R2, CurrencyInfo, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _CurrencyInfoCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


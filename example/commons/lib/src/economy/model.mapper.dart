// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class TransactionKindMapper extends EnumMapper<TransactionKind> {
  TransactionKindMapper._();

  static TransactionKindMapper? _instance;
  static TransactionKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TransactionKindMapper._());
    }
    return _instance!;
  }

  static TransactionKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TransactionKind decode(dynamic value) {
    switch (value) {
      case r'deposit':
        return TransactionKind.deposit;
      case r'withdraw':
        return TransactionKind.withdraw;
      case r'transfer_in':
        return TransactionKind.transferIn;
      case r'transfer_out':
        return TransactionKind.transferOut;
      case r'set':
        return TransactionKind.set;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(TransactionKind self) {
    switch (self) {
      case TransactionKind.deposit:
        return r'deposit';
      case TransactionKind.withdraw:
        return r'withdraw';
      case TransactionKind.transferIn:
        return r'transfer_in';
      case TransactionKind.transferOut:
        return r'transfer_out';
      case TransactionKind.set:
        return r'set';
    }
  }
}

extension TransactionKindMapperExtension on TransactionKind {
  String toValue() {
    TransactionKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TransactionKind>(this) as String;
  }
}

class EconomyConfigMapper extends ClassMapperBase<EconomyConfig> {
  EconomyConfigMapper._();

  static EconomyConfigMapper? _instance;
  static EconomyConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EconomyConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'EconomyConfig';

  static String _$currencySingular(EconomyConfig v) => v.currencySingular;
  static const Field<EconomyConfig, String> _f$currencySingular = Field(
    'currencySingular',
    _$currencySingular,
    opt: true,
    def: 'coin',
  );
  static String _$currencyPlural(EconomyConfig v) => v.currencyPlural;
  static const Field<EconomyConfig, String> _f$currencyPlural = Field(
    'currencyPlural',
    _$currencyPlural,
    opt: true,
    def: 'coins',
  );
  static String _$symbol(EconomyConfig v) => v.symbol;
  static const Field<EconomyConfig, String> _f$symbol = Field(
    'symbol',
    _$symbol,
    opt: true,
    def: '',
  );
  static int _$startingBalance(EconomyConfig v) => v.startingBalance;
  static const Field<EconomyConfig, int> _f$startingBalance = Field(
    'startingBalance',
    _$startingBalance,
    opt: true,
    def: 100,
  );
  static int _$payMinimum(EconomyConfig v) => v.payMinimum;
  static const Field<EconomyConfig, int> _f$payMinimum = Field(
    'payMinimum',
    _$payMinimum,
    opt: true,
    def: 1,
  );
  static int _$confirmAbove(EconomyConfig v) => v.confirmAbove;
  static const Field<EconomyConfig, int> _f$confirmAbove = Field(
    'confirmAbove',
    _$confirmAbove,
    opt: true,
    def: 1000,
  );
  static int _$confirmSeconds(EconomyConfig v) => v.confirmSeconds;
  static const Field<EconomyConfig, int> _f$confirmSeconds = Field(
    'confirmSeconds',
    _$confirmSeconds,
    opt: true,
    def: 15,
  );
  static int _$maxBalance(EconomyConfig v) => v.maxBalance;
  static const Field<EconomyConfig, int> _f$maxBalance = Field(
    'maxBalance',
    _$maxBalance,
    opt: true,
    def: 1000000000000,
  );
  static int _$historyPerAccount(EconomyConfig v) => v.historyPerAccount;
  static const Field<EconomyConfig, int> _f$historyPerAccount = Field(
    'historyPerAccount',
    _$historyPerAccount,
    opt: true,
    def: 25,
  );
  static bool _$ipcEnabled(EconomyConfig v) => v.ipcEnabled;
  static const Field<EconomyConfig, bool> _f$ipcEnabled = Field(
    'ipcEnabled',
    _$ipcEnabled,
    opt: true,
    def: true,
  );

  @override
  final MappableFields<EconomyConfig> fields = const {
    #currencySingular: _f$currencySingular,
    #currencyPlural: _f$currencyPlural,
    #symbol: _f$symbol,
    #startingBalance: _f$startingBalance,
    #payMinimum: _f$payMinimum,
    #confirmAbove: _f$confirmAbove,
    #confirmSeconds: _f$confirmSeconds,
    #maxBalance: _f$maxBalance,
    #historyPerAccount: _f$historyPerAccount,
    #ipcEnabled: _f$ipcEnabled,
  };

  static EconomyConfig _instantiate(DecodingData data) {
    return EconomyConfig(
      currencySingular: data.dec(_f$currencySingular),
      currencyPlural: data.dec(_f$currencyPlural),
      symbol: data.dec(_f$symbol),
      startingBalance: data.dec(_f$startingBalance),
      payMinimum: data.dec(_f$payMinimum),
      confirmAbove: data.dec(_f$confirmAbove),
      confirmSeconds: data.dec(_f$confirmSeconds),
      maxBalance: data.dec(_f$maxBalance),
      historyPerAccount: data.dec(_f$historyPerAccount),
      ipcEnabled: data.dec(_f$ipcEnabled),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EconomyConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EconomyConfig>(map);
  }

  static EconomyConfig fromJson(String json) {
    return ensureInitialized().decodeJson<EconomyConfig>(json);
  }
}

mixin EconomyConfigMappable {
  String toJson() {
    return EconomyConfigMapper.ensureInitialized().encodeJson<EconomyConfig>(
      this as EconomyConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return EconomyConfigMapper.ensureInitialized().encodeMap<EconomyConfig>(
      this as EconomyConfig,
    );
  }

  EconomyConfigCopyWith<EconomyConfig, EconomyConfig, EconomyConfig>
  get copyWith => _EconomyConfigCopyWithImpl<EconomyConfig, EconomyConfig>(
    this as EconomyConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return EconomyConfigMapper.ensureInitialized().stringifyValue(
      this as EconomyConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return EconomyConfigMapper.ensureInitialized().equalsValue(
      this as EconomyConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return EconomyConfigMapper.ensureInitialized().hashValue(
      this as EconomyConfig,
    );
  }
}

extension EconomyConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, EconomyConfig, $Out> {
  EconomyConfigCopyWith<$R, EconomyConfig, $Out> get $asEconomyConfig =>
      $base.as((v, t, t2) => _EconomyConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class EconomyConfigCopyWith<$R, $In extends EconomyConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? currencySingular,
    String? currencyPlural,
    String? symbol,
    int? startingBalance,
    int? payMinimum,
    int? confirmAbove,
    int? confirmSeconds,
    int? maxBalance,
    int? historyPerAccount,
    bool? ipcEnabled,
  });
  EconomyConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _EconomyConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, EconomyConfig, $Out>
    implements EconomyConfigCopyWith<$R, EconomyConfig, $Out> {
  _EconomyConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<EconomyConfig> $mapper =
      EconomyConfigMapper.ensureInitialized();
  @override
  $R call({
    String? currencySingular,
    String? currencyPlural,
    String? symbol,
    int? startingBalance,
    int? payMinimum,
    int? confirmAbove,
    int? confirmSeconds,
    int? maxBalance,
    int? historyPerAccount,
    bool? ipcEnabled,
  }) => $apply(
    FieldCopyWithData({
      if (currencySingular != null) #currencySingular: currencySingular,
      if (currencyPlural != null) #currencyPlural: currencyPlural,
      if (symbol != null) #symbol: symbol,
      if (startingBalance != null) #startingBalance: startingBalance,
      if (payMinimum != null) #payMinimum: payMinimum,
      if (confirmAbove != null) #confirmAbove: confirmAbove,
      if (confirmSeconds != null) #confirmSeconds: confirmSeconds,
      if (maxBalance != null) #maxBalance: maxBalance,
      if (historyPerAccount != null) #historyPerAccount: historyPerAccount,
      if (ipcEnabled != null) #ipcEnabled: ipcEnabled,
    }),
  );
  @override
  EconomyConfig $make(CopyWithData data) => EconomyConfig(
    currencySingular: data.get(#currencySingular, or: $value.currencySingular),
    currencyPlural: data.get(#currencyPlural, or: $value.currencyPlural),
    symbol: data.get(#symbol, or: $value.symbol),
    startingBalance: data.get(#startingBalance, or: $value.startingBalance),
    payMinimum: data.get(#payMinimum, or: $value.payMinimum),
    confirmAbove: data.get(#confirmAbove, or: $value.confirmAbove),
    confirmSeconds: data.get(#confirmSeconds, or: $value.confirmSeconds),
    maxBalance: data.get(#maxBalance, or: $value.maxBalance),
    historyPerAccount: data.get(
      #historyPerAccount,
      or: $value.historyPerAccount,
    ),
    ipcEnabled: data.get(#ipcEnabled, or: $value.ipcEnabled),
  );

  @override
  EconomyConfigCopyWith<$R2, EconomyConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _EconomyConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AccountsMapper extends ClassMapperBase<Accounts> {
  AccountsMapper._();

  static AccountsMapper? _instance;
  static AccountsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AccountsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Accounts';

  static Map<String, int> _$balances(Accounts v) => v.balances;
  static const Field<Accounts, Map<String, int>> _f$balances = Field(
    'balances',
    _$balances,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<Accounts> fields = const {#balances: _f$balances};

  static Accounts _instantiate(DecodingData data) {
    return Accounts(balances: data.dec(_f$balances));
  }

  @override
  final Function instantiate = _instantiate;

  static Accounts fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Accounts>(map);
  }

  static Accounts fromJson(String json) {
    return ensureInitialized().decodeJson<Accounts>(json);
  }
}

mixin AccountsMappable {
  String toJson() {
    return AccountsMapper.ensureInitialized().encodeJson<Accounts>(
      this as Accounts,
    );
  }

  Map<String, dynamic> toMap() {
    return AccountsMapper.ensureInitialized().encodeMap<Accounts>(
      this as Accounts,
    );
  }

  AccountsCopyWith<Accounts, Accounts, Accounts> get copyWith =>
      _AccountsCopyWithImpl<Accounts, Accounts>(
        this as Accounts,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AccountsMapper.ensureInitialized().stringifyValue(this as Accounts);
  }

  @override
  bool operator ==(Object other) {
    return AccountsMapper.ensureInitialized().equalsValue(
      this as Accounts,
      other,
    );
  }

  @override
  int get hashCode {
    return AccountsMapper.ensureInitialized().hashValue(this as Accounts);
  }
}

extension AccountsValueCopy<$R, $Out> on ObjectCopyWith<$R, Accounts, $Out> {
  AccountsCopyWith<$R, Accounts, $Out> get $asAccounts =>
      $base.as((v, t, t2) => _AccountsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AccountsCopyWith<$R, $In extends Accounts, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get balances;
  $R call({Map<String, int>? balances});
  AccountsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AccountsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Accounts, $Out>
    implements AccountsCopyWith<$R, Accounts, $Out> {
  _AccountsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Accounts> $mapper =
      AccountsMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get balances =>
      MapCopyWith(
        $value.balances,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(balances: v),
      );
  @override
  $R call({Map<String, int>? balances}) =>
      $apply(FieldCopyWithData({if (balances != null) #balances: balances}));
  @override
  Accounts $make(CopyWithData data) =>
      Accounts(balances: data.get(#balances, or: $value.balances));

  @override
  AccountsCopyWith<$R2, Accounts, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AccountsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LedgerEntryMapper extends ClassMapperBase<LedgerEntry> {
  LedgerEntryMapper._();

  static LedgerEntryMapper? _instance;
  static LedgerEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerEntryMapper._());
      TransactionKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LedgerEntry';

  static DateTime _$at(LedgerEntry v) => v.at;
  static const Field<LedgerEntry, DateTime> _f$at = Field('at', _$at);
  static TransactionKind _$kind(LedgerEntry v) => v.kind;
  static const Field<LedgerEntry, TransactionKind> _f$kind = Field(
    'kind',
    _$kind,
  );
  static int _$change(LedgerEntry v) => v.change;
  static const Field<LedgerEntry, int> _f$change = Field('change', _$change);
  static int _$balance(LedgerEntry v) => v.balance;
  static const Field<LedgerEntry, int> _f$balance = Field('balance', _$balance);
  static String? _$other(LedgerEntry v) => v.other;
  static const Field<LedgerEntry, String> _f$other = Field(
    'other',
    _$other,
    opt: true,
  );
  static String? _$reason(LedgerEntry v) => v.reason;
  static const Field<LedgerEntry, String> _f$reason = Field(
    'reason',
    _$reason,
    opt: true,
  );

  @override
  final MappableFields<LedgerEntry> fields = const {
    #at: _f$at,
    #kind: _f$kind,
    #change: _f$change,
    #balance: _f$balance,
    #other: _f$other,
    #reason: _f$reason,
  };

  static LedgerEntry _instantiate(DecodingData data) {
    return LedgerEntry(
      at: data.dec(_f$at),
      kind: data.dec(_f$kind),
      change: data.dec(_f$change),
      balance: data.dec(_f$balance),
      other: data.dec(_f$other),
      reason: data.dec(_f$reason),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LedgerEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LedgerEntry>(map);
  }

  static LedgerEntry fromJson(String json) {
    return ensureInitialized().decodeJson<LedgerEntry>(json);
  }
}

mixin LedgerEntryMappable {
  String toJson() {
    return LedgerEntryMapper.ensureInitialized().encodeJson<LedgerEntry>(
      this as LedgerEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return LedgerEntryMapper.ensureInitialized().encodeMap<LedgerEntry>(
      this as LedgerEntry,
    );
  }

  LedgerEntryCopyWith<LedgerEntry, LedgerEntry, LedgerEntry> get copyWith =>
      _LedgerEntryCopyWithImpl<LedgerEntry, LedgerEntry>(
        this as LedgerEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LedgerEntryMapper.ensureInitialized().stringifyValue(
      this as LedgerEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return LedgerEntryMapper.ensureInitialized().equalsValue(
      this as LedgerEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return LedgerEntryMapper.ensureInitialized().hashValue(this as LedgerEntry);
  }
}

extension LedgerEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LedgerEntry, $Out> {
  LedgerEntryCopyWith<$R, LedgerEntry, $Out> get $asLedgerEntry =>
      $base.as((v, t, t2) => _LedgerEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LedgerEntryCopyWith<$R, $In extends LedgerEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    DateTime? at,
    TransactionKind? kind,
    int? change,
    int? balance,
    String? other,
    String? reason,
  });
  LedgerEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LedgerEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LedgerEntry, $Out>
    implements LedgerEntryCopyWith<$R, LedgerEntry, $Out> {
  _LedgerEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LedgerEntry> $mapper =
      LedgerEntryMapper.ensureInitialized();
  @override
  $R call({
    DateTime? at,
    TransactionKind? kind,
    int? change,
    int? balance,
    Object? other = $none,
    Object? reason = $none,
  }) => $apply(
    FieldCopyWithData({
      if (at != null) #at: at,
      if (kind != null) #kind: kind,
      if (change != null) #change: change,
      if (balance != null) #balance: balance,
      if (other != $none) #other: other,
      if (reason != $none) #reason: reason,
    }),
  );
  @override
  LedgerEntry $make(CopyWithData data) => LedgerEntry(
    at: data.get(#at, or: $value.at),
    kind: data.get(#kind, or: $value.kind),
    change: data.get(#change, or: $value.change),
    balance: data.get(#balance, or: $value.balance),
    other: data.get(#other, or: $value.other),
    reason: data.get(#reason, or: $value.reason),
  );

  @override
  LedgerEntryCopyWith<$R2, LedgerEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LedgerEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class HistoryMapper extends ClassMapperBase<History> {
  HistoryMapper._();

  static HistoryMapper? _instance;
  static HistoryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HistoryMapper._());
      LedgerEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'History';

  static Map<String, List<LedgerEntry>> _$entries(History v) => v.entries;
  static const Field<History, Map<String, List<LedgerEntry>>> _f$entries =
      Field('entries', _$entries, opt: true, def: const {});

  @override
  final MappableFields<History> fields = const {#entries: _f$entries};

  static History _instantiate(DecodingData data) {
    return History(entries: data.dec(_f$entries));
  }

  @override
  final Function instantiate = _instantiate;

  static History fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<History>(map);
  }

  static History fromJson(String json) {
    return ensureInitialized().decodeJson<History>(json);
  }
}

mixin HistoryMappable {
  String toJson() {
    return HistoryMapper.ensureInitialized().encodeJson<History>(
      this as History,
    );
  }

  Map<String, dynamic> toMap() {
    return HistoryMapper.ensureInitialized().encodeMap<History>(
      this as History,
    );
  }

  HistoryCopyWith<History, History, History> get copyWith =>
      _HistoryCopyWithImpl<History, History>(
        this as History,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return HistoryMapper.ensureInitialized().stringifyValue(this as History);
  }

  @override
  bool operator ==(Object other) {
    return HistoryMapper.ensureInitialized().equalsValue(
      this as History,
      other,
    );
  }

  @override
  int get hashCode {
    return HistoryMapper.ensureInitialized().hashValue(this as History);
  }
}

extension HistoryValueCopy<$R, $Out> on ObjectCopyWith<$R, History, $Out> {
  HistoryCopyWith<$R, History, $Out> get $asHistory =>
      $base.as((v, t, t2) => _HistoryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class HistoryCopyWith<$R, $In extends History, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    List<LedgerEntry>,
    ObjectCopyWith<$R, List<LedgerEntry>, List<LedgerEntry>>
  >
  get entries;
  $R call({Map<String, List<LedgerEntry>>? entries});
  HistoryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _HistoryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, History, $Out>
    implements HistoryCopyWith<$R, History, $Out> {
  _HistoryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<History> $mapper =
      HistoryMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    List<LedgerEntry>,
    ObjectCopyWith<$R, List<LedgerEntry>, List<LedgerEntry>>
  >
  get entries => MapCopyWith(
    $value.entries,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(entries: v),
  );
  @override
  $R call({Map<String, List<LedgerEntry>>? entries}) =>
      $apply(FieldCopyWithData({if (entries != null) #entries: entries}));
  @override
  History $make(CopyWithData data) =>
      History(entries: data.get(#entries, or: $value.entries));

  @override
  HistoryCopyWith<$R2, History, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _HistoryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


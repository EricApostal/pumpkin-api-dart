// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class TradeKindMapper extends EnumMapper<TradeKind> {
  TradeKindMapper._();

  static TradeKindMapper? _instance;
  static TradeKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TradeKindMapper._());
    }
    return _instance!;
  }

  static TradeKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TradeKind decode(dynamic value) {
    switch (value) {
      case r'buy':
        return TradeKind.buy;
      case r'sell':
        return TradeKind.sell;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(TradeKind self) {
    switch (self) {
      case TradeKind.buy:
        return r'buy';
      case TradeKind.sell:
        return r'sell';
    }
  }
}

extension TradeKindMapperExtension on TradeKind {
  String toValue() {
    TradeKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TradeKind>(this) as String;
  }
}

class ShopEntryMapper extends ClassMapperBase<ShopEntry> {
  ShopEntryMapper._();

  static ShopEntryMapper? _instance;
  static ShopEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShopEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ShopEntry';

  static String _$item(ShopEntry v) => v.item;
  static const Field<ShopEntry, String> _f$item = Field('item', _$item);
  static int _$buy(ShopEntry v) => v.buy;
  static const Field<ShopEntry, int> _f$buy = Field('buy', _$buy);
  static int? _$sell(ShopEntry v) => v.sell;
  static const Field<ShopEntry, int> _f$sell = Field('sell', _$sell, opt: true);
  static int _$amount(ShopEntry v) => v.amount;
  static const Field<ShopEntry, int> _f$amount = Field(
    'amount',
    _$amount,
    opt: true,
    def: 1,
  );
  static int _$stack(ShopEntry v) => v.stack;
  static const Field<ShopEntry, int> _f$stack = Field(
    'stack',
    _$stack,
    opt: true,
    def: 64,
  );
  static String? _$permission(ShopEntry v) => v.permission;
  static const Field<ShopEntry, String> _f$permission = Field(
    'permission',
    _$permission,
    opt: true,
  );

  @override
  final MappableFields<ShopEntry> fields = const {
    #item: _f$item,
    #buy: _f$buy,
    #sell: _f$sell,
    #amount: _f$amount,
    #stack: _f$stack,
    #permission: _f$permission,
  };
  @override
  final bool ignoreNull = true;

  static ShopEntry _instantiate(DecodingData data) {
    return ShopEntry(
      item: data.dec(_f$item),
      buy: data.dec(_f$buy),
      sell: data.dec(_f$sell),
      amount: data.dec(_f$amount),
      stack: data.dec(_f$stack),
      permission: data.dec(_f$permission),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ShopEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ShopEntry>(map);
  }

  static ShopEntry fromJson(String json) {
    return ensureInitialized().decodeJson<ShopEntry>(json);
  }
}

mixin ShopEntryMappable {
  String toJson() {
    return ShopEntryMapper.ensureInitialized().encodeJson<ShopEntry>(
      this as ShopEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return ShopEntryMapper.ensureInitialized().encodeMap<ShopEntry>(
      this as ShopEntry,
    );
  }

  ShopEntryCopyWith<ShopEntry, ShopEntry, ShopEntry> get copyWith =>
      _ShopEntryCopyWithImpl<ShopEntry, ShopEntry>(
        this as ShopEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ShopEntryMapper.ensureInitialized().stringifyValue(
      this as ShopEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return ShopEntryMapper.ensureInitialized().equalsValue(
      this as ShopEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ShopEntryMapper.ensureInitialized().hashValue(this as ShopEntry);
  }
}

extension ShopEntryValueCopy<$R, $Out> on ObjectCopyWith<$R, ShopEntry, $Out> {
  ShopEntryCopyWith<$R, ShopEntry, $Out> get $asShopEntry =>
      $base.as((v, t, t2) => _ShopEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ShopEntryCopyWith<$R, $In extends ShopEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? item,
    int? buy,
    int? sell,
    int? amount,
    int? stack,
    String? permission,
  });
  ShopEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ShopEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ShopEntry, $Out>
    implements ShopEntryCopyWith<$R, ShopEntry, $Out> {
  _ShopEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ShopEntry> $mapper =
      ShopEntryMapper.ensureInitialized();
  @override
  $R call({
    String? item,
    int? buy,
    Object? sell = $none,
    int? amount,
    int? stack,
    Object? permission = $none,
  }) => $apply(
    FieldCopyWithData({
      if (item != null) #item: item,
      if (buy != null) #buy: buy,
      if (sell != $none) #sell: sell,
      if (amount != null) #amount: amount,
      if (stack != null) #stack: stack,
      if (permission != $none) #permission: permission,
    }),
  );
  @override
  ShopEntry $make(CopyWithData data) => ShopEntry(
    item: data.get(#item, or: $value.item),
    buy: data.get(#buy, or: $value.buy),
    sell: data.get(#sell, or: $value.sell),
    amount: data.get(#amount, or: $value.amount),
    stack: data.get(#stack, or: $value.stack),
    permission: data.get(#permission, or: $value.permission),
  );

  @override
  ShopEntryCopyWith<$R2, ShopEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ShopEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ShopCategoryMapper extends ClassMapperBase<ShopCategory> {
  ShopCategoryMapper._();

  static ShopCategoryMapper? _instance;
  static ShopCategoryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShopCategoryMapper._());
      ShopEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ShopCategory';

  static String _$id(ShopCategory v) => v.id;
  static const Field<ShopCategory, String> _f$id = Field('id', _$id);
  static String _$name(ShopCategory v) => v.name;
  static const Field<ShopCategory, String> _f$name = Field('name', _$name);
  static String _$icon(ShopCategory v) => v.icon;
  static const Field<ShopCategory, String> _f$icon = Field('icon', _$icon);
  static List<ShopEntry> _$entries(ShopCategory v) => v.entries;
  static const Field<ShopCategory, List<ShopEntry>> _f$entries = Field(
    'entries',
    _$entries,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<ShopCategory> fields = const {
    #id: _f$id,
    #name: _f$name,
    #icon: _f$icon,
    #entries: _f$entries,
  };
  @override
  final bool ignoreNull = true;

  static ShopCategory _instantiate(DecodingData data) {
    return ShopCategory(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      icon: data.dec(_f$icon),
      entries: data.dec(_f$entries),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ShopCategory fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ShopCategory>(map);
  }

  static ShopCategory fromJson(String json) {
    return ensureInitialized().decodeJson<ShopCategory>(json);
  }
}

mixin ShopCategoryMappable {
  String toJson() {
    return ShopCategoryMapper.ensureInitialized().encodeJson<ShopCategory>(
      this as ShopCategory,
    );
  }

  Map<String, dynamic> toMap() {
    return ShopCategoryMapper.ensureInitialized().encodeMap<ShopCategory>(
      this as ShopCategory,
    );
  }

  ShopCategoryCopyWith<ShopCategory, ShopCategory, ShopCategory> get copyWith =>
      _ShopCategoryCopyWithImpl<ShopCategory, ShopCategory>(
        this as ShopCategory,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ShopCategoryMapper.ensureInitialized().stringifyValue(
      this as ShopCategory,
    );
  }

  @override
  bool operator ==(Object other) {
    return ShopCategoryMapper.ensureInitialized().equalsValue(
      this as ShopCategory,
      other,
    );
  }

  @override
  int get hashCode {
    return ShopCategoryMapper.ensureInitialized().hashValue(
      this as ShopCategory,
    );
  }
}

extension ShopCategoryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ShopCategory, $Out> {
  ShopCategoryCopyWith<$R, ShopCategory, $Out> get $asShopCategory =>
      $base.as((v, t, t2) => _ShopCategoryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ShopCategoryCopyWith<$R, $In extends ShopCategory, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, ShopEntry, ShopEntryCopyWith<$R, ShopEntry, ShopEntry>>
  get entries;
  $R call({String? id, String? name, String? icon, List<ShopEntry>? entries});
  ShopCategoryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ShopCategoryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ShopCategory, $Out>
    implements ShopCategoryCopyWith<$R, ShopCategory, $Out> {
  _ShopCategoryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ShopCategory> $mapper =
      ShopCategoryMapper.ensureInitialized();
  @override
  ListCopyWith<$R, ShopEntry, ShopEntryCopyWith<$R, ShopEntry, ShopEntry>>
  get entries => ListCopyWith(
    $value.entries,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(entries: v),
  );
  @override
  $R call({String? id, String? name, String? icon, List<ShopEntry>? entries}) =>
      $apply(
        FieldCopyWithData({
          if (id != null) #id: id,
          if (name != null) #name: name,
          if (icon != null) #icon: icon,
          if (entries != null) #entries: entries,
        }),
      );
  @override
  ShopCategory $make(CopyWithData data) => ShopCategory(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    icon: data.get(#icon, or: $value.icon),
    entries: data.get(#entries, or: $value.entries),
  );

  @override
  ShopCategoryCopyWith<$R2, ShopCategory, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ShopCategoryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ShopCatalogMapper extends ClassMapperBase<ShopCatalog> {
  ShopCatalogMapper._();

  static ShopCatalogMapper? _instance;
  static ShopCatalogMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShopCatalogMapper._());
      ShopCategoryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ShopCatalog';

  static List<ShopCategory> _$categories(ShopCatalog v) => v.categories;
  static const Field<ShopCatalog, List<ShopCategory>> _f$categories = Field(
    'categories',
    _$categories,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<ShopCatalog> fields = const {#categories: _f$categories};

  static ShopCatalog _instantiate(DecodingData data) {
    return ShopCatalog(categories: data.dec(_f$categories));
  }

  @override
  final Function instantiate = _instantiate;

  static ShopCatalog fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ShopCatalog>(map);
  }

  static ShopCatalog fromJson(String json) {
    return ensureInitialized().decodeJson<ShopCatalog>(json);
  }
}

mixin ShopCatalogMappable {
  String toJson() {
    return ShopCatalogMapper.ensureInitialized().encodeJson<ShopCatalog>(
      this as ShopCatalog,
    );
  }

  Map<String, dynamic> toMap() {
    return ShopCatalogMapper.ensureInitialized().encodeMap<ShopCatalog>(
      this as ShopCatalog,
    );
  }

  ShopCatalogCopyWith<ShopCatalog, ShopCatalog, ShopCatalog> get copyWith =>
      _ShopCatalogCopyWithImpl<ShopCatalog, ShopCatalog>(
        this as ShopCatalog,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ShopCatalogMapper.ensureInitialized().stringifyValue(
      this as ShopCatalog,
    );
  }

  @override
  bool operator ==(Object other) {
    return ShopCatalogMapper.ensureInitialized().equalsValue(
      this as ShopCatalog,
      other,
    );
  }

  @override
  int get hashCode {
    return ShopCatalogMapper.ensureInitialized().hashValue(this as ShopCatalog);
  }
}

extension ShopCatalogValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ShopCatalog, $Out> {
  ShopCatalogCopyWith<$R, ShopCatalog, $Out> get $asShopCatalog =>
      $base.as((v, t, t2) => _ShopCatalogCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ShopCatalogCopyWith<$R, $In extends ShopCatalog, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    ShopCategory,
    ShopCategoryCopyWith<$R, ShopCategory, ShopCategory>
  >
  get categories;
  $R call({List<ShopCategory>? categories});
  ShopCatalogCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ShopCatalogCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ShopCatalog, $Out>
    implements ShopCatalogCopyWith<$R, ShopCatalog, $Out> {
  _ShopCatalogCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ShopCatalog> $mapper =
      ShopCatalogMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    ShopCategory,
    ShopCategoryCopyWith<$R, ShopCategory, ShopCategory>
  >
  get categories => ListCopyWith(
    $value.categories,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(categories: v),
  );
  @override
  $R call({List<ShopCategory>? categories}) => $apply(
    FieldCopyWithData({if (categories != null) #categories: categories}),
  );
  @override
  ShopCatalog $make(CopyWithData data) =>
      ShopCatalog(categories: data.get(#categories, or: $value.categories));

  @override
  ShopCatalogCopyWith<$R2, ShopCatalog, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ShopCatalogCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ShopConfigMapper extends ClassMapperBase<ShopConfig> {
  ShopConfigMapper._();

  static ShopConfigMapper? _instance;
  static ShopConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShopConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ShopConfig';

  static int _$sellPercent(ShopConfig v) => v.sellPercent;
  static const Field<ShopConfig, int> _f$sellPercent = Field(
    'sellPercent',
    _$sellPercent,
    opt: true,
    def: 50,
  );
  static int _$confirmThreshold(ShopConfig v) => v.confirmThreshold;
  static const Field<ShopConfig, int> _f$confirmThreshold = Field(
    'confirmThreshold',
    _$confirmThreshold,
    opt: true,
    def: 5000,
  );
  static String _$prefix(ShopConfig v) => v.prefix;
  static const Field<ShopConfig, String> _f$prefix = Field(
    'prefix',
    _$prefix,
    opt: true,
    def: '&8[&6Shop&8] &r',
  );
  static int _$ledgerSize(ShopConfig v) => v.ledgerSize;
  static const Field<ShopConfig, int> _f$ledgerSize = Field(
    'ledgerSize',
    _$ledgerSize,
    opt: true,
    def: 500,
  );

  @override
  final MappableFields<ShopConfig> fields = const {
    #sellPercent: _f$sellPercent,
    #confirmThreshold: _f$confirmThreshold,
    #prefix: _f$prefix,
    #ledgerSize: _f$ledgerSize,
  };

  static ShopConfig _instantiate(DecodingData data) {
    return ShopConfig(
      sellPercent: data.dec(_f$sellPercent),
      confirmThreshold: data.dec(_f$confirmThreshold),
      prefix: data.dec(_f$prefix),
      ledgerSize: data.dec(_f$ledgerSize),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ShopConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ShopConfig>(map);
  }

  static ShopConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ShopConfig>(json);
  }
}

mixin ShopConfigMappable {
  String toJson() {
    return ShopConfigMapper.ensureInitialized().encodeJson<ShopConfig>(
      this as ShopConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return ShopConfigMapper.ensureInitialized().encodeMap<ShopConfig>(
      this as ShopConfig,
    );
  }

  ShopConfigCopyWith<ShopConfig, ShopConfig, ShopConfig> get copyWith =>
      _ShopConfigCopyWithImpl<ShopConfig, ShopConfig>(
        this as ShopConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ShopConfigMapper.ensureInitialized().stringifyValue(
      this as ShopConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ShopConfigMapper.ensureInitialized().equalsValue(
      this as ShopConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ShopConfigMapper.ensureInitialized().hashValue(this as ShopConfig);
  }
}

extension ShopConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ShopConfig, $Out> {
  ShopConfigCopyWith<$R, ShopConfig, $Out> get $asShopConfig =>
      $base.as((v, t, t2) => _ShopConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ShopConfigCopyWith<$R, $In extends ShopConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? sellPercent,
    int? confirmThreshold,
    String? prefix,
    int? ledgerSize,
  });
  ShopConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ShopConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ShopConfig, $Out>
    implements ShopConfigCopyWith<$R, ShopConfig, $Out> {
  _ShopConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ShopConfig> $mapper =
      ShopConfigMapper.ensureInitialized();
  @override
  $R call({
    int? sellPercent,
    int? confirmThreshold,
    String? prefix,
    int? ledgerSize,
  }) => $apply(
    FieldCopyWithData({
      if (sellPercent != null) #sellPercent: sellPercent,
      if (confirmThreshold != null) #confirmThreshold: confirmThreshold,
      if (prefix != null) #prefix: prefix,
      if (ledgerSize != null) #ledgerSize: ledgerSize,
    }),
  );
  @override
  ShopConfig $make(CopyWithData data) => ShopConfig(
    sellPercent: data.get(#sellPercent, or: $value.sellPercent),
    confirmThreshold: data.get(#confirmThreshold, or: $value.confirmThreshold),
    prefix: data.get(#prefix, or: $value.prefix),
    ledgerSize: data.get(#ledgerSize, or: $value.ledgerSize),
  );

  @override
  ShopConfigCopyWith<$R2, ShopConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ShopConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LedgerEntryMapper extends ClassMapperBase<LedgerEntry> {
  LedgerEntryMapper._();

  static LedgerEntryMapper? _instance;
  static LedgerEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerEntryMapper._());
      TradeKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LedgerEntry';

  static DateTime _$time(LedgerEntry v) => v.time;
  static const Field<LedgerEntry, DateTime> _f$time = Field('time', _$time);
  static String _$uuid(LedgerEntry v) => v.uuid;
  static const Field<LedgerEntry, String> _f$uuid = Field('uuid', _$uuid);
  static String _$player(LedgerEntry v) => v.player;
  static const Field<LedgerEntry, String> _f$player = Field('player', _$player);
  static TradeKind _$kind(LedgerEntry v) => v.kind;
  static const Field<LedgerEntry, TradeKind> _f$kind = Field('kind', _$kind);
  static String _$item(LedgerEntry v) => v.item;
  static const Field<LedgerEntry, String> _f$item = Field('item', _$item);
  static int _$amount(LedgerEntry v) => v.amount;
  static const Field<LedgerEntry, int> _f$amount = Field('amount', _$amount);
  static int _$total(LedgerEntry v) => v.total;
  static const Field<LedgerEntry, int> _f$total = Field('total', _$total);

  @override
  final MappableFields<LedgerEntry> fields = const {
    #time: _f$time,
    #uuid: _f$uuid,
    #player: _f$player,
    #kind: _f$kind,
    #item: _f$item,
    #amount: _f$amount,
    #total: _f$total,
  };

  static LedgerEntry _instantiate(DecodingData data) {
    return LedgerEntry(
      time: data.dec(_f$time),
      uuid: data.dec(_f$uuid),
      player: data.dec(_f$player),
      kind: data.dec(_f$kind),
      item: data.dec(_f$item),
      amount: data.dec(_f$amount),
      total: data.dec(_f$total),
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
    DateTime? time,
    String? uuid,
    String? player,
    TradeKind? kind,
    String? item,
    int? amount,
    int? total,
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
    DateTime? time,
    String? uuid,
    String? player,
    TradeKind? kind,
    String? item,
    int? amount,
    int? total,
  }) => $apply(
    FieldCopyWithData({
      if (time != null) #time: time,
      if (uuid != null) #uuid: uuid,
      if (player != null) #player: player,
      if (kind != null) #kind: kind,
      if (item != null) #item: item,
      if (amount != null) #amount: amount,
      if (total != null) #total: total,
    }),
  );
  @override
  LedgerEntry $make(CopyWithData data) => LedgerEntry(
    time: data.get(#time, or: $value.time),
    uuid: data.get(#uuid, or: $value.uuid),
    player: data.get(#player, or: $value.player),
    kind: data.get(#kind, or: $value.kind),
    item: data.get(#item, or: $value.item),
    amount: data.get(#amount, or: $value.amount),
    total: data.get(#total, or: $value.total),
  );

  @override
  LedgerEntryCopyWith<$R2, LedgerEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LedgerEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LedgerMapper extends ClassMapperBase<Ledger> {
  LedgerMapper._();

  static LedgerMapper? _instance;
  static LedgerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerMapper._());
      LedgerEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Ledger';

  static List<LedgerEntry> _$entries(Ledger v) => v.entries;
  static const Field<Ledger, List<LedgerEntry>> _f$entries = Field(
    'entries',
    _$entries,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<Ledger> fields = const {#entries: _f$entries};

  static Ledger _instantiate(DecodingData data) {
    return Ledger(entries: data.dec(_f$entries));
  }

  @override
  final Function instantiate = _instantiate;

  static Ledger fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Ledger>(map);
  }

  static Ledger fromJson(String json) {
    return ensureInitialized().decodeJson<Ledger>(json);
  }
}

mixin LedgerMappable {
  String toJson() {
    return LedgerMapper.ensureInitialized().encodeJson<Ledger>(this as Ledger);
  }

  Map<String, dynamic> toMap() {
    return LedgerMapper.ensureInitialized().encodeMap<Ledger>(this as Ledger);
  }

  LedgerCopyWith<Ledger, Ledger, Ledger> get copyWith =>
      _LedgerCopyWithImpl<Ledger, Ledger>(this as Ledger, $identity, $identity);
  @override
  String toString() {
    return LedgerMapper.ensureInitialized().stringifyValue(this as Ledger);
  }

  @override
  bool operator ==(Object other) {
    return LedgerMapper.ensureInitialized().equalsValue(this as Ledger, other);
  }

  @override
  int get hashCode {
    return LedgerMapper.ensureInitialized().hashValue(this as Ledger);
  }
}

extension LedgerValueCopy<$R, $Out> on ObjectCopyWith<$R, Ledger, $Out> {
  LedgerCopyWith<$R, Ledger, $Out> get $asLedger =>
      $base.as((v, t, t2) => _LedgerCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LedgerCopyWith<$R, $In extends Ledger, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    LedgerEntry,
    LedgerEntryCopyWith<$R, LedgerEntry, LedgerEntry>
  >
  get entries;
  $R call({List<LedgerEntry>? entries});
  LedgerCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LedgerCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Ledger, $Out>
    implements LedgerCopyWith<$R, Ledger, $Out> {
  _LedgerCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Ledger> $mapper = LedgerMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    LedgerEntry,
    LedgerEntryCopyWith<$R, LedgerEntry, LedgerEntry>
  >
  get entries => ListCopyWith(
    $value.entries,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(entries: v),
  );
  @override
  $R call({List<LedgerEntry>? entries}) =>
      $apply(FieldCopyWithData({if (entries != null) #entries: entries}));
  @override
  Ledger $make(CopyWithData data) =>
      Ledger(entries: data.get(#entries, or: $value.entries));

  @override
  LedgerCopyWith<$R2, Ledger, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LedgerCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


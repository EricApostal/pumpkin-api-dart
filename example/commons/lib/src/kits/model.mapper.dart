// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class KitItemMapper extends ClassMapperBase<KitItem> {
  KitItemMapper._();

  static KitItemMapper? _instance;
  static KitItemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KitItemMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'KitItem';

  static String _$item(KitItem v) => v.item;
  static const Field<KitItem, String> _f$item = Field('item', _$item);
  static int _$count(KitItem v) => v.count;
  static const Field<KitItem, int> _f$count = Field(
    'count',
    _$count,
    opt: true,
    def: 1,
  );
  static String? _$name(KitItem v) => v.name;
  static const Field<KitItem, String> _f$name = Field(
    'name',
    _$name,
    opt: true,
  );
  static List<String> _$lore(KitItem v) => v.lore;
  static const Field<KitItem, List<String>> _f$lore = Field(
    'lore',
    _$lore,
    opt: true,
    def: const [],
  );
  static Map<String, int> _$enchantments(KitItem v) => v.enchantments;
  static const Field<KitItem, Map<String, int>> _f$enchantments = Field(
    'enchantments',
    _$enchantments,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<KitItem> fields = const {
    #item: _f$item,
    #count: _f$count,
    #name: _f$name,
    #lore: _f$lore,
    #enchantments: _f$enchantments,
  };
  @override
  final bool ignoreNull = true;

  static KitItem _instantiate(DecodingData data) {
    return KitItem(
      item: data.dec(_f$item),
      count: data.dec(_f$count),
      name: data.dec(_f$name),
      lore: data.dec(_f$lore),
      enchantments: data.dec(_f$enchantments),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static KitItem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KitItem>(map);
  }

  static KitItem fromJson(String json) {
    return ensureInitialized().decodeJson<KitItem>(json);
  }
}

mixin KitItemMappable {
  String toJson() {
    return KitItemMapper.ensureInitialized().encodeJson<KitItem>(
      this as KitItem,
    );
  }

  Map<String, dynamic> toMap() {
    return KitItemMapper.ensureInitialized().encodeMap<KitItem>(
      this as KitItem,
    );
  }

  KitItemCopyWith<KitItem, KitItem, KitItem> get copyWith =>
      _KitItemCopyWithImpl<KitItem, KitItem>(
        this as KitItem,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return KitItemMapper.ensureInitialized().stringifyValue(this as KitItem);
  }

  @override
  bool operator ==(Object other) {
    return KitItemMapper.ensureInitialized().equalsValue(
      this as KitItem,
      other,
    );
  }

  @override
  int get hashCode {
    return KitItemMapper.ensureInitialized().hashValue(this as KitItem);
  }
}

extension KitItemValueCopy<$R, $Out> on ObjectCopyWith<$R, KitItem, $Out> {
  KitItemCopyWith<$R, KitItem, $Out> get $asKitItem =>
      $base.as((v, t, t2) => _KitItemCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KitItemCopyWith<$R, $In extends KitItem, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get lore;
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get enchantments;
  $R call({
    String? item,
    int? count,
    String? name,
    List<String>? lore,
    Map<String, int>? enchantments,
  });
  KitItemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _KitItemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KitItem, $Out>
    implements KitItemCopyWith<$R, KitItem, $Out> {
  _KitItemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KitItem> $mapper =
      KitItemMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get lore =>
      ListCopyWith(
        $value.lore,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(lore: v),
      );
  @override
  MapCopyWith<$R, String, int, ObjectCopyWith<$R, int, int>> get enchantments =>
      MapCopyWith(
        $value.enchantments,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(enchantments: v),
      );
  @override
  $R call({
    String? item,
    int? count,
    Object? name = $none,
    List<String>? lore,
    Map<String, int>? enchantments,
  }) => $apply(
    FieldCopyWithData({
      if (item != null) #item: item,
      if (count != null) #count: count,
      if (name != $none) #name: name,
      if (lore != null) #lore: lore,
      if (enchantments != null) #enchantments: enchantments,
    }),
  );
  @override
  KitItem $make(CopyWithData data) => KitItem(
    item: data.get(#item, or: $value.item),
    count: data.get(#count, or: $value.count),
    name: data.get(#name, or: $value.name),
    lore: data.get(#lore, or: $value.lore),
    enchantments: data.get(#enchantments, or: $value.enchantments),
  );

  @override
  KitItemCopyWith<$R2, KitItem, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _KitItemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class KitMapper extends ClassMapperBase<Kit> {
  KitMapper._();

  static KitMapper? _instance;
  static KitMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KitMapper._());
      KitItemMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Kit';

  static String _$name(Kit v) => v.name;
  static const Field<Kit, String> _f$name = Field('name', _$name);
  static String? _$displayName(Kit v) => v.displayName;
  static const Field<Kit, String> _f$displayName = Field(
    'displayName',
    _$displayName,
    opt: true,
  );
  static String _$icon(Kit v) => v.icon;
  static const Field<Kit, String> _f$icon = Field(
    'icon',
    _$icon,
    opt: true,
    def: 'chest',
  );
  static List<KitItem> _$items(Kit v) => v.items;
  static const Field<Kit, List<KitItem>> _f$items = Field(
    'items',
    _$items,
    opt: true,
    def: const [],
  );
  static int _$cooldownSeconds(Kit v) => v.cooldownSeconds;
  static const Field<Kit, int> _f$cooldownSeconds = Field(
    'cooldownSeconds',
    _$cooldownSeconds,
    opt: true,
    def: 0,
  );
  static bool _$oneTime(Kit v) => v.oneTime;
  static const Field<Kit, bool> _f$oneTime = Field(
    'oneTime',
    _$oneTime,
    opt: true,
    def: false,
  );
  static int _$price(Kit v) => v.price;
  static const Field<Kit, int> _f$price = Field(
    'price',
    _$price,
    opt: true,
    def: 0,
  );
  static bool _$restricted(Kit v) => v.restricted;
  static const Field<Kit, bool> _f$restricted = Field(
    'restricted',
    _$restricted,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<Kit> fields = const {
    #name: _f$name,
    #displayName: _f$displayName,
    #icon: _f$icon,
    #items: _f$items,
    #cooldownSeconds: _f$cooldownSeconds,
    #oneTime: _f$oneTime,
    #price: _f$price,
    #restricted: _f$restricted,
  };
  @override
  final bool ignoreNull = true;

  static Kit _instantiate(DecodingData data) {
    return Kit(
      name: data.dec(_f$name),
      displayName: data.dec(_f$displayName),
      icon: data.dec(_f$icon),
      items: data.dec(_f$items),
      cooldownSeconds: data.dec(_f$cooldownSeconds),
      oneTime: data.dec(_f$oneTime),
      price: data.dec(_f$price),
      restricted: data.dec(_f$restricted),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Kit fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Kit>(map);
  }

  static Kit fromJson(String json) {
    return ensureInitialized().decodeJson<Kit>(json);
  }
}

mixin KitMappable {
  String toJson() {
    return KitMapper.ensureInitialized().encodeJson<Kit>(this as Kit);
  }

  Map<String, dynamic> toMap() {
    return KitMapper.ensureInitialized().encodeMap<Kit>(this as Kit);
  }

  KitCopyWith<Kit, Kit, Kit> get copyWith =>
      _KitCopyWithImpl<Kit, Kit>(this as Kit, $identity, $identity);
  @override
  String toString() {
    return KitMapper.ensureInitialized().stringifyValue(this as Kit);
  }

  @override
  bool operator ==(Object other) {
    return KitMapper.ensureInitialized().equalsValue(this as Kit, other);
  }

  @override
  int get hashCode {
    return KitMapper.ensureInitialized().hashValue(this as Kit);
  }
}

extension KitValueCopy<$R, $Out> on ObjectCopyWith<$R, Kit, $Out> {
  KitCopyWith<$R, Kit, $Out> get $asKit =>
      $base.as((v, t, t2) => _KitCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KitCopyWith<$R, $In extends Kit, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, KitItem, KitItemCopyWith<$R, KitItem, KitItem>> get items;
  $R call({
    String? name,
    String? displayName,
    String? icon,
    List<KitItem>? items,
    int? cooldownSeconds,
    bool? oneTime,
    int? price,
    bool? restricted,
  });
  KitCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _KitCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Kit, $Out>
    implements KitCopyWith<$R, Kit, $Out> {
  _KitCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Kit> $mapper = KitMapper.ensureInitialized();
  @override
  ListCopyWith<$R, KitItem, KitItemCopyWith<$R, KitItem, KitItem>> get items =>
      ListCopyWith(
        $value.items,
        (v, t) => v.copyWith.$chain(t),
        (v) => call(items: v),
      );
  @override
  $R call({
    String? name,
    Object? displayName = $none,
    String? icon,
    List<KitItem>? items,
    int? cooldownSeconds,
    bool? oneTime,
    int? price,
    bool? restricted,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (displayName != $none) #displayName: displayName,
      if (icon != null) #icon: icon,
      if (items != null) #items: items,
      if (cooldownSeconds != null) #cooldownSeconds: cooldownSeconds,
      if (oneTime != null) #oneTime: oneTime,
      if (price != null) #price: price,
      if (restricted != null) #restricted: restricted,
    }),
  );
  @override
  Kit $make(CopyWithData data) => Kit(
    name: data.get(#name, or: $value.name),
    displayName: data.get(#displayName, or: $value.displayName),
    icon: data.get(#icon, or: $value.icon),
    items: data.get(#items, or: $value.items),
    cooldownSeconds: data.get(#cooldownSeconds, or: $value.cooldownSeconds),
    oneTime: data.get(#oneTime, or: $value.oneTime),
    price: data.get(#price, or: $value.price),
    restricted: data.get(#restricted, or: $value.restricted),
  );

  @override
  KitCopyWith<$R2, Kit, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _KitCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class KitCatalogMapper extends ClassMapperBase<KitCatalog> {
  KitCatalogMapper._();

  static KitCatalogMapper? _instance;
  static KitCatalogMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KitCatalogMapper._());
      KitMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'KitCatalog';

  static List<Kit> _$kits(KitCatalog v) => v.kits;
  static const Field<KitCatalog, List<Kit>> _f$kits = Field(
    'kits',
    _$kits,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<KitCatalog> fields = const {#kits: _f$kits};

  static KitCatalog _instantiate(DecodingData data) {
    return KitCatalog(kits: data.dec(_f$kits));
  }

  @override
  final Function instantiate = _instantiate;

  static KitCatalog fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KitCatalog>(map);
  }

  static KitCatalog fromJson(String json) {
    return ensureInitialized().decodeJson<KitCatalog>(json);
  }
}

mixin KitCatalogMappable {
  String toJson() {
    return KitCatalogMapper.ensureInitialized().encodeJson<KitCatalog>(
      this as KitCatalog,
    );
  }

  Map<String, dynamic> toMap() {
    return KitCatalogMapper.ensureInitialized().encodeMap<KitCatalog>(
      this as KitCatalog,
    );
  }

  KitCatalogCopyWith<KitCatalog, KitCatalog, KitCatalog> get copyWith =>
      _KitCatalogCopyWithImpl<KitCatalog, KitCatalog>(
        this as KitCatalog,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return KitCatalogMapper.ensureInitialized().stringifyValue(
      this as KitCatalog,
    );
  }

  @override
  bool operator ==(Object other) {
    return KitCatalogMapper.ensureInitialized().equalsValue(
      this as KitCatalog,
      other,
    );
  }

  @override
  int get hashCode {
    return KitCatalogMapper.ensureInitialized().hashValue(this as KitCatalog);
  }
}

extension KitCatalogValueCopy<$R, $Out>
    on ObjectCopyWith<$R, KitCatalog, $Out> {
  KitCatalogCopyWith<$R, KitCatalog, $Out> get $asKitCatalog =>
      $base.as((v, t, t2) => _KitCatalogCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KitCatalogCopyWith<$R, $In extends KitCatalog, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Kit, KitCopyWith<$R, Kit, Kit>> get kits;
  $R call({List<Kit>? kits});
  KitCatalogCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _KitCatalogCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KitCatalog, $Out>
    implements KitCatalogCopyWith<$R, KitCatalog, $Out> {
  _KitCatalogCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KitCatalog> $mapper =
      KitCatalogMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Kit, KitCopyWith<$R, Kit, Kit>> get kits => ListCopyWith(
    $value.kits,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(kits: v),
  );
  @override
  $R call({List<Kit>? kits}) =>
      $apply(FieldCopyWithData({if (kits != null) #kits: kits}));
  @override
  KitCatalog $make(CopyWithData data) =>
      KitCatalog(kits: data.get(#kits, or: $value.kits));

  @override
  KitCatalogCopyWith<$R2, KitCatalog, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _KitCatalogCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class KitsConfigMapper extends ClassMapperBase<KitsConfig> {
  KitsConfigMapper._();

  static KitsConfigMapper? _instance;
  static KitsConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KitsConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'KitsConfig';

  static bool _$giveStarterKit(KitsConfig v) => v.giveStarterKit;
  static const Field<KitsConfig, bool> _f$giveStarterKit = Field(
    'giveStarterKit',
    _$giveStarterKit,
    opt: true,
    def: true,
  );
  static String _$starterKit(KitsConfig v) => v.starterKit;
  static const Field<KitsConfig, String> _f$starterKit = Field(
    'starterKit',
    _$starterKit,
    opt: true,
    def: 'starter',
  );
  static String _$prefix(KitsConfig v) => v.prefix;
  static const Field<KitsConfig, String> _f$prefix = Field(
    'prefix',
    _$prefix,
    opt: true,
    def: '&8[&6Kits&8] &r',
  );

  @override
  final MappableFields<KitsConfig> fields = const {
    #giveStarterKit: _f$giveStarterKit,
    #starterKit: _f$starterKit,
    #prefix: _f$prefix,
  };

  static KitsConfig _instantiate(DecodingData data) {
    return KitsConfig(
      giveStarterKit: data.dec(_f$giveStarterKit),
      starterKit: data.dec(_f$starterKit),
      prefix: data.dec(_f$prefix),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static KitsConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KitsConfig>(map);
  }

  static KitsConfig fromJson(String json) {
    return ensureInitialized().decodeJson<KitsConfig>(json);
  }
}

mixin KitsConfigMappable {
  String toJson() {
    return KitsConfigMapper.ensureInitialized().encodeJson<KitsConfig>(
      this as KitsConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return KitsConfigMapper.ensureInitialized().encodeMap<KitsConfig>(
      this as KitsConfig,
    );
  }

  KitsConfigCopyWith<KitsConfig, KitsConfig, KitsConfig> get copyWith =>
      _KitsConfigCopyWithImpl<KitsConfig, KitsConfig>(
        this as KitsConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return KitsConfigMapper.ensureInitialized().stringifyValue(
      this as KitsConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return KitsConfigMapper.ensureInitialized().equalsValue(
      this as KitsConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return KitsConfigMapper.ensureInitialized().hashValue(this as KitsConfig);
  }
}

extension KitsConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, KitsConfig, $Out> {
  KitsConfigCopyWith<$R, KitsConfig, $Out> get $asKitsConfig =>
      $base.as((v, t, t2) => _KitsConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KitsConfigCopyWith<$R, $In extends KitsConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({bool? giveStarterKit, String? starterKit, String? prefix});
  KitsConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _KitsConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KitsConfig, $Out>
    implements KitsConfigCopyWith<$R, KitsConfig, $Out> {
  _KitsConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KitsConfig> $mapper =
      KitsConfigMapper.ensureInitialized();
  @override
  $R call({bool? giveStarterKit, String? starterKit, String? prefix}) => $apply(
    FieldCopyWithData({
      if (giveStarterKit != null) #giveStarterKit: giveStarterKit,
      if (starterKit != null) #starterKit: starterKit,
      if (prefix != null) #prefix: prefix,
    }),
  );
  @override
  KitsConfig $make(CopyWithData data) => KitsConfig(
    giveStarterKit: data.get(#giveStarterKit, or: $value.giveStarterKit),
    starterKit: data.get(#starterKit, or: $value.starterKit),
    prefix: data.get(#prefix, or: $value.prefix),
  );

  @override
  KitsConfigCopyWith<$R2, KitsConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _KitsConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class KitClaimMapper extends ClassMapperBase<KitClaim> {
  KitClaimMapper._();

  static KitClaimMapper? _instance;
  static KitClaimMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KitClaimMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'KitClaim';

  static DateTime _$lastClaimed(KitClaim v) => v.lastClaimed;
  static const Field<KitClaim, DateTime> _f$lastClaimed = Field(
    'lastClaimed',
    _$lastClaimed,
  );
  static int _$count(KitClaim v) => v.count;
  static const Field<KitClaim, int> _f$count = Field('count', _$count);

  @override
  final MappableFields<KitClaim> fields = const {
    #lastClaimed: _f$lastClaimed,
    #count: _f$count,
  };

  static KitClaim _instantiate(DecodingData data) {
    return KitClaim(
      lastClaimed: data.dec(_f$lastClaimed),
      count: data.dec(_f$count),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static KitClaim fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KitClaim>(map);
  }

  static KitClaim fromJson(String json) {
    return ensureInitialized().decodeJson<KitClaim>(json);
  }
}

mixin KitClaimMappable {
  String toJson() {
    return KitClaimMapper.ensureInitialized().encodeJson<KitClaim>(
      this as KitClaim,
    );
  }

  Map<String, dynamic> toMap() {
    return KitClaimMapper.ensureInitialized().encodeMap<KitClaim>(
      this as KitClaim,
    );
  }

  KitClaimCopyWith<KitClaim, KitClaim, KitClaim> get copyWith =>
      _KitClaimCopyWithImpl<KitClaim, KitClaim>(
        this as KitClaim,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return KitClaimMapper.ensureInitialized().stringifyValue(this as KitClaim);
  }

  @override
  bool operator ==(Object other) {
    return KitClaimMapper.ensureInitialized().equalsValue(
      this as KitClaim,
      other,
    );
  }

  @override
  int get hashCode {
    return KitClaimMapper.ensureInitialized().hashValue(this as KitClaim);
  }
}

extension KitClaimValueCopy<$R, $Out> on ObjectCopyWith<$R, KitClaim, $Out> {
  KitClaimCopyWith<$R, KitClaim, $Out> get $asKitClaim =>
      $base.as((v, t, t2) => _KitClaimCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KitClaimCopyWith<$R, $In extends KitClaim, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({DateTime? lastClaimed, int? count});
  KitClaimCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _KitClaimCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KitClaim, $Out>
    implements KitClaimCopyWith<$R, KitClaim, $Out> {
  _KitClaimCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KitClaim> $mapper =
      KitClaimMapper.ensureInitialized();
  @override
  $R call({DateTime? lastClaimed, int? count}) => $apply(
    FieldCopyWithData({
      if (lastClaimed != null) #lastClaimed: lastClaimed,
      if (count != null) #count: count,
    }),
  );
  @override
  KitClaim $make(CopyWithData data) => KitClaim(
    lastClaimed: data.get(#lastClaimed, or: $value.lastClaimed),
    count: data.get(#count, or: $value.count),
  );

  @override
  KitClaimCopyWith<$R2, KitClaim, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _KitClaimCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class KitClaimsMapper extends ClassMapperBase<KitClaims> {
  KitClaimsMapper._();

  static KitClaimsMapper? _instance;
  static KitClaimsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KitClaimsMapper._());
      KitClaimMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'KitClaims';

  static Map<String, Map<String, KitClaim>> _$players(KitClaims v) => v.players;
  static const Field<KitClaims, Map<String, Map<String, KitClaim>>> _f$players =
      Field('players', _$players, opt: true, def: const {});

  @override
  final MappableFields<KitClaims> fields = const {#players: _f$players};

  static KitClaims _instantiate(DecodingData data) {
    return KitClaims(players: data.dec(_f$players));
  }

  @override
  final Function instantiate = _instantiate;

  static KitClaims fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KitClaims>(map);
  }

  static KitClaims fromJson(String json) {
    return ensureInitialized().decodeJson<KitClaims>(json);
  }
}

mixin KitClaimsMappable {
  String toJson() {
    return KitClaimsMapper.ensureInitialized().encodeJson<KitClaims>(
      this as KitClaims,
    );
  }

  Map<String, dynamic> toMap() {
    return KitClaimsMapper.ensureInitialized().encodeMap<KitClaims>(
      this as KitClaims,
    );
  }

  KitClaimsCopyWith<KitClaims, KitClaims, KitClaims> get copyWith =>
      _KitClaimsCopyWithImpl<KitClaims, KitClaims>(
        this as KitClaims,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return KitClaimsMapper.ensureInitialized().stringifyValue(
      this as KitClaims,
    );
  }

  @override
  bool operator ==(Object other) {
    return KitClaimsMapper.ensureInitialized().equalsValue(
      this as KitClaims,
      other,
    );
  }

  @override
  int get hashCode {
    return KitClaimsMapper.ensureInitialized().hashValue(this as KitClaims);
  }
}

extension KitClaimsValueCopy<$R, $Out> on ObjectCopyWith<$R, KitClaims, $Out> {
  KitClaimsCopyWith<$R, KitClaims, $Out> get $asKitClaims =>
      $base.as((v, t, t2) => _KitClaimsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class KitClaimsCopyWith<$R, $In extends KitClaims, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    Map<String, KitClaim>,
    ObjectCopyWith<$R, Map<String, KitClaim>, Map<String, KitClaim>>
  >
  get players;
  $R call({Map<String, Map<String, KitClaim>>? players});
  KitClaimsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _KitClaimsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KitClaims, $Out>
    implements KitClaimsCopyWith<$R, KitClaims, $Out> {
  _KitClaimsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KitClaims> $mapper =
      KitClaimsMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    Map<String, KitClaim>,
    ObjectCopyWith<$R, Map<String, KitClaim>, Map<String, KitClaim>>
  >
  get players => MapCopyWith(
    $value.players,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(players: v),
  );
  @override
  $R call({Map<String, Map<String, KitClaim>>? players}) =>
      $apply(FieldCopyWithData({if (players != null) #players: players}));
  @override
  KitClaims $make(CopyWithData data) =>
      KitClaims(players: data.get(#players, or: $value.players));

  @override
  KitClaimsCopyWith<$R2, KitClaims, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _KitClaimsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


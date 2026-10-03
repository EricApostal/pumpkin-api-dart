// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class LocationMapper extends ClassMapperBase<Location> {
  LocationMapper._();

  static LocationMapper? _instance;
  static LocationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LocationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Location';

  static String _$world(Location v) => v.world;
  static const Field<Location, String> _f$world = Field('world', _$world);
  static double _$x(Location v) => v.x;
  static const Field<Location, double> _f$x = Field('x', _$x);
  static double _$y(Location v) => v.y;
  static const Field<Location, double> _f$y = Field('y', _$y);
  static double _$z(Location v) => v.z;
  static const Field<Location, double> _f$z = Field('z', _$z);
  static double _$yaw(Location v) => v.yaw;
  static const Field<Location, double> _f$yaw = Field(
    'yaw',
    _$yaw,
    opt: true,
    def: 0,
  );
  static double _$pitch(Location v) => v.pitch;
  static const Field<Location, double> _f$pitch = Field(
    'pitch',
    _$pitch,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<Location> fields = const {
    #world: _f$world,
    #x: _f$x,
    #y: _f$y,
    #z: _f$z,
    #yaw: _f$yaw,
    #pitch: _f$pitch,
  };

  static Location _instantiate(DecodingData data) {
    return Location(
      world: data.dec(_f$world),
      x: data.dec(_f$x),
      y: data.dec(_f$y),
      z: data.dec(_f$z),
      yaw: data.dec(_f$yaw),
      pitch: data.dec(_f$pitch),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Location fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Location>(map);
  }

  static Location fromJson(String json) {
    return ensureInitialized().decodeJson<Location>(json);
  }
}

mixin LocationMappable {
  String toJson() {
    return LocationMapper.ensureInitialized().encodeJson<Location>(
      this as Location,
    );
  }

  Map<String, dynamic> toMap() {
    return LocationMapper.ensureInitialized().encodeMap<Location>(
      this as Location,
    );
  }

  LocationCopyWith<Location, Location, Location> get copyWith =>
      _LocationCopyWithImpl<Location, Location>(
        this as Location,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LocationMapper.ensureInitialized().stringifyValue(this as Location);
  }

  @override
  bool operator ==(Object other) {
    return LocationMapper.ensureInitialized().equalsValue(
      this as Location,
      other,
    );
  }

  @override
  int get hashCode {
    return LocationMapper.ensureInitialized().hashValue(this as Location);
  }
}

extension LocationValueCopy<$R, $Out> on ObjectCopyWith<$R, Location, $Out> {
  LocationCopyWith<$R, Location, $Out> get $asLocation =>
      $base.as((v, t, t2) => _LocationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LocationCopyWith<$R, $In extends Location, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? world,
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? pitch,
  });
  LocationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LocationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Location, $Out>
    implements LocationCopyWith<$R, Location, $Out> {
  _LocationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Location> $mapper =
      LocationMapper.ensureInitialized();
  @override
  $R call({
    String? world,
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? pitch,
  }) => $apply(
    FieldCopyWithData({
      if (world != null) #world: world,
      if (x != null) #x: x,
      if (y != null) #y: y,
      if (z != null) #z: z,
      if (yaw != null) #yaw: yaw,
      if (pitch != null) #pitch: pitch,
    }),
  );
  @override
  Location $make(CopyWithData data) => Location(
    world: data.get(#world, or: $value.world),
    x: data.get(#x, or: $value.x),
    y: data.get(#y, or: $value.y),
    z: data.get(#z, or: $value.z),
    yaw: data.get(#yaw, or: $value.yaw),
    pitch: data.get(#pitch, or: $value.pitch),
  );

  @override
  LocationCopyWith<$R2, Location, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LocationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TeleportConfigMapper extends ClassMapperBase<TeleportConfig> {
  TeleportConfigMapper._();

  static TeleportConfigMapper? _instance;
  static TeleportConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TeleportConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TeleportConfig';

  static int _$maxHomes(TeleportConfig v) => v.maxHomes;
  static const Field<TeleportConfig, int> _f$maxHomes = Field(
    'maxHomes',
    _$maxHomes,
    opt: true,
    def: 3,
  );
  static int _$requestTimeoutSeconds(TeleportConfig v) =>
      v.requestTimeoutSeconds;
  static const Field<TeleportConfig, int> _f$requestTimeoutSeconds = Field(
    'requestTimeoutSeconds',
    _$requestTimeoutSeconds,
    opt: true,
    def: 60,
  );
  static int _$cooldownSeconds(TeleportConfig v) => v.cooldownSeconds;
  static const Field<TeleportConfig, int> _f$cooldownSeconds = Field(
    'cooldownSeconds',
    _$cooldownSeconds,
    opt: true,
    def: 5,
  );

  @override
  final MappableFields<TeleportConfig> fields = const {
    #maxHomes: _f$maxHomes,
    #requestTimeoutSeconds: _f$requestTimeoutSeconds,
    #cooldownSeconds: _f$cooldownSeconds,
  };

  static TeleportConfig _instantiate(DecodingData data) {
    return TeleportConfig(
      maxHomes: data.dec(_f$maxHomes),
      requestTimeoutSeconds: data.dec(_f$requestTimeoutSeconds),
      cooldownSeconds: data.dec(_f$cooldownSeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TeleportConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TeleportConfig>(map);
  }

  static TeleportConfig fromJson(String json) {
    return ensureInitialized().decodeJson<TeleportConfig>(json);
  }
}

mixin TeleportConfigMappable {
  String toJson() {
    return TeleportConfigMapper.ensureInitialized().encodeJson<TeleportConfig>(
      this as TeleportConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return TeleportConfigMapper.ensureInitialized().encodeMap<TeleportConfig>(
      this as TeleportConfig,
    );
  }

  TeleportConfigCopyWith<TeleportConfig, TeleportConfig, TeleportConfig>
  get copyWith => _TeleportConfigCopyWithImpl<TeleportConfig, TeleportConfig>(
    this as TeleportConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return TeleportConfigMapper.ensureInitialized().stringifyValue(
      this as TeleportConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return TeleportConfigMapper.ensureInitialized().equalsValue(
      this as TeleportConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return TeleportConfigMapper.ensureInitialized().hashValue(
      this as TeleportConfig,
    );
  }
}

extension TeleportConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TeleportConfig, $Out> {
  TeleportConfigCopyWith<$R, TeleportConfig, $Out> get $asTeleportConfig =>
      $base.as((v, t, t2) => _TeleportConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TeleportConfigCopyWith<$R, $In extends TeleportConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? maxHomes, int? requestTimeoutSeconds, int? cooldownSeconds});
  TeleportConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TeleportConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TeleportConfig, $Out>
    implements TeleportConfigCopyWith<$R, TeleportConfig, $Out> {
  _TeleportConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TeleportConfig> $mapper =
      TeleportConfigMapper.ensureInitialized();
  @override
  $R call({int? maxHomes, int? requestTimeoutSeconds, int? cooldownSeconds}) =>
      $apply(
        FieldCopyWithData({
          if (maxHomes != null) #maxHomes: maxHomes,
          if (requestTimeoutSeconds != null)
            #requestTimeoutSeconds: requestTimeoutSeconds,
          if (cooldownSeconds != null) #cooldownSeconds: cooldownSeconds,
        }),
      );
  @override
  TeleportConfig $make(CopyWithData data) => TeleportConfig(
    maxHomes: data.get(#maxHomes, or: $value.maxHomes),
    requestTimeoutSeconds: data.get(
      #requestTimeoutSeconds,
      or: $value.requestTimeoutSeconds,
    ),
    cooldownSeconds: data.get(#cooldownSeconds, or: $value.cooldownSeconds),
  );

  @override
  TeleportConfigCopyWith<$R2, TeleportConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TeleportConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlayerHomesMapper extends ClassMapperBase<PlayerHomes> {
  PlayerHomesMapper._();

  static PlayerHomesMapper? _instance;
  static PlayerHomesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayerHomesMapper._());
      LocationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PlayerHomes';

  static String _$name(PlayerHomes v) => v.name;
  static const Field<PlayerHomes, String> _f$name = Field('name', _$name);
  static Map<String, Location> _$homes(PlayerHomes v) => v.homes;
  static const Field<PlayerHomes, Map<String, Location>> _f$homes = Field(
    'homes',
    _$homes,
  );

  @override
  final MappableFields<PlayerHomes> fields = const {
    #name: _f$name,
    #homes: _f$homes,
  };

  static PlayerHomes _instantiate(DecodingData data) {
    return PlayerHomes(name: data.dec(_f$name), homes: data.dec(_f$homes));
  }

  @override
  final Function instantiate = _instantiate;

  static PlayerHomes fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlayerHomes>(map);
  }

  static PlayerHomes fromJson(String json) {
    return ensureInitialized().decodeJson<PlayerHomes>(json);
  }
}

mixin PlayerHomesMappable {
  String toJson() {
    return PlayerHomesMapper.ensureInitialized().encodeJson<PlayerHomes>(
      this as PlayerHomes,
    );
  }

  Map<String, dynamic> toMap() {
    return PlayerHomesMapper.ensureInitialized().encodeMap<PlayerHomes>(
      this as PlayerHomes,
    );
  }

  PlayerHomesCopyWith<PlayerHomes, PlayerHomes, PlayerHomes> get copyWith =>
      _PlayerHomesCopyWithImpl<PlayerHomes, PlayerHomes>(
        this as PlayerHomes,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlayerHomesMapper.ensureInitialized().stringifyValue(
      this as PlayerHomes,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlayerHomesMapper.ensureInitialized().equalsValue(
      this as PlayerHomes,
      other,
    );
  }

  @override
  int get hashCode {
    return PlayerHomesMapper.ensureInitialized().hashValue(this as PlayerHomes);
  }
}

extension PlayerHomesValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlayerHomes, $Out> {
  PlayerHomesCopyWith<$R, PlayerHomes, $Out> get $asPlayerHomes =>
      $base.as((v, t, t2) => _PlayerHomesCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlayerHomesCopyWith<$R, $In extends PlayerHomes, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Location, LocationCopyWith<$R, Location, Location>>
  get homes;
  $R call({String? name, Map<String, Location>? homes});
  PlayerHomesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PlayerHomesCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlayerHomes, $Out>
    implements PlayerHomesCopyWith<$R, PlayerHomes, $Out> {
  _PlayerHomesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlayerHomes> $mapper =
      PlayerHomesMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Location, LocationCopyWith<$R, Location, Location>>
  get homes => MapCopyWith(
    $value.homes,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(homes: v),
  );
  @override
  $R call({String? name, Map<String, Location>? homes}) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (homes != null) #homes: homes,
    }),
  );
  @override
  PlayerHomes $make(CopyWithData data) => PlayerHomes(
    name: data.get(#name, or: $value.name),
    homes: data.get(#homes, or: $value.homes),
  );

  @override
  PlayerHomesCopyWith<$R2, PlayerHomes, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlayerHomesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class HomesFileMapper extends ClassMapperBase<HomesFile> {
  HomesFileMapper._();

  static HomesFileMapper? _instance;
  static HomesFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HomesFileMapper._());
      PlayerHomesMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'HomesFile';

  static Map<String, PlayerHomes> _$players(HomesFile v) => v.players;
  static const Field<HomesFile, Map<String, PlayerHomes>> _f$players = Field(
    'players',
    _$players,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<HomesFile> fields = const {#players: _f$players};

  static HomesFile _instantiate(DecodingData data) {
    return HomesFile(players: data.dec(_f$players));
  }

  @override
  final Function instantiate = _instantiate;

  static HomesFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<HomesFile>(map);
  }

  static HomesFile fromJson(String json) {
    return ensureInitialized().decodeJson<HomesFile>(json);
  }
}

mixin HomesFileMappable {
  String toJson() {
    return HomesFileMapper.ensureInitialized().encodeJson<HomesFile>(
      this as HomesFile,
    );
  }

  Map<String, dynamic> toMap() {
    return HomesFileMapper.ensureInitialized().encodeMap<HomesFile>(
      this as HomesFile,
    );
  }

  HomesFileCopyWith<HomesFile, HomesFile, HomesFile> get copyWith =>
      _HomesFileCopyWithImpl<HomesFile, HomesFile>(
        this as HomesFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return HomesFileMapper.ensureInitialized().stringifyValue(
      this as HomesFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return HomesFileMapper.ensureInitialized().equalsValue(
      this as HomesFile,
      other,
    );
  }

  @override
  int get hashCode {
    return HomesFileMapper.ensureInitialized().hashValue(this as HomesFile);
  }
}

extension HomesFileValueCopy<$R, $Out> on ObjectCopyWith<$R, HomesFile, $Out> {
  HomesFileCopyWith<$R, HomesFile, $Out> get $asHomesFile =>
      $base.as((v, t, t2) => _HomesFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class HomesFileCopyWith<$R, $In extends HomesFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    PlayerHomes,
    PlayerHomesCopyWith<$R, PlayerHomes, PlayerHomes>
  >
  get players;
  $R call({Map<String, PlayerHomes>? players});
  HomesFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _HomesFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, HomesFile, $Out>
    implements HomesFileCopyWith<$R, HomesFile, $Out> {
  _HomesFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<HomesFile> $mapper =
      HomesFileMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    PlayerHomes,
    PlayerHomesCopyWith<$R, PlayerHomes, PlayerHomes>
  >
  get players => MapCopyWith(
    $value.players,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(players: v),
  );
  @override
  $R call({Map<String, PlayerHomes>? players}) =>
      $apply(FieldCopyWithData({if (players != null) #players: players}));
  @override
  HomesFile $make(CopyWithData data) =>
      HomesFile(players: data.get(#players, or: $value.players));

  @override
  HomesFileCopyWith<$R2, HomesFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _HomesFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WarpsFileMapper extends ClassMapperBase<WarpsFile> {
  WarpsFileMapper._();

  static WarpsFileMapper? _instance;
  static WarpsFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WarpsFileMapper._());
      LocationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WarpsFile';

  static Map<String, Location> _$warps(WarpsFile v) => v.warps;
  static const Field<WarpsFile, Map<String, Location>> _f$warps = Field(
    'warps',
    _$warps,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<WarpsFile> fields = const {#warps: _f$warps};

  static WarpsFile _instantiate(DecodingData data) {
    return WarpsFile(warps: data.dec(_f$warps));
  }

  @override
  final Function instantiate = _instantiate;

  static WarpsFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WarpsFile>(map);
  }

  static WarpsFile fromJson(String json) {
    return ensureInitialized().decodeJson<WarpsFile>(json);
  }
}

mixin WarpsFileMappable {
  String toJson() {
    return WarpsFileMapper.ensureInitialized().encodeJson<WarpsFile>(
      this as WarpsFile,
    );
  }

  Map<String, dynamic> toMap() {
    return WarpsFileMapper.ensureInitialized().encodeMap<WarpsFile>(
      this as WarpsFile,
    );
  }

  WarpsFileCopyWith<WarpsFile, WarpsFile, WarpsFile> get copyWith =>
      _WarpsFileCopyWithImpl<WarpsFile, WarpsFile>(
        this as WarpsFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WarpsFileMapper.ensureInitialized().stringifyValue(
      this as WarpsFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return WarpsFileMapper.ensureInitialized().equalsValue(
      this as WarpsFile,
      other,
    );
  }

  @override
  int get hashCode {
    return WarpsFileMapper.ensureInitialized().hashValue(this as WarpsFile);
  }
}

extension WarpsFileValueCopy<$R, $Out> on ObjectCopyWith<$R, WarpsFile, $Out> {
  WarpsFileCopyWith<$R, WarpsFile, $Out> get $asWarpsFile =>
      $base.as((v, t, t2) => _WarpsFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WarpsFileCopyWith<$R, $In extends WarpsFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Location, LocationCopyWith<$R, Location, Location>>
  get warps;
  $R call({Map<String, Location>? warps});
  WarpsFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _WarpsFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WarpsFile, $Out>
    implements WarpsFileCopyWith<$R, WarpsFile, $Out> {
  _WarpsFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WarpsFile> $mapper =
      WarpsFileMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Location, LocationCopyWith<$R, Location, Location>>
  get warps => MapCopyWith(
    $value.warps,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(warps: v),
  );
  @override
  $R call({Map<String, Location>? warps}) =>
      $apply(FieldCopyWithData({if (warps != null) #warps: warps}));
  @override
  WarpsFile $make(CopyWithData data) =>
      WarpsFile(warps: data.get(#warps, or: $value.warps));

  @override
  WarpsFileCopyWith<$R2, WarpsFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WarpsFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


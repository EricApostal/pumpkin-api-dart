// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class RankStyleMapper extends ClassMapperBase<RankStyle> {
  RankStyleMapper._();

  static RankStyleMapper? _instance;
  static RankStyleMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RankStyleMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RankStyle';

  static String _$permission(RankStyle v) => v.permission;
  static const Field<RankStyle, String> _f$permission = Field(
    'permission',
    _$permission,
    opt: true,
    def: '',
  );
  static String _$prefix(RankStyle v) => v.prefix;
  static const Field<RankStyle, String> _f$prefix = Field(
    'prefix',
    _$prefix,
    opt: true,
    def: '',
  );
  static String _$suffix(RankStyle v) => v.suffix;
  static const Field<RankStyle, String> _f$suffix = Field(
    'suffix',
    _$suffix,
    opt: true,
    def: '',
  );
  static String _$color(RankStyle v) => v.color;
  static const Field<RankStyle, String> _f$color = Field(
    'color',
    _$color,
    opt: true,
    def: '&f',
  );

  @override
  final MappableFields<RankStyle> fields = const {
    #permission: _f$permission,
    #prefix: _f$prefix,
    #suffix: _f$suffix,
    #color: _f$color,
  };

  static RankStyle _instantiate(DecodingData data) {
    return RankStyle(
      permission: data.dec(_f$permission),
      prefix: data.dec(_f$prefix),
      suffix: data.dec(_f$suffix),
      color: data.dec(_f$color),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RankStyle fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RankStyle>(map);
  }

  static RankStyle fromJson(String json) {
    return ensureInitialized().decodeJson<RankStyle>(json);
  }
}

mixin RankStyleMappable {
  String toJson() {
    return RankStyleMapper.ensureInitialized().encodeJson<RankStyle>(
      this as RankStyle,
    );
  }

  Map<String, dynamic> toMap() {
    return RankStyleMapper.ensureInitialized().encodeMap<RankStyle>(
      this as RankStyle,
    );
  }

  RankStyleCopyWith<RankStyle, RankStyle, RankStyle> get copyWith =>
      _RankStyleCopyWithImpl<RankStyle, RankStyle>(
        this as RankStyle,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RankStyleMapper.ensureInitialized().stringifyValue(
      this as RankStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    return RankStyleMapper.ensureInitialized().equalsValue(
      this as RankStyle,
      other,
    );
  }

  @override
  int get hashCode {
    return RankStyleMapper.ensureInitialized().hashValue(this as RankStyle);
  }
}

extension RankStyleValueCopy<$R, $Out> on ObjectCopyWith<$R, RankStyle, $Out> {
  RankStyleCopyWith<$R, RankStyle, $Out> get $asRankStyle =>
      $base.as((v, t, t2) => _RankStyleCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RankStyleCopyWith<$R, $In extends RankStyle, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? permission, String? prefix, String? suffix, String? color});
  RankStyleCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RankStyleCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RankStyle, $Out>
    implements RankStyleCopyWith<$R, RankStyle, $Out> {
  _RankStyleCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RankStyle> $mapper =
      RankStyleMapper.ensureInitialized();
  @override
  $R call({
    String? permission,
    String? prefix,
    String? suffix,
    String? color,
  }) => $apply(
    FieldCopyWithData({
      if (permission != null) #permission: permission,
      if (prefix != null) #prefix: prefix,
      if (suffix != null) #suffix: suffix,
      if (color != null) #color: color,
    }),
  );
  @override
  RankStyle $make(CopyWithData data) => RankStyle(
    permission: data.get(#permission, or: $value.permission),
    prefix: data.get(#prefix, or: $value.prefix),
    suffix: data.get(#suffix, or: $value.suffix),
    color: data.get(#color, or: $value.color),
  );

  @override
  RankStyleCopyWith<$R2, RankStyle, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RankStyleCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SpamConfigMapper extends ClassMapperBase<SpamConfig> {
  SpamConfigMapper._();

  static SpamConfigMapper? _instance;
  static SpamConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SpamConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SpamConfig';

  static bool _$enabled(SpamConfig v) => v.enabled;
  static const Field<SpamConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int _$cooldownMillis(SpamConfig v) => v.cooldownMillis;
  static const Field<SpamConfig, int> _f$cooldownMillis = Field(
    'cooldownMillis',
    _$cooldownMillis,
    opt: true,
    def: 1000,
  );
  static int _$maxMessages(SpamConfig v) => v.maxMessages;
  static const Field<SpamConfig, int> _f$maxMessages = Field(
    'maxMessages',
    _$maxMessages,
    opt: true,
    def: 5,
  );
  static int _$windowSeconds(SpamConfig v) => v.windowSeconds;
  static const Field<SpamConfig, int> _f$windowSeconds = Field(
    'windowSeconds',
    _$windowSeconds,
    opt: true,
    def: 10,
  );
  static int _$repeatSeconds(SpamConfig v) => v.repeatSeconds;
  static const Field<SpamConfig, int> _f$repeatSeconds = Field(
    'repeatSeconds',
    _$repeatSeconds,
    opt: true,
    def: 30,
  );

  @override
  final MappableFields<SpamConfig> fields = const {
    #enabled: _f$enabled,
    #cooldownMillis: _f$cooldownMillis,
    #maxMessages: _f$maxMessages,
    #windowSeconds: _f$windowSeconds,
    #repeatSeconds: _f$repeatSeconds,
  };

  static SpamConfig _instantiate(DecodingData data) {
    return SpamConfig(
      enabled: data.dec(_f$enabled),
      cooldownMillis: data.dec(_f$cooldownMillis),
      maxMessages: data.dec(_f$maxMessages),
      windowSeconds: data.dec(_f$windowSeconds),
      repeatSeconds: data.dec(_f$repeatSeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SpamConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SpamConfig>(map);
  }

  static SpamConfig fromJson(String json) {
    return ensureInitialized().decodeJson<SpamConfig>(json);
  }
}

mixin SpamConfigMappable {
  String toJson() {
    return SpamConfigMapper.ensureInitialized().encodeJson<SpamConfig>(
      this as SpamConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return SpamConfigMapper.ensureInitialized().encodeMap<SpamConfig>(
      this as SpamConfig,
    );
  }

  SpamConfigCopyWith<SpamConfig, SpamConfig, SpamConfig> get copyWith =>
      _SpamConfigCopyWithImpl<SpamConfig, SpamConfig>(
        this as SpamConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SpamConfigMapper.ensureInitialized().stringifyValue(
      this as SpamConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return SpamConfigMapper.ensureInitialized().equalsValue(
      this as SpamConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return SpamConfigMapper.ensureInitialized().hashValue(this as SpamConfig);
  }
}

extension SpamConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SpamConfig, $Out> {
  SpamConfigCopyWith<$R, SpamConfig, $Out> get $asSpamConfig =>
      $base.as((v, t, t2) => _SpamConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SpamConfigCopyWith<$R, $In extends SpamConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? enabled,
    int? cooldownMillis,
    int? maxMessages,
    int? windowSeconds,
    int? repeatSeconds,
  });
  SpamConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SpamConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SpamConfig, $Out>
    implements SpamConfigCopyWith<$R, SpamConfig, $Out> {
  _SpamConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SpamConfig> $mapper =
      SpamConfigMapper.ensureInitialized();
  @override
  $R call({
    bool? enabled,
    int? cooldownMillis,
    int? maxMessages,
    int? windowSeconds,
    int? repeatSeconds,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (cooldownMillis != null) #cooldownMillis: cooldownMillis,
      if (maxMessages != null) #maxMessages: maxMessages,
      if (windowSeconds != null) #windowSeconds: windowSeconds,
      if (repeatSeconds != null) #repeatSeconds: repeatSeconds,
    }),
  );
  @override
  SpamConfig $make(CopyWithData data) => SpamConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    cooldownMillis: data.get(#cooldownMillis, or: $value.cooldownMillis),
    maxMessages: data.get(#maxMessages, or: $value.maxMessages),
    windowSeconds: data.get(#windowSeconds, or: $value.windowSeconds),
    repeatSeconds: data.get(#repeatSeconds, or: $value.repeatSeconds),
  );

  @override
  SpamConfigCopyWith<$R2, SpamConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SpamConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WelcomeConfigMapper extends ClassMapperBase<WelcomeConfig> {
  WelcomeConfigMapper._();

  static WelcomeConfigMapper? _instance;
  static WelcomeConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WelcomeConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'WelcomeConfig';

  static bool _$enabled(WelcomeConfig v) => v.enabled;
  static const Field<WelcomeConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int _$delaySeconds(WelcomeConfig v) => v.delaySeconds;
  static const Field<WelcomeConfig, int> _f$delaySeconds = Field(
    'delaySeconds',
    _$delaySeconds,
    opt: true,
    def: 1,
  );
  static String _$title(WelcomeConfig v) => v.title;
  static const Field<WelcomeConfig, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
    def: '&6Welcome back',
  );
  static String _$subtitle(WelcomeConfig v) => v.subtitle;
  static const Field<WelcomeConfig, String> _f$subtitle = Field(
    'subtitle',
    _$subtitle,
    opt: true,
    def: '&e{name}',
  );
  static String _$firstTitle(WelcomeConfig v) => v.firstTitle;
  static const Field<WelcomeConfig, String> _f$firstTitle = Field(
    'firstTitle',
    _$firstTitle,
    opt: true,
    def: '&6Welcome',
  );
  static String _$firstSubtitle(WelcomeConfig v) => v.firstSubtitle;
  static const Field<WelcomeConfig, String> _f$firstSubtitle = Field(
    'firstSubtitle',
    _$firstSubtitle,
    opt: true,
    def: '&eenjoy your stay, {name}',
  );

  @override
  final MappableFields<WelcomeConfig> fields = const {
    #enabled: _f$enabled,
    #delaySeconds: _f$delaySeconds,
    #title: _f$title,
    #subtitle: _f$subtitle,
    #firstTitle: _f$firstTitle,
    #firstSubtitle: _f$firstSubtitle,
  };

  static WelcomeConfig _instantiate(DecodingData data) {
    return WelcomeConfig(
      enabled: data.dec(_f$enabled),
      delaySeconds: data.dec(_f$delaySeconds),
      title: data.dec(_f$title),
      subtitle: data.dec(_f$subtitle),
      firstTitle: data.dec(_f$firstTitle),
      firstSubtitle: data.dec(_f$firstSubtitle),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WelcomeConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WelcomeConfig>(map);
  }

  static WelcomeConfig fromJson(String json) {
    return ensureInitialized().decodeJson<WelcomeConfig>(json);
  }
}

mixin WelcomeConfigMappable {
  String toJson() {
    return WelcomeConfigMapper.ensureInitialized().encodeJson<WelcomeConfig>(
      this as WelcomeConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return WelcomeConfigMapper.ensureInitialized().encodeMap<WelcomeConfig>(
      this as WelcomeConfig,
    );
  }

  WelcomeConfigCopyWith<WelcomeConfig, WelcomeConfig, WelcomeConfig>
  get copyWith => _WelcomeConfigCopyWithImpl<WelcomeConfig, WelcomeConfig>(
    this as WelcomeConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return WelcomeConfigMapper.ensureInitialized().stringifyValue(
      this as WelcomeConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return WelcomeConfigMapper.ensureInitialized().equalsValue(
      this as WelcomeConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return WelcomeConfigMapper.ensureInitialized().hashValue(
      this as WelcomeConfig,
    );
  }
}

extension WelcomeConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WelcomeConfig, $Out> {
  WelcomeConfigCopyWith<$R, WelcomeConfig, $Out> get $asWelcomeConfig =>
      $base.as((v, t, t2) => _WelcomeConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WelcomeConfigCopyWith<$R, $In extends WelcomeConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? enabled,
    int? delaySeconds,
    String? title,
    String? subtitle,
    String? firstTitle,
    String? firstSubtitle,
  });
  WelcomeConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _WelcomeConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WelcomeConfig, $Out>
    implements WelcomeConfigCopyWith<$R, WelcomeConfig, $Out> {
  _WelcomeConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WelcomeConfig> $mapper =
      WelcomeConfigMapper.ensureInitialized();
  @override
  $R call({
    bool? enabled,
    int? delaySeconds,
    String? title,
    String? subtitle,
    String? firstTitle,
    String? firstSubtitle,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (delaySeconds != null) #delaySeconds: delaySeconds,
      if (title != null) #title: title,
      if (subtitle != null) #subtitle: subtitle,
      if (firstTitle != null) #firstTitle: firstTitle,
      if (firstSubtitle != null) #firstSubtitle: firstSubtitle,
    }),
  );
  @override
  WelcomeConfig $make(CopyWithData data) => WelcomeConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    delaySeconds: data.get(#delaySeconds, or: $value.delaySeconds),
    title: data.get(#title, or: $value.title),
    subtitle: data.get(#subtitle, or: $value.subtitle),
    firstTitle: data.get(#firstTitle, or: $value.firstTitle),
    firstSubtitle: data.get(#firstSubtitle, or: $value.firstSubtitle),
  );

  @override
  WelcomeConfigCopyWith<$R2, WelcomeConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WelcomeConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ChatConfigMapper extends ClassMapperBase<ChatConfig> {
  ChatConfigMapper._();

  static ChatConfigMapper? _instance;
  static ChatConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatConfigMapper._());
      RankStyleMapper.ensureInitialized();
      SpamConfigMapper.ensureInitialized();
      WelcomeConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChatConfig';

  static String _$format(ChatConfig v) => v.format;
  static const Field<ChatConfig, String> _f$format = Field(
    'format',
    _$format,
    opt: true,
    def: '{prefix}{name}{suffix}&8: &f{message}',
  );
  static String _$joinFormat(ChatConfig v) => v.joinFormat;
  static const Field<ChatConfig, String> _f$joinFormat = Field(
    'joinFormat',
    _$joinFormat,
    opt: true,
    def: '&e{prefix}{name}&e joined the game',
  );
  static String _$leaveFormat(ChatConfig v) => v.leaveFormat;
  static const Field<ChatConfig, String> _f$leaveFormat = Field(
    'leaveFormat',
    _$leaveFormat,
    opt: true,
    def: '&e{prefix}{name}&e left the game',
  );
  static String _$firstJoinFormat(ChatConfig v) => v.firstJoinFormat;
  static const Field<ChatConfig, String> _f$firstJoinFormat = Field(
    'firstJoinFormat',
    _$firstJoinFormat,
    opt: true,
    def: '&6&l» &eWelcome &6{name}&e, our player number &6{count}&e!',
  );
  static String _$pmSentFormat(ChatConfig v) => v.pmSentFormat;
  static const Field<ChatConfig, String> _f$pmSentFormat = Field(
    'pmSentFormat',
    _$pmSentFormat,
    opt: true,
    def: '&8[&7You &8→ &f{player}&8] &7{message}',
  );
  static String _$pmReceivedFormat(ChatConfig v) => v.pmReceivedFormat;
  static const Field<ChatConfig, String> _f$pmReceivedFormat = Field(
    'pmReceivedFormat',
    _$pmReceivedFormat,
    opt: true,
    def: '&8[&f{player} &8→ &7You&8] &7{message}',
  );
  static String _$spyFormat(ChatConfig v) => v.spyFormat;
  static const Field<ChatConfig, String> _f$spyFormat = Field(
    'spyFormat',
    _$spyFormat,
    opt: true,
    def: '&8[&6Spy&8] &7{from} &8→ &7{to}&8: &7{message}',
  );
  static List<RankStyle> _$ranks(ChatConfig v) => v.ranks;
  static const Field<ChatConfig, List<RankStyle>> _f$ranks = Field(
    'ranks',
    _$ranks,
    opt: true,
    def: const [
      RankStyle(
        permission: 'commons:chat.rank.admin',
        prefix: '&c[Admin] ',
        color: '&c',
      ),
      RankStyle(
        permission: 'commons:chat.rank.moderator',
        prefix: '&9[Mod] ',
        color: '&9',
      ),
      RankStyle(
        permission: 'commons:chat.rank.vip',
        prefix: '&6[VIP] ',
        color: '&6',
      ),
    ],
  );
  static RankStyle _$defaultRank(ChatConfig v) => v.defaultRank;
  static const Field<ChatConfig, RankStyle> _f$defaultRank = Field(
    'defaultRank',
    _$defaultRank,
    opt: true,
    def: const RankStyle(color: '&7'),
  );
  static bool _$mentions(ChatConfig v) => v.mentions;
  static const Field<ChatConfig, bool> _f$mentions = Field(
    'mentions',
    _$mentions,
    opt: true,
    def: true,
  );
  static String _$mentionSound(ChatConfig v) => v.mentionSound;
  static const Field<ChatConfig, String> _f$mentionSound = Field(
    'mentionSound',
    _$mentionSound,
    opt: true,
    def: 'minecraft:block.note_block.pling',
  );
  static SpamConfig _$spam(ChatConfig v) => v.spam;
  static const Field<ChatConfig, SpamConfig> _f$spam = Field(
    'spam',
    _$spam,
    opt: true,
    def: const SpamConfig(),
  );
  static WelcomeConfig _$welcome(ChatConfig v) => v.welcome;
  static const Field<ChatConfig, WelcomeConfig> _f$welcome = Field(
    'welcome',
    _$welcome,
    opt: true,
    def: const WelcomeConfig(),
  );

  @override
  final MappableFields<ChatConfig> fields = const {
    #format: _f$format,
    #joinFormat: _f$joinFormat,
    #leaveFormat: _f$leaveFormat,
    #firstJoinFormat: _f$firstJoinFormat,
    #pmSentFormat: _f$pmSentFormat,
    #pmReceivedFormat: _f$pmReceivedFormat,
    #spyFormat: _f$spyFormat,
    #ranks: _f$ranks,
    #defaultRank: _f$defaultRank,
    #mentions: _f$mentions,
    #mentionSound: _f$mentionSound,
    #spam: _f$spam,
    #welcome: _f$welcome,
  };

  static ChatConfig _instantiate(DecodingData data) {
    return ChatConfig(
      format: data.dec(_f$format),
      joinFormat: data.dec(_f$joinFormat),
      leaveFormat: data.dec(_f$leaveFormat),
      firstJoinFormat: data.dec(_f$firstJoinFormat),
      pmSentFormat: data.dec(_f$pmSentFormat),
      pmReceivedFormat: data.dec(_f$pmReceivedFormat),
      spyFormat: data.dec(_f$spyFormat),
      ranks: data.dec(_f$ranks),
      defaultRank: data.dec(_f$defaultRank),
      mentions: data.dec(_f$mentions),
      mentionSound: data.dec(_f$mentionSound),
      spam: data.dec(_f$spam),
      welcome: data.dec(_f$welcome),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChatConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChatConfig>(map);
  }

  static ChatConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ChatConfig>(json);
  }
}

mixin ChatConfigMappable {
  String toJson() {
    return ChatConfigMapper.ensureInitialized().encodeJson<ChatConfig>(
      this as ChatConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return ChatConfigMapper.ensureInitialized().encodeMap<ChatConfig>(
      this as ChatConfig,
    );
  }

  ChatConfigCopyWith<ChatConfig, ChatConfig, ChatConfig> get copyWith =>
      _ChatConfigCopyWithImpl<ChatConfig, ChatConfig>(
        this as ChatConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ChatConfigMapper.ensureInitialized().stringifyValue(
      this as ChatConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ChatConfigMapper.ensureInitialized().equalsValue(
      this as ChatConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ChatConfigMapper.ensureInitialized().hashValue(this as ChatConfig);
  }
}

extension ChatConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ChatConfig, $Out> {
  ChatConfigCopyWith<$R, ChatConfig, $Out> get $asChatConfig =>
      $base.as((v, t, t2) => _ChatConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ChatConfigCopyWith<$R, $In extends ChatConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, RankStyle, RankStyleCopyWith<$R, RankStyle, RankStyle>>
  get ranks;
  RankStyleCopyWith<$R, RankStyle, RankStyle> get defaultRank;
  SpamConfigCopyWith<$R, SpamConfig, SpamConfig> get spam;
  WelcomeConfigCopyWith<$R, WelcomeConfig, WelcomeConfig> get welcome;
  $R call({
    String? format,
    String? joinFormat,
    String? leaveFormat,
    String? firstJoinFormat,
    String? pmSentFormat,
    String? pmReceivedFormat,
    String? spyFormat,
    List<RankStyle>? ranks,
    RankStyle? defaultRank,
    bool? mentions,
    String? mentionSound,
    SpamConfig? spam,
    WelcomeConfig? welcome,
  });
  ChatConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ChatConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ChatConfig, $Out>
    implements ChatConfigCopyWith<$R, ChatConfig, $Out> {
  _ChatConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ChatConfig> $mapper =
      ChatConfigMapper.ensureInitialized();
  @override
  ListCopyWith<$R, RankStyle, RankStyleCopyWith<$R, RankStyle, RankStyle>>
  get ranks => ListCopyWith(
    $value.ranks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(ranks: v),
  );
  @override
  RankStyleCopyWith<$R, RankStyle, RankStyle> get defaultRank =>
      $value.defaultRank.copyWith.$chain((v) => call(defaultRank: v));
  @override
  SpamConfigCopyWith<$R, SpamConfig, SpamConfig> get spam =>
      $value.spam.copyWith.$chain((v) => call(spam: v));
  @override
  WelcomeConfigCopyWith<$R, WelcomeConfig, WelcomeConfig> get welcome =>
      $value.welcome.copyWith.$chain((v) => call(welcome: v));
  @override
  $R call({
    String? format,
    String? joinFormat,
    String? leaveFormat,
    String? firstJoinFormat,
    String? pmSentFormat,
    String? pmReceivedFormat,
    String? spyFormat,
    List<RankStyle>? ranks,
    RankStyle? defaultRank,
    bool? mentions,
    String? mentionSound,
    SpamConfig? spam,
    WelcomeConfig? welcome,
  }) => $apply(
    FieldCopyWithData({
      if (format != null) #format: format,
      if (joinFormat != null) #joinFormat: joinFormat,
      if (leaveFormat != null) #leaveFormat: leaveFormat,
      if (firstJoinFormat != null) #firstJoinFormat: firstJoinFormat,
      if (pmSentFormat != null) #pmSentFormat: pmSentFormat,
      if (pmReceivedFormat != null) #pmReceivedFormat: pmReceivedFormat,
      if (spyFormat != null) #spyFormat: spyFormat,
      if (ranks != null) #ranks: ranks,
      if (defaultRank != null) #defaultRank: defaultRank,
      if (mentions != null) #mentions: mentions,
      if (mentionSound != null) #mentionSound: mentionSound,
      if (spam != null) #spam: spam,
      if (welcome != null) #welcome: welcome,
    }),
  );
  @override
  ChatConfig $make(CopyWithData data) => ChatConfig(
    format: data.get(#format, or: $value.format),
    joinFormat: data.get(#joinFormat, or: $value.joinFormat),
    leaveFormat: data.get(#leaveFormat, or: $value.leaveFormat),
    firstJoinFormat: data.get(#firstJoinFormat, or: $value.firstJoinFormat),
    pmSentFormat: data.get(#pmSentFormat, or: $value.pmSentFormat),
    pmReceivedFormat: data.get(#pmReceivedFormat, or: $value.pmReceivedFormat),
    spyFormat: data.get(#spyFormat, or: $value.spyFormat),
    ranks: data.get(#ranks, or: $value.ranks),
    defaultRank: data.get(#defaultRank, or: $value.defaultRank),
    mentions: data.get(#mentions, or: $value.mentions),
    mentionSound: data.get(#mentionSound, or: $value.mentionSound),
    spam: data.get(#spam, or: $value.spam),
    welcome: data.get(#welcome, or: $value.welcome),
  );

  @override
  ChatConfigCopyWith<$R2, ChatConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ChatConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IgnoreDataMapper extends ClassMapperBase<IgnoreData> {
  IgnoreDataMapper._();

  static IgnoreDataMapper? _instance;
  static IgnoreDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IgnoreDataMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'IgnoreData';

  static Map<String, List<String>> _$ignored(IgnoreData v) => v.ignored;
  static const Field<IgnoreData, Map<String, List<String>>> _f$ignored = Field(
    'ignored',
    _$ignored,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<IgnoreData> fields = const {#ignored: _f$ignored};

  static IgnoreData _instantiate(DecodingData data) {
    return IgnoreData(ignored: data.dec(_f$ignored));
  }

  @override
  final Function instantiate = _instantiate;

  static IgnoreData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IgnoreData>(map);
  }

  static IgnoreData fromJson(String json) {
    return ensureInitialized().decodeJson<IgnoreData>(json);
  }
}

mixin IgnoreDataMappable {
  String toJson() {
    return IgnoreDataMapper.ensureInitialized().encodeJson<IgnoreData>(
      this as IgnoreData,
    );
  }

  Map<String, dynamic> toMap() {
    return IgnoreDataMapper.ensureInitialized().encodeMap<IgnoreData>(
      this as IgnoreData,
    );
  }

  IgnoreDataCopyWith<IgnoreData, IgnoreData, IgnoreData> get copyWith =>
      _IgnoreDataCopyWithImpl<IgnoreData, IgnoreData>(
        this as IgnoreData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IgnoreDataMapper.ensureInitialized().stringifyValue(
      this as IgnoreData,
    );
  }

  @override
  bool operator ==(Object other) {
    return IgnoreDataMapper.ensureInitialized().equalsValue(
      this as IgnoreData,
      other,
    );
  }

  @override
  int get hashCode {
    return IgnoreDataMapper.ensureInitialized().hashValue(this as IgnoreData);
  }
}

extension IgnoreDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IgnoreData, $Out> {
  IgnoreDataCopyWith<$R, IgnoreData, $Out> get $asIgnoreData =>
      $base.as((v, t, t2) => _IgnoreDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IgnoreDataCopyWith<$R, $In extends IgnoreData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    List<String>,
    ObjectCopyWith<$R, List<String>, List<String>>
  >
  get ignored;
  $R call({Map<String, List<String>>? ignored});
  IgnoreDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IgnoreDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IgnoreData, $Out>
    implements IgnoreDataCopyWith<$R, IgnoreData, $Out> {
  _IgnoreDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IgnoreData> $mapper =
      IgnoreDataMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    List<String>,
    ObjectCopyWith<$R, List<String>, List<String>>
  >
  get ignored => MapCopyWith(
    $value.ignored,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(ignored: v),
  );
  @override
  $R call({Map<String, List<String>>? ignored}) =>
      $apply(FieldCopyWithData({if (ignored != null) #ignored: ignored}));
  @override
  IgnoreData $make(CopyWithData data) =>
      IgnoreData(ignored: data.get(#ignored, or: $value.ignored));

  @override
  IgnoreDataCopyWith<$R2, IgnoreData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IgnoreDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


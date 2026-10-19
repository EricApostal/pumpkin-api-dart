// NeoForge recipe load conditions (`neoforge:conditions`), evaluated at load time (pure).

/// What the conditions can ask about the running server.
abstract interface class ConditionContext {
  bool modLoaded(String modId);
  bool itemExists(String itemKey);
  bool tagEmpty(String tag);
}

/// The server's view: only vanilla, NeoForge and Create content exists. A tag counts as not
/// empty (recipes with an empty tag ingredient simply never match).
final class DefaultConditionContext implements ConditionContext {
  final bool Function(String itemKey)? itemKnown;

  const DefaultConditionContext({this.itemKnown});

  static const Set<String> loadedMods = {'minecraft', 'neoforge', 'create', 'c'};

  @override
  bool modLoaded(String modId) => loadedMods.contains(modId);

  @override
  bool itemExists(String itemKey) => itemKnown?.call(itemKey) ?? loadedMods.contains(itemKey.split(':').first);

  @override
  bool tagEmpty(String tag) => false;
}

/// Evaluates a list of conditions (all must hold). Unknown condition types fail the recipe.
bool conditionsHold(List<Object?>? conditions, ConditionContext ctx) {
  if (conditions == null) return true;
  for (final c in conditions) {
    if (!_holds(c, ctx)) return false;
  }
  return true;
}

bool _holds(Object? c, ConditionContext ctx) {
  if (c is! Map) return false;
  switch (c['type']) {
    case 'neoforge:true':
      return true;
    case 'neoforge:false':
      return false;
    case 'neoforge:not':
      return !_holds(c['value'], ctx);
    case 'neoforge:and':
      return [for (final v in (c['values'] as List? ?? const [])) v].every((v) => _holds(v, ctx));
    case 'neoforge:or':
      return [for (final v in (c['values'] as List? ?? const [])) v].any((v) => _holds(v, ctx));
    case 'neoforge:mod_loaded':
      return ctx.modLoaded('${c['modid']}');
    case 'neoforge:item_exists':
      return ctx.itemExists('${c['item']}');
    case 'neoforge:tag_empty':
      return ctx.tagEmpty('${c['tag']}');
    default:
      return false;
  }
}

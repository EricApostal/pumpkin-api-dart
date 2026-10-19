// `FlapDisplayLayout` (pure): the sections of one line of a display board and the key of the
// layout they were configured for.
import '../util/ctag.dart';
import 'flap_display_section.dart';

/// `FlapDisplayLayout`.
class FlapDisplayLayout {
  late List<FlapDisplaySection> sections;
  late String layoutKey;

  FlapDisplayLayout(int maxCharCount) {
    loadDefault(maxCharCount);
  }

  /// `loadDefault(maxCharCount)`.
  void loadDefault(int maxCharCount) {
    configure('Default', [FlapDisplaySection(maxCharCount * FlapDisplaySection.MONOSPACE, 'alphabet', false, false)]);
  }

  /// `isLayout(key)`.
  bool isLayout(String key) => layoutKey == key;

  /// `configure(layoutKey, sections)`.
  void configure(String layoutKey, List<FlapDisplaySection> sections) {
    this.layoutKey = layoutKey;
    this.sections = sections;
  }

  /// `write(registries)`.
  CTag write({bool clearTransition = true}) {
    final tag = CTag();
    tag.putString('Key', layoutKey);
    tag.putCompoundList('Sections', [for (final s in sections) s.write(clearTransition: clearTransition)]);
    return tag;
  }

  /// `read(tag, registries)`: sections of an unchanged layout key are updated in place, a new key
  /// replaces them.
  void read(CTag tag) {
    final prevKey = layoutKey;
    layoutKey = tag.getString('Key');
    final sectionsTag = tag.getCompoundList('Sections');

    if (prevKey != layoutKey) {
      sections = [for (final s in sectionsTag) FlapDisplaySection.load(s)];
      return;
    }

    var index = 0;
    for (final nbt in sectionsTag) {
      sections[index++].update(nbt);
    }
  }

  /// `getSections()`.
  List<FlapDisplaySection> getSections() => sections;
}

// Golden byte vectors for the NeoForge 26.3 negotiation payloads.
//
// NeoForge's codecs are built from Minecraft's codec primitives (map, collection,
// optional, indexed enums, VarInt, string, identifier). This program rebuilds each
// payload codec from NeoForge's source (see docs/neoforge-protocol.md for the
// file of each) with the very same primitives of Minecraft 1.21.11 (yarn names:
// PacketCodecs = ByteBufCodecs, PacketByteBuf = FriendlyByteBuf, Identifier,
// NetworkPhase = ConnectionProtocol, NetworkSide = PacketFlow) and prints the
// bytes. Output: test/golden/neoforge_codecs.txt, which the Dart and Python tests
// compare against.
//
// Run (classpath: the yarn-named 1.21.11 jar and its libraries: netty-buffer,
// netty-common, fastutil, guava, slf4j-api, DataFixerUpper 10.x, brigadier, gson,
// joml, log4j-api, commons-lang3, jsr305):
//   javac -cp "$CP" Golden.java && java -cp "$CP:." Golden > ../../test/golden/neoforge_codecs.txt
// (drop the SLF4J/Log4j warnings from the output).

import net.minecraft.network.PacketByteBuf;
import net.minecraft.network.NetworkPhase;
import net.minecraft.network.NetworkSide;
import net.minecraft.network.codec.PacketCodec;
import net.minecraft.network.codec.PacketCodecs;
import net.minecraft.util.Identifier;
import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import java.util.*;

/** Mirrors the NeoForge codecs (26.3.x) with the identical primitives of 1.21.11 (yarn names). */
public class Golden {
  static <T> void out(String name, PacketCodec<ByteBuf, T> codec, T value) {
    PacketByteBuf b = new PacketByteBuf(Unpooled.buffer());
    codec.encode(b, value);
    System.out.println(name + "=" + HexFormat.of().formatHex(b.array(), 0, b.writerIndex()));
  }
  static final PacketCodec<ByteBuf, Identifier> ID = Identifier.PACKET_CODEC;
  static final PacketCodec<ByteBuf, NetworkPhase> PHASE = PacketCodecs.indexed(i -> NetworkPhase.values()[i], NetworkPhase::ordinal);
  static final PacketCodec<ByteBuf, NetworkSide> SIDE = PacketCodecs.indexed(i -> NetworkSide.values()[i], NetworkSide::ordinal);

  record Query(Identifier id, String version, Optional<NetworkSide> flow, boolean optional) {}
  static final PacketCodec<ByteBuf, Query> QUERY = PacketCodec.tuple(
      ID, Query::id, PacketCodecs.STRING, Query::version,
      PacketCodecs.optional(SIDE), Query::flow, PacketCodecs.BOOLEAN, Query::optional, Query::new);

  record Chan(Identifier id, String v) {}
  static final PacketCodec<ByteBuf, Chan> CHAN = PacketCodec.tuple(ID, Chan::id, PacketCodecs.STRING, Chan::v, Chan::new);

  record Ext(int vanilla, int total, List<String> entries) {}
  static final PacketCodec<ByteBuf, Ext> EXT = PacketCodec.tuple(
      PacketCodecs.VAR_INT, Ext::vanilla, PacketCodecs.VAR_INT, Ext::total,
      PacketCodecs.collection(ArrayList::new, PacketCodecs.STRING), Ext::entries, Ext::new);
  record Entry(String cls, String check, Optional<Ext> data) {}
  static final PacketCodec<ByteBuf, Entry> ENTRY = PacketCodec.tuple(
      PacketCodecs.STRING, Entry::cls, PacketCodecs.STRING, Entry::check,
      PacketCodecs.optional(EXT), Entry::data, Entry::new);

  record Known(Identifier id, boolean mandatory) {}
  static final PacketCodec<ByteBuf, Known> KNOWN = PacketCodec.tuple(ID, Known::id, PacketCodecs.BOOLEAN, Known::mandatory, Known::new);

  record Snap(TreeMap<Integer, Identifier> ids, TreeMap<Identifier, Identifier> aliases) {}
  static final PacketCodec<ByteBuf, Snap> SNAP = PacketCodec.tuple(
      PacketCodecs.map(i -> new TreeMap<Integer, Identifier>(), PacketCodecs.VAR_INT, ID), Snap::ids,
      PacketCodecs.map(i -> new TreeMap<Identifier, Identifier>(Comparator.comparing(Identifier::toString)), ID, ID), Snap::aliases, Snap::new);
  record Frozen(Identifier name, Snap snap) {}
  static final PacketCodec<ByteBuf, Frozen> FROZEN = PacketCodec.tuple(ID, Frozen::name, SNAP, Frozen::snap, Frozen::new);

  public static void main(String[] a) {
    System.out.println("ordinals PLAY=" + NetworkPhase.PLAY.ordinal() + " CONFIGURATION=" + NetworkPhase.CONFIGURATION.ordinal()
        + " SERVERBOUND=" + NetworkSide.SERVERBOUND.ordinal() + " CLIENTBOUND=" + NetworkSide.CLIENTBOUND.ordinal()
        + " ids=" + NetworkPhase.PLAY.getId() + "," + NetworkPhase.CONFIGURATION.getId());
    var queryMapCodec = PacketCodecs.map(i -> new IdentityHashMap<NetworkPhase, Set<Query>>(), PHASE, PacketCodecs.collection(i -> (Set<Query>) new HashSet<Query>(), QUERY));
    var q1 = new IdentityHashMap<NetworkPhase, Set<Query>>();
    q1.put(NetworkPhase.CONFIGURATION, Set.of(new Query(Identifier.of("neoforge", "frozen_registry_sync_completed"), "1", Optional.empty(), true)));
    out("query_config_bidirectional", queryMapCodec, q1);
    var q2 = new IdentityHashMap<NetworkPhase, Set<Query>>();
    q2.put(NetworkPhase.PLAY, Set.of(new Query(Identifier.of("neoforge", "recipe_content"), "1", Optional.of(NetworkSide.CLIENTBOUND), true)));
    out("query_play_clientbound", queryMapCodec, q2);
    out("query_empty", queryMapCodec, new IdentityHashMap<>());
    var qb = new IdentityHashMap<NetworkPhase, Set<Query>>();
    qb.put(NetworkPhase.CONFIGURATION, Set.of(new Query(Identifier.of("mymod", "x"), "2", Optional.of(NetworkSide.SERVERBOUND), false)));
    out("query_config_serverbound_required", queryMapCodec, qb);

    var setupCodec = PacketCodecs.map(i -> new IdentityHashMap<NetworkPhase, Map<Identifier, Chan>>(), PHASE,
        PacketCodecs.map(i -> new HashMap<Identifier, Chan>(), ID, CHAN));
    var s1 = new IdentityHashMap<NetworkPhase, Map<Identifier, Chan>>();
    s1.put(NetworkPhase.CONFIGURATION, Map.of(Identifier.of("neoforge", "frozen_registry"), new Chan(Identifier.of("neoforge", "frozen_registry"), "1")));
    out("network_config_one", setupCodec, s1);
    var s2 = new IdentityHashMap<NetworkPhase, Map<Identifier, Chan>>();
    s2.put(NetworkPhase.PLAY, Map.of());
    out("network_play_empty", setupCodec, s2);

    out("common_version", PacketCodecs.VAR_INT.collect(PacketCodecs.toList()), List.of(1));
    out("common_version_two", PacketCodecs.VAR_INT.collect(PacketCodecs.toList()), List.of(1, 300));

    // c:register: varint version, string protocol id, collection of identifiers
    PacketByteBuf cr = new PacketByteBuf(Unpooled.buffer());
    PacketCodecs.VAR_INT.encode(cr, 1); PacketCodecs.STRING.encode(cr, NetworkPhase.PLAY.getId());
    PacketCodecs.collection(HashSet::new, ID).encode(cr, new HashSet<>(List.of(Identifier.of("c", "foo"))));
    System.out.println("common_register_play_one=" + HexFormat.of().formatHex(cr.array(), 0, cr.writerIndex()));

    var idList = ID.collect(PacketCodecs.toList());
    out("sync_start", idList, List.of(Identifier.of("minecraft", "item"), Identifier.of("minecraft", "block")));

    var ids = new TreeMap<Integer, Identifier>();
    ids.put(0, Identifier.of("minecraft", "air")); ids.put(1, Identifier.of("minecraft", "stone")); ids.put(300, Identifier.of("lonsdaleite", "raw_lonsdaleite"));
    out("frozen_registry_item", FROZEN, new Frozen(Identifier.of("minecraft", "item"), new Snap(ids, new TreeMap<>())));
    var al = new TreeMap<Identifier, Identifier>(Comparator.comparing(Identifier::toString));
    al.put(Identifier.of("old", "thing"), Identifier.of("minecraft", "stone"));
    out("frozen_registry_with_alias", FROZEN, new Frozen(Identifier.of("minecraft", "block"), new Snap(new TreeMap<>(Map.of(0, Identifier.of("minecraft", "air"))), al)));

    var knownCodec = PacketCodecs.map(i -> new HashMap<Identifier, List<Known>>(), ID, KNOWN.collect(PacketCodecs.toList()));
    out("known_data_maps", knownCodec, new HashMap<>(Map.of(Identifier.of("minecraft", "item"), List.of(new Known(Identifier.of("neoforge", "villager_compostables"), false), new Known(Identifier.of("mymod", "tiers"), true)))));
    var replyCodec = PacketCodecs.map(i -> new HashMap<Identifier, List<Identifier>>(), ID, ID.collect(PacketCodecs.toList()));
    out("known_data_maps_reply", replyCodec, new HashMap<>(Map.of(Identifier.of("minecraft", "item"), List.of(Identifier.of("neoforge", "villager_compostables")))));

    var enumCodec = PacketCodecs.collection(ArrayList::new, ENTRY);
    out("enum_data_plain", enumCodec, new ArrayList<>(List.of(new Entry("net.minecraft.world.item.Rarity", "BIDIRECTIONAL", Optional.empty()))));
    out("enum_data_extended", enumCodec, new ArrayList<>(List.of(new Entry("x.Y", "CLIENTBOUND", Optional.of(new Ext(2, 4, List.of("A", "B")))))));
    out("enum_data_empty", enumCodec, new ArrayList<>());
    out("feature_flags_one", PacketCodecs.collection(i -> new HashSet<Identifier>(), ID), new HashSet<>(List.of(Identifier.of("mymod", "flag"))));
    out("feature_flags_empty", PacketCodecs.collection(i -> new HashSet<Identifier>(), ID), new HashSet<>());
    PacketByteBuf cf = new PacketByteBuf(Unpooled.buffer());
    PacketCodecs.STRING.encode(cf, "neoforge-server.toml"); cf.writeByteArray(new byte[]{'a', '=', '1'});
    System.out.println("config_file=" + HexFormat.of().formatHex(cf.array(), 0, cf.writerIndex()));
  }
}

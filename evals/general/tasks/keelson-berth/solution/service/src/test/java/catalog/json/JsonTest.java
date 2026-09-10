package catalog.json;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JsonTest {

    private final JsonCodec json = new JsonCodec();

    @Test
    void parsesScalars() throws Exception {
        assertEquals(Long.valueOf(42), json.parse("42"));
        assertEquals(Long.valueOf(-7), json.parse("-7"));
        assertEquals(0.5, json.parse("0.5"));
        assertEquals(1.5e3, (Double) json.parse("1.5e3"), 0.0);
        assertEquals("hello", json.parse("\"hello\""));
        assertEquals(Boolean.TRUE, json.parse("true"));
        assertEquals(Boolean.FALSE, json.parse("false"));
        assertNull(json.parse("null"));
    }

    @Test
    void parsesNestedStructures() throws Exception {
        Object parsed = json.parse(
                "{\"a\": [1, 2.5, \"x\"], \"b\": {\"c\": null, \"d\": true}}");
        Map<?, ?> root = assertInstanceOf(Map.class, parsed);
        List<?> a = assertInstanceOf(List.class, root.get("a"));
        assertEquals(Long.valueOf(1), a.get(0));
        assertEquals(2.5, (Double) a.get(1), 0.0);
        assertEquals("x", a.get(2));
        Map<?, ?> b = assertInstanceOf(Map.class, root.get("b"));
        assertNull(b.get("c"));
        assertEquals(Boolean.TRUE, b.get("d"));
    }

    @Test
    void handlesEscapesAndUnicode() throws Exception {
        assertEquals("quote\"back\\slash", json.parse(
                "\"quote\\\"back\\\\slash\""));
        assertEquals("line\nbreak", json.parse("\"line\\nbreak\""));
        assertEquals("\u0001", json.parse("\"\\u0001\""));
        assertEquals("caf\u00e9", json.parse("\"caf\\u00e9\""));
        // surrogate pair (\uD83D\uDE00 = U+1F600)
        assertEquals("\ud83d\ude00", json.parse("\"\\ud83d\\ude00\""));
    }

    @Test
    void ignoresWhitespace() throws Exception {
        assertEquals("ok", json.parse("  \n\t\"ok\" \r"));
    }

    @Test
    void rejectsMalformedInput() {
        for (String bad : new String[]{
                "", "{", "[1, 2", "\"unterminated", "tru", "nul", "{a: 1}",
                "{\"a\" 1}", "01", "1.", "1e", "{\"a\":1,}",
                "{\"a\":1} trailing"}) {
            assertThrows(JsonCodec.JsonException.class, () -> json.parse(bad),
                    "expected rejection of: " + bad);
        }
    }

    @Test
    void stringifiesShapes() {
        Map<String, Object> item = new java.util.LinkedHashMap<>();
        item.put("sku", "ql-001");
        item.put("price", 12.5);
        item.put("quantity", 3L);
        item.put("flag", Boolean.TRUE);
        item.put("none", null);
        item.put("name", "caf\u00e9 \"x\" \\ y");
        assertEquals(
                "{\"sku\":\"ql-001\",\"price\":12.5,\"quantity\":3,"
                        + "\"flag\":true,\"none\":null,"
                        + "\"name\":\"caf\u00e9 \\\"x\\\" \\\\ y\"}",
                json.stringify(item));
    }

    @Test
    void printsIntegralDoublesWithoutFractionalPart() {
        assertEquals("12", json.stringify(12.0));
        assertEquals("0", json.stringify(0.0));
        assertEquals("12.5", json.stringify(12.5));
        assertEquals("-3.25", json.stringify(-3.25));
    }

    @Test
    void roundTrips() throws Exception {
        Map<String, Object> original = new java.util.LinkedHashMap<>();
        original.put("items", List.of(
                Map.of("sku", "a", "price", 1.5),
                Map.of("sku", "b", "price", 2.5)));
        original.put("count", (long) 2);
        Object back = json.parse(json.stringify(original));
        assertEquals(original, back);
    }

    @Test
    void rejectsNonFiniteOutput() {
        assertThrows(IllegalArgumentException.class,
                () -> json.stringify(Double.NaN));
        assertThrows(IllegalArgumentException.class,
                () -> json.stringify(Double.POSITIVE_INFINITY));
    }

    @Test
    void parsesAndStringifiesListsAndMapsFromApi() throws Exception {
        Object parsed = json.parse("{\"items\":[],\"count\":0}");
        Map<?, ?> root = assertInstanceOf(Map.class, parsed);
        assertTrue(root.containsKey("items"));
        assertTrue(assertInstanceOf(List.class, root.get("items")).isEmpty());
        assertEquals(Long.valueOf(0), root.get("count"));
    }
}
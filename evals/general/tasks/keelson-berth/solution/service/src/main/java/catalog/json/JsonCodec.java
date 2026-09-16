package catalog.json;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A small, dependency-free JSON codec.
 *
 * The parse() side is a recursive-descent parser that builds the plain-Java
 * shape used everywhere in this service:
 *   Map<String,Object>   for objects (insertion-ordered),
 *   List<Object>         for arrays,
 *   String, Long, Double, Boolean, null
 * for scalars.  The stringify() side walks that same shape and emits
 * compact JSON (no whitespace).  All strings are handled as UTF-8.
 */
public final class JsonCodec {

    /** Raised when the input is not well-formed JSON. */
    public static final class JsonException extends Exception {
        public JsonException(String message) {
            super(message);
        }
    }

    /** Parses {@code text} into the plain-Java shape described above. */
    public Object parse(String text) throws JsonException {
        return new Parser(text).parseAll();
    }

    /** Serialises any value in the plain-Java shape to compact JSON. */
    public String stringify(Object value) {
        StringBuilder sb = new StringBuilder();
        write(sb, value);
        return sb.toString();
    }

    // ------------------------------------------------------------------
    // serialisation
    // ------------------------------------------------------------------

    private void write(StringBuilder sb, Object value) {
        if (value == null) {
            sb.append("null");
        } else if (value instanceof String s) {
            writeString(sb, s);
        } else if (value instanceof Boolean b) {
            sb.append(b ? "true" : "false");
        } else if (value instanceof Long l) {
            sb.append(l);
        } else if (value instanceof Integer i) {
            sb.append(i);
        } else if (value instanceof Double d) {
            writeNumber(sb, d);
        } else if (value instanceof Float f) {
            writeNumber(sb, f.doubleValue());
        } else if (value instanceof Number n) {
            // Any other numeric type arrives here (BigDecimal, AtomicInteger,
            // ...).  Emit it through a double so the output is always valid
            // JSON rather than whatever the type's toString() produces.
            writeNumber(sb, n.doubleValue());
        } else if (value instanceof Map<?, ?> m) {
            sb.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> e : m.entrySet()) {
                if (!first) {
                    sb.append(',');
                }
                first = false;
                writeString(sb, String.valueOf(e.getKey()));
                sb.append(':');
                write(sb, e.getValue());
            }
            sb.append('}');
        } else if (value instanceof Object[] array) {
            sb.append('[');
            boolean first = true;
            for (Object o : array) {
                if (!first) {
                    sb.append(',');
                }
                first = false;
                write(sb, o);
            }
            sb.append(']');
        } else if (value instanceof Iterable<?> iterable) {
            sb.append('[');
            boolean first = true;
            for (Object o : iterable) {
                if (!first) {
                    sb.append(',');
                }
                first = false;
                write(sb, o);
            }
            sb.append(']');
        } else {
            throw new IllegalArgumentException(
                    "cannot serialise " + value.getClass().getName());
        }
    }

    private void writeNumber(StringBuilder sb, double d) {
        if (Double.isNaN(d) || Double.isInfinite(d)) {
            throw new IllegalArgumentException("non-finite number in JSON output");
        }
        if (d == Math.rint(d) && Math.abs(d) < 1e15) {
            // Integral doubles (12.0, -3.0) print without a fraction part.
            sb.append((long) d);
        } else {
            sb.append(Double.toString(d));
        }
    }

    private void writeString(StringBuilder sb, String s) {
        sb.append('"');
        // Walk the string code point by code point.  Only the quote, the
        // backslash and C0 control characters need escaping; everything else
        // (including multibyte UTF-8 text) is emitted verbatim.
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                case '\b' -> sb.append("\\b");
                case '\f' -> sb.append("\\f");
                default -> {
                    if (c < 0x20) {
                        sb.append("\\u");
                        sb.append(String.format("%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
    }

    // ------------------------------------------------------------------
    // parsing
    // ------------------------------------------------------------------

    private static final class Parser {
        private final String text;
        private int pos;

        Parser(String text) {
            this.text = text;
        }

        Object parseAll() throws JsonException {
            Object value = parseValue();
            skipWhitespace();
            if (!atEnd()) {
                throw new JsonException("trailing characters after value");
            }
            return value;
        }

        private boolean atEnd() {
            return pos >= text.length();
        }

        private void skipWhitespace() {
            while (pos < text.length()) {
                char c = text.charAt(pos);
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    pos++;
                } else {
                    break;
                }
            }
        }

        private Object parseValue() throws JsonException {
            skipWhitespace();
            if (atEnd()) {
                throw new JsonException("unexpected end of input");
            }
            char c = text.charAt(pos);
            switch (c) {
                case '{' -> { return parseObject(); }
                case '[' -> { return parseArray(); }
                case '"' -> { return parseString(); }
                case 't' -> {
                    expect("true");
                    return Boolean.TRUE;
                }
                case 'f' -> {
                    expect("false");
                    return Boolean.FALSE;
                }
                case 'n' -> {
                    expect("null");
                    return null;
                }
                default -> {
                    if (c == '-' || (c >= '0' && c <= '9')) {
                        return parseNumber();
                    }
                    throw new JsonException("unexpected character '" + c + "' at " + pos);
                }
            }
        }

        private void expect(String word) throws JsonException {
            if (text.startsWith(word, pos)) {
                pos += word.length();
                return;
            }
            throw new JsonException("expected " + word + " at " + pos);
        }

        private Map<String, Object> parseObject() throws JsonException {
            pos++; // '{'
            Map<String, Object> map = new LinkedHashMap<>();
            skipWhitespace();
            if (!atEnd() && text.charAt(pos) == '}') {
                pos++;
                return map;
            }
            while (true) {
                skipWhitespace();
                if (atEnd() || text.charAt(pos) != '"') {
                    throw new JsonException("expected a string key at " + pos);
                }
                String key = parseString();
                skipWhitespace();
                if (atEnd() || text.charAt(pos) != ':') {
                    throw new JsonException("expected ':' at " + pos);
                }
                pos++;
                map.put(key, parseValue());
                skipWhitespace();
                if (atEnd()) {
                    throw new JsonException("unterminated object");
                }
                char c = text.charAt(pos);
                if (c == ',') {
                    pos++;
                } else if (c == '}') {
                    pos++;
                    return map;
                } else {
                    throw new JsonException("expected ',' or '}' at " + pos);
                }
            }
        }

        private List<Object> parseArray() throws JsonException {
            pos++; // '['
            List<Object> list = new ArrayList<>();
            skipWhitespace();
            if (!atEnd() && text.charAt(pos) == ']') {
                pos++;
                return list;
            }
            while (true) {
                list.add(parseValue());
                skipWhitespace();
                if (atEnd()) {
                    throw new JsonException("unterminated array");
                }
                char c = text.charAt(pos);
                if (c == ',') {
                    pos++;
                } else if (c == ']') {
                    pos++;
                    return list;
                } else {
                    throw new JsonException("expected ',' or ']' at " + pos);
                }
            }
        }

        private String parseString() throws JsonException {
            StringBuilder sb = new StringBuilder();
            pos++; // opening quote
            while (true) {
                if (atEnd()) {
                    throw new JsonException("unterminated string");
                }
                char c = text.charAt(pos++);
                if (c == '"') {
                    break;
                }
                if (c == '\\') {
                    if (atEnd()) {
                        throw new JsonException("unterminated escape sequence");
                    }
                    char e = text.charAt(pos++);
                    switch (e) {
                        case '"' -> sb.append('"');
                        case '\\' -> sb.append('\\');
                        case '/' -> sb.append('/');
                        case 'b' -> sb.append('\b');
                        case 'f' -> sb.append('\f');
                        case 'n' -> sb.append('\n');
                        case 'r' -> sb.append('\r');
                        case 't' -> sb.append('\t');
                        case 'u' -> sb.append(readUnicodeEscape());
                        default -> throw new JsonException("invalid escape \\" + e);
                    }
                } else {
                    sb.append(c);
                }
            }
            return sb.toString();
        }

        private String readUnicodeEscape() throws JsonException {
            if (pos + 4 > text.length()) {
                throw new JsonException("short \\u escape");
            }
            int cp;
            try {
                cp = Integer.parseInt(text.substring(pos, pos + 4), 16);
            } catch (NumberFormatException e) {
                throw new JsonException("bad \\u escape");
            }
            pos += 4;
            if (cp >= 0xD800 && cp <= 0xDBFF) {
                // High surrogate: must be followed by a low surrogate.
                if (pos + 6 <= text.length() && text.startsWith("\\u", pos)) {
                    int low;
                    try {
                        low = Integer.parseInt(text.substring(pos + 2, pos + 6), 16);
                    } catch (NumberFormatException e) {
                        low = -1;
                    }
                    if (low >= 0xDC00 && low <= 0xDFFF) {
                        pos += 6;
                        return new String(new int[]{cp, low}, 0, 2);
                    }
                }
                throw new JsonException("lone high surrogate");
            }
            return new String(Character.toChars(cp));
        }

        private Object parseNumber() throws JsonException {
            int start = pos;
            boolean isInt = true;
            if (pos < text.length() && text.charAt(pos) == '-') {
                pos++;
            }
            if (atEnd() || !isDigitAt(pos)) {
                throw new JsonException("bad number at " + pos);
            }
            if (text.charAt(pos) == '0') {
                pos++;
            } else {
                while (pos < text.length() && isDigitAt(pos)) {
                    pos++;
                }
            }
            if (pos < text.length() && text.charAt(pos) == '.') {
                isInt = false;
                pos++;
                if (atEnd() || !isDigitAt(pos)) {
                    throw new JsonException("bad number at " + pos);
                }
                while (pos < text.length() && isDigitAt(pos)) {
                    pos++;
                }
            }
            if (pos < text.length() && (text.charAt(pos) == 'e' || text.charAt(pos) == 'E')) {
                isInt = false;
                pos++;
                if (pos < text.length() && (text.charAt(pos) == '+' || text.charAt(pos) == '-')) {
                    pos++;
                }
                if (atEnd() || !isDigitAt(pos)) {
                    throw new JsonException("bad number at " + pos);
                }
                while (pos < text.length() && isDigitAt(pos)) {
                    pos++;
                }
            }
            String literal = text.substring(start, pos);
            if (isInt) {
                try {
                    return Long.parseLong(literal);
                } catch (NumberFormatException ignored) {
                    // Out of long range: fall through to the double form.
                }
            }
            return Double.parseDouble(literal);
        }

        private boolean isDigitAt(int i) {
            char c = text.charAt(i);
            return c >= '0' && c <= '9';
        }
    }
}
package bridge;

import java.lang.reflect.Array;
import java.util.*;

/** Small writer for the bridge protocol; never evaluates incoming JSON. */
public final class Json {
    public static String encode(Object value) {
        if (value == null) return "null";
        if (value instanceof String s) {
            StringBuilder b = new StringBuilder("\"");
            for (char c : s.toCharArray()) {
                switch (c) {
                    case '"' -> b.append("\\\"");
                    case '\\' -> b.append("\\\\");
                    case '\n' -> b.append("\\n");
                    case '\r' -> b.append("\\r");
                    case '\t' -> b.append("\\t");
                    default -> { if (c < 32) b.append(String.format("\\u%04x", (int)c)); else b.append(c); }
                }
            }
            return b.append('"').toString();
        }
        if (value instanceof Number || value instanceof Boolean) return value.toString();
        if (value instanceof Map<?,?> map) {
            List<String> parts = new ArrayList<>();
            map.forEach((k,v) -> parts.add(encode(k.toString()) + ":" + encode(v)));
            return "{" + String.join(",", parts) + "}";
        }
        List<String> parts = new ArrayList<>();
        if (value instanceof Iterable<?> values) for (Object v : values) parts.add(encode(v));
        else if (value.getClass().isArray()) for (int i=0;i<Array.getLength(value);i++) parts.add(encode(Array.get(value,i)));
        else throw new IllegalArgumentException("Unsupported JSON type: " + value.getClass());
        return "[" + String.join(",", parts) + "]";
    }
}

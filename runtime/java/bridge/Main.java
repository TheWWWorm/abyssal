package bridge;
import java.nio.file.*;
import java.util.*;
/** Offline compatibility shim. No game loop, network listener or MIDlet launch. */
public final class Main {
 /** Digest of the build this engine is developed against: the Sony Ericsson
  * release of DEEP 1.0.8. Recorded for reference; acceptance is structural. */
 public static final String DEVELOPED_AGAINST="a247f8a872dda268ed8138086bd0de6d038d7faf7ef31469b0efe3eb54209d26";
 public static void main(String[] args)throws Exception {
  if(args.length!=2)throw new IllegalArgumentException("Expected JAR and cache directory");
  Path jar=Path.of(args[0]);
  if(Files.size(jar)>16_000_000)throw new IllegalArgumentException("JAR exceeds 16 MiB");
  Assets.prepare(jar,Path.of(args[1]));
  System.out.println(Json.encode(Map.of("cache",Assets.root.toString())));
 }
}

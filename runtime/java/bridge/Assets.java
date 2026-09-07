package bridge;

import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.jar.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.io.*;
import com.mascotcapsule.micro3d.v3.AssetExport;

public final class Assets {
    public static final Map<String,String> names = new HashMap<>();
    public static Path root;
    public static String jarHash;
    public static String hash(byte[] data) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)); }
        catch (NoSuchAlgorithmException e) { throw new AssertionError(e); }
    }
    public static String name(byte[] data) { return names.getOrDefault(hash(data), hash(data)); }
    /** Resource envelope specified by cv.a(String): swap N pairs at the two ends. */
    public static byte[] unwrap(byte[] input) {
        byte[] b = input.clone(); int n=b.length;
        int k=n<100 ? 10+n%10 : n<200 ? 50+n%20 : n<300 ? 80+n%20 : 100+n%50;
        if (n < k) throw new IllegalArgumentException("Resource envelope too short");
        for(int i=0;i<k;i++){ byte t=b[i];b[i]=b[n-1-i];b[n-1-i]=t; }
        return b;
    }
    public static Map<String,Object> prepare(Path jarPath, Path cache) throws Exception {
        jarHash=hash(Files.readAllBytes(jarPath)); root=cache.resolve(jarHash); Files.createDirectories(root);
        List<Object> entries=new ArrayList<>(); Map<String,String> manifest=new LinkedHashMap<>();
        try(JarFile jar = new JarFile(jarPath.toFile())) {
            jar.getManifest().getMainAttributes().forEach((k,v)->manifest.put(k.toString(),v.toString()));
            String[] midlet=manifest.getOrDefault("MIDlet-1","").split(",");
            if (midlet.length!=3 || !"DeepMIDlet".equals(midlet[2].trim())) throw new IOException("Unsupported JAR: this is not a DEEP MIDlet");
            String icon=manifest.get("MIDlet-1").split(",")[1].trim().replaceFirst("^/","");
            for (JarEntry e : Collections.list(jar.entries())) {
                if(e.isDirectory()) continue;
                String n=e.getName();
                if(n.startsWith("/") || n.contains("..") || n.contains("\\")) throw new IOException("Unsafe entry: "+n);
                if(e.getSize()>16_000_000) throw new IOException("Oversized entry");
                byte[] raw=jar.getInputStream(e).readAllBytes(); byte[] data=raw;
                boolean wrapped=n.endsWith(".mbac")||n.endsWith(".mtra")||n.endsWith(".bmp")||n.endsWith(".png");
                // The MIDlet icon is read by the phone launcher, outside cv.a.
                if(n.equals(icon))wrapped=false;
                if(wrapped)data=unwrap(raw);
                names.put(hash(data),n);
                entries.add(Map.of("path",n,"bytes",raw.length,"sha256",hash(raw),"decoded_sha256",hash(data),"envelope",wrapped ? "cv.a(String)" : "none"));
                if(!n.startsWith("data/"))continue;
                Path out=root.resolve(n); Files.createDirectories(out.getParent());
                Files.write(out,data);
                if(n.endsWith(".mbac")) Files.writeString(Path.of(out+".json"),Json.encode(AssetExport.model(data)));
                if(n.endsWith(".mtra")) Files.writeString(Path.of(out+".json"),Json.encode(AssetExport.animation(data)));
                if(n.endsWith(".bmp")) {
                    BufferedImage image=ImageIO.read(new ByteArrayInputStream(data));
                    if(image==null)throw new IOException("Unsupported texture "+n);
                    ImageIO.write(image,"png",Path.of(out+".png").toFile());
                    BufferedImage alpha=new BufferedImage(image.getWidth(),image.getHeight(),BufferedImage.TYPE_INT_ARGB);
                    for(int y=0;y<image.getHeight();y++)for(int x=0;x<image.getWidth();x++) {
                        int color=image.getRGB(x,y);
                        if(image.getColorModel() instanceof java.awt.image.IndexColorModel && image.getRaster().getSample(x,y,0)==0)color&=0xffffff;
                        alpha.setRGB(x,y,color);
                    }
                    ImageIO.write(alpha,"png",Path.of(out+".alpha.png").toFile());
                }
            }
        }
        Map<String,Object> report=Map.of("schema",1,"jar_sha256",jarHash,"manifest",manifest,"entries",entries,"cache",root.toString());
        Files.writeString(root.resolve("inventory.json"),Json.encode(report));
        return report;
    }
}

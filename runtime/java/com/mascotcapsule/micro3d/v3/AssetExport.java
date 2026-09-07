package com.mascotcapsule.micro3d.v3;

import java.util.*;

/** Exports decoded data only. Game rules and texture bindings remain in the supplied JAR. */
public final class AssetExport {
    public static Map<String,Object> model(byte[] bytes) throws Exception { return model(Loader.loadMbacData(bytes)); }
    static Map<String,Object> model(Model m) {
        List<Object> polys=new ArrayList<>();
        for(Model.Polygon[] group : new Model.Polygon[][]{m.polygonsT,m.polygonsC}) for(Model.Polygon p:group) {
            int[] attributes=new int[p.texCoords.length];
            for(int i=0;i<attributes.length;i++)attributes[i]=p.texCoords[i]&255;
            polys.add(Map.of("indices",p.indices,"attributes",attributes,"texture",p.face,"pattern",p.pattern,"blend",p.blendMode,"double_sided",p.doubleFace==1));
        }
        List<Object> bones=new ArrayList<>();
        for(int i=0;i<m.bones.capacity()/56;i++) {
            float[] mat=new float[12];for(int j=0;j<12;j++)mat[j]=m.bones.getFloat(i*56+8+j*4);
            bones.add(Map.of("vertices",m.bones.getInt(i*56),"parent",m.bones.getInt(i*56+4),"matrix",mat));
        }
        float[] vertices=new float[m.originalVertices.capacity()];for(int i=0;i<vertices.length;i++)vertices[i]=m.originalVertices.get(i);
        float[] normals=new float[m.originalNormals==null?0:m.originalNormals.capacity()];for(int i=0;i<normals.length;i++)normals[i]=m.originalNormals.get(i);
        return Map.of("vertices",vertices,"normals",normals,"polygons",polys,"bones",bones,"patterns",m.numPatterns);
    }
    public static List<Object> animation(byte[] bytes) throws Exception {
        List<Object> out=new ArrayList<>();
        for(Action a:Loader.loadMtraData(bytes)) {
            List<Object> frames=new ArrayList<>();
            for(int i=0;i<=a.keyframes;i++) {
                for(Action.Bone b:a.boneActions)b.setFrame(i<<16);
                frames.add(a.matrices.clone());
            }
            out.add(Map.of("last_frame",a.keyframes,"matrices",frames,"patterns",a.dynamic==null?Map.of():a.dynamic));
        }
        return out;
    }
}

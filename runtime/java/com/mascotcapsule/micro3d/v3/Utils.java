package com.mascotcapsule.micro3d.v3;

final class Utils {
    static final float TO_FLOAT=1f/4096f, TO_RADIANS=(float)(Math.PI*2/4096);
    static final float[] IDENTITY_AFFINE={1,0,0,0, 0,1,0,0, 0,0,1,0};
    static float[] multiply(float[] a,float[] b) {
        float[] out=new float[12];
        for(int r=0;r<3;r++)for(int c=0;c<4;c++) {
            float x=c==3 ? a[r*4+3] : 0;
            for(int k=0;k<3;k++)x+=a[r*4+k]*b[k*4+c];
            out[r*4+c]=x;
        }
        return out;
    }
}

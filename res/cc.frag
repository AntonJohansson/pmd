#version 330
in vec2 v_texcoords;
out vec4 frag_color;
uniform sampler2D tex;

// post-process pipeline
//
// . fog
// . bloom
// . color correction
//      . exposure
//      . white balancing
//      . contrast/brightness/filtering/saturation
//      . tone map
//          . clamp
//          . tumblin rushmeier
//          . aces
//          . ...
//
//      . gamma correct
//          color = color ^ (1/2.2)
//

vec3 wb(vec3 color, float temp, float tint) {
    float t1 = temp * 10.0 / 6.0;
    float t2 = tint * 10.0 / 6.0;

    float x = 0.31271 - t1 * (t1 < 0 ? 0.1 : 0.05);
    float stdIllY = 2.87*x - 3*x*x - 0.27509507;
    float y = stdIllY + 0.05*t2;

    vec3 w1 = vec3(0.949237, 1.03542, 1.08728);

    float Y = 1;
    float X = Y*x/y;
    float Z = Y*(1-x-y) / y;
    float L = 0.7328*X + 0.4296*Y - 0.1624*Z;
    float M = -0.7036*X + 1.6975*Y + 0.0061*Z;
    float S = 0.0030*X + 0.0136*Y + 0.9834*Z;

    vec3 w2 = vec3(L,M,S);

    vec3 balance = w1/w2;

    mat3 LIN_2_LMS_MAT = mat3(
        3.90405e-1, 5.49941e-1, 8.92632e-3,
        7.08416e-2, 9.63172e-1, 1.35775e-3,
        2.31082e-2, 1.28021e-1, 9.36245e-1
    );

    mat3 LMS_2_LIN_MAT = mat3(
        2.85847e+0, -1.62879e+0, -2.48910e-2,
        -2.10182e-1,  1.15820e+0,  3.24281e-4,
        -4.18120e-2, -1.18169e-1,  1.06867e+0
    );

    vec3 lms = LIN_2_LMS_MAT * color;
    lms *= balance;
    return LMS_2_LIN_MAT * lms;
}

float luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

// https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
vec3 aces(vec3 color) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((color*(a*color+b))/(color*(c*color+d)+e), 0.0, 1.0);
}

void main() {
    vec3 color = texture(tex, vec2(v_texcoords.x, 1.0-v_texcoords.y)).rgb;

    float exposure = 1.0;
    color *= exposure;

    color = wb(color, 0.5, 0.0);

    float brightness = 0.0;
    float contrast = 1.0;
    color = brightness*vec3(1,1,1) + contrast*(color - 0.5) + 0.5;

    vec3 filtering = vec3(1,1,1);
    color *= filtering;

    float saturation = 1.0;
    float l = luminance(color);
    color = mix(vec3(l,l,l), color, saturation);

    color = aces(color);

    float gamma = 2.2;
    color = vec3(pow(color.r, gamma), pow(color.g, gamma), pow(color.b, gamma));

    frag_color = vec4(color, 1.0);
}

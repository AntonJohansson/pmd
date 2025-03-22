#version 330

uniform sampler2D tex;
uniform vec2 off;
uniform vec2 scale;
uniform vec4 fg;
uniform vec4 bg;

in vec2 v_texcoords;
out vec4 frag_color;

void main() {
    float c = texture(tex, scale*v_texcoords + off).r;
    frag_color = vec4(0,0,0,0) + fg*c;
}

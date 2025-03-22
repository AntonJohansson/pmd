#version 330

layout(location=0) in vec2 position;
layout(location=1) in vec2 texcoords;

out vec2 v_texcoords;

uniform vec2 vs_off;
uniform vec2 vs_scale;

void main() {
    v_texcoords = texcoords;
    gl_Position = vec4(vs_scale*0.5*(position+vec2(1,1)) + vs_off, 0, 1);
}

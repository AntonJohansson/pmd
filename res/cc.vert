#version 330
layout(location=0) in vec2 position;
layout(location=1) in vec2 texcoords;
out vec2 v_texcoords;
void main() {
    v_texcoords = texcoords;
    gl_Position = vec4(position, 0, 1);
}

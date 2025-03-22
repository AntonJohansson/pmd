#version 330

layout(location=0) in vec3 position;

out vec3 vtexcoords;

uniform mat4 mvp;
uniform mat4 model;

void main() {
    vtexcoords = normalize(position);
    gl_Position = mvp*vec4(position, 1);
}

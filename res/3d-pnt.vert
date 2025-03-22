#version 330

layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;

uniform mat4 mvp;
uniform mat4 model;

out vec3 vnormal;
out vec3 vpos;
out vec2 vtexcoord;

void main() {
    gl_Position = mvp * vec4(position, 1);
    vpos = vec3(model * vec4(position, 1));
    vtexcoord = texcoord;
    vnormal = transpose(inverse(mat3(model)))*normal;
}

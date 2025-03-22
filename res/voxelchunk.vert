#version 330

layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
//layout(location=2) in vec2 texcoord;
layout(location=2) in vec4 instance;

uniform mat4 vp;
uniform mat4 rotations[6];
uniform vec3 chunk_pos;
uniform float voxel_size;

out vec3 vnormal;
out vec3 vpos;
//out vec2 vtexcoord;

void main() {
    int index = int(instance.w);
    mat4 model = rotations[index];
    vec3 translation = chunk_pos + (voxel_size/2.0)*vec3(1,1,1) + voxel_size*vec3(instance.xyz);
    gl_Position = vp * (model* vec4(position,1) + vec4(translation,0));
    vpos = mat3(model)*position + translation;
    //vtexcoord = texcoord;
    vnormal = transpose(inverse(mat3(model)))*normal;
}

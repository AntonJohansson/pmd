#version 400

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
out float color_rand;
//out vec2 vtexcoord;
flat out int vkind;

float rand_float(int x) {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 13;
    int max_int = (1 << 31) - 1;
    return float(x) / float(max_int);
}

void main() {
    int i    = int(bitfieldExtract(int(instance.x), 0, 8));
    int j    = int(bitfieldExtract(int(instance.x), 8, 8));
    int k    = int(bitfieldExtract(int(instance.y), 0, 8));
    int dir  = int(bitfieldExtract(int(instance.y), 8, 8));
    int kind = int(bitfieldExtract(int(instance.z), 0, 8));

    int index = int(dir);
    mat4 model = rotations[index];
    vec3 translation = chunk_pos + (voxel_size/2.0)*vec3(1,1,1) + voxel_size*vec3(i,j,k);
    gl_Position = vp * (model* vec4(position,1) + vec4(translation,0));
    vpos = mat3(model)*position + translation;
    color_rand = rand_float(gl_InstanceID);
    //vtexcoord = texcoord;
    vnormal = transpose(inverse(mat3(model)))*normal;
    vkind = kind;
}

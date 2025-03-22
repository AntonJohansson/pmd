#version 330

in vec3 vtexcoords;
out vec4 frag_color;

uniform samplerCube cube;
uniform vec4 color;

void main() {
    frag_color = color*texture(cube, vtexcoords);
}

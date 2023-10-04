#version 330
layout(location=0) in vec3 vertexPosition;
in mat4 matModel;
//layout(location=1) in vec2 vertexTexCoord;
//layout(location=3) in vec4 vertexColor;
uniform mat4 mvp;
//out vec4 color;
out float color_blend;
void main() {
    color_blend = vertexPosition.z;
    gl_Position = mvp*matModel*vec4(vertexPosition, 1);
}

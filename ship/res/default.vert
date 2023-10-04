#version 330
layout(location=0) in vec3 vertexPosition;
//layout(location=1) in vec2 vertexTexCoord;
layout(location=3) in vec4 vertexColor;
uniform mat4 mvp;
out vec4 color;
void main() {
  color = vertexColor;
  gl_Position = mvp*vec4(vertexPosition, 1);
}

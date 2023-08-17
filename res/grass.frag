#version 330
//in vec4 color;
out vec4 finalColor;
in float color_blend;
void main() {
    vec3 bottom_color = vec3(0.1,0.25,0.1);
    vec3 top_color = vec3(0.5,0.75,0.5);
    finalColor = vec4(mix(bottom_color, top_color, 1.75*color_blend), 1);
}

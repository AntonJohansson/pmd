#version 330

uniform vec4 color;
uniform vec3 light_pos;
uniform vec3 light_color;
uniform vec3 camera_pos;
uniform sampler2D tex;

in vec3 vnormal;
in vec3 vpos;
in vec2 vtexcoord;

out vec4 frag_color;

void main() {
    vec3 ambient = vec3(0.4,0.4,0.4);

    // diffuse
    vec3 n = normalize(vnormal);
    vec3 d = normalize(light_pos - vpos);
    float diff = max(dot(n, d), 0.0);
    vec3 diffuse = diff * light_color;

    // specular
    float strength = 0.5;
    vec3 e = normalize(camera_pos - vpos);
    vec3 r = reflect(-d, n);
    float spec = pow(max(dot(e, r), 0.0), 256);
    vec3 specular = strength * spec * light_color;

    vec3 texture_color = texture(tex, vtexcoord).rgb;
    frag_color = vec4((ambient + diffuse + specular) * texture_color * color.rgb, 1.0);
}

@header const alg = @import("lib/algebra")
@ctype mat4 alg.Mat4

@vs vs
layout(binding = 0) uniform vs_params { mat4 mvp; };
in vec4 position; in vec4 color0;
out vec4 color; out vec3 frag_pos;
void main() { gl_Position = mvp * position; frag_pos = position.xyz; color = color0; }
@end

@fs fs
in vec4 color; in vec3 frag_pos; out vec4 frag_color;
void main() {
    vec3 n = normalize(cross(dFdx(frag_pos), dFdy(frag_pos)));
    float diff = max(dot(n, normalize(vec3(0.5, 1.0, 0.3))), 0.0);
    frag_color = vec4(color.rgb * (0.4 + diff * 0.6), color.a);
}
@end

@program cube vs fs

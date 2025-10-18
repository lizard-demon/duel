@header const math = @import("../lib/math.zig")
@ctype mat4 math.Mat4

@vs vs
layout(binding = 0) uniform vs_params { mat4 mvp; };
in vec4 position; in vec4 color0;
out vec4 color; out vec3 frag_pos; out vec3 world_pos;
void main() {
    gl_Position = mvp * position;
    frag_pos = position.xyz;
    world_pos = position.xyz;
    color = color0;
}
@end

@fs fs
in vec4 color; in vec3 frag_pos; in vec3 world_pos;
out vec4 frag_color;

// Noise function for texture
float hash(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
                   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

// Fractal Brownian Motion for layered texture
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for(int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void main() {
    vec3 n = normalize(cross(dFdx(frag_pos), dFdy(frag_pos)));

    // Determine which face we're on based on normal
    vec3 abs_n = abs(n);
    float face_id = 0.0;
    vec3 tex_coord;

    if (abs_n.x > abs_n.y && abs_n.x > abs_n.z) {
        // X-facing wall
        face_id = sign(n.x);
        tex_coord = world_pos.yzx * 2.5 + vec3(face_id * 10.0, 0, 0);
    } else if (abs_n.y > abs_n.z) {
        // Y-facing wall
        face_id = sign(n.y) + 3.0;
        tex_coord = world_pos.xzy * 3.0 + vec3(0, face_id * 10.0, 0);
    } else {
        // Z-facing wall
        face_id = sign(n.z) + 6.0;
        tex_coord = world_pos.xyz * 2.2 + vec3(0, 0, face_id * 10.0);
    }

    // Multi-scale texture with face variation
    float base_texture = fbm(tex_coord);
    float detail = noise(tex_coord * 12.0) * 0.25;
    float grain = hash(world_pos * 80.0 + vec3(face_id)) * 0.12;

    // Combine textures with slight contrast boost
    float texture_value = base_texture * 0.7 + detail + grain;
    texture_value = pow(texture_value, 1.15); // increased contrast

    // Apply texture to color
    vec3 textured_color = color.rgb * (0.6 + texture_value * 0.8);

    // Enhanced lighting with multiple light sources
    vec3 light_dir1 = normalize(vec3(0.5, 1.0, 0.3));
    vec3 light_dir2 = normalize(vec3(-0.3, 0.2, 0.8));

    float diff1 = max(dot(n, light_dir1), 0.0);
    float diff2 = max(dot(n, light_dir2), 0.0) * 0.4; // secondary light

    // Rim lighting for edge definition
    vec3 view_dir = normalize(vec3(0, 0, 1));
    float rim = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0) * 0.25;

    // Ambient occlusion approximation
    float ao = 0.5 + 0.5 * noise(world_pos * 1.5);

    // Combine all lighting
    float lighting = 0.3 * ao + diff1 * 0.6 + diff2 + rim;
    vec3 final_color = textured_color * lighting;

    // Subtle color grading for warmth
    final_color = pow(final_color, vec3(0.95, 1.0, 1.05));

    frag_color = vec4(final_color, color.a);
}
@end

@program cube vs fs

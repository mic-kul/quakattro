#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float posX;
    float posY;
    float dirX;
    float dirY;
    float planeX;
    float planeY;
    float torch;
    vec4 apple0; vec4 apple1; vec4 apple2; vec4 apple3;
    vec4 apple4; vec4 apple5; vec4 apple6; vec4 apple7;
    vec4 grail;
    vec4 merchant0; vec4 merchant1; vec4 merchant2;
};

// >>> generated map -- tools/build-maze.py writes everything between these
// markers. Do not edit by hand; it will be overwritten.
const int MAPN = 21;
const int MAP[21] = int[21](
    0x1FFFFF, 0x100011, 0x1D5AF7, 0x105001,
    0x15F7FD, 0x151001, 0x17595D, 0x105115,
    0x13D715, 0x104441, 0x1E6CD7, 0x144451,
    0x15455F, 0x101041, 0x17DF5D, 0x145111,
    0x1515F5, 0x115405, 0x1F77D1, 0x100005,
    0x1FFFFF
);
// <<< generated map

int tileAt(int x, int y) {
    if (x < 0 || x >= MAPN || y < 0 || y >= MAPN)
        return 1;
    return (MAP[y] >> x) & 1;
}

// Cheap deterministic noise so the surfaces have some grain instead of reading
// as flat gouache.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Hyprland's dwindle, as masonry. Each split halves what is left and swaps
// axis, one side becoming a window and the other carrying on, so the pattern
// spirals into a corner exactly the way your windows do.
vec3 dwindle(vec2 uv, bool sideWall) {
    vec2 lo = vec2(0.0), hi = vec2(1.0);
    bool vertical = true;   // first split is a vertical line, as in a fresh workspace

    for (int i = 0; i < 11; ++i) {
        vec2 mid = (lo + hi) * 0.5;
        // The leaf alternates sides, which is what makes it spiral rather than
        // march off in one direction.
        bool leafLow = (i % 2) == 0;
        if (vertical) {
            bool inLow = uv.x < mid.x;
            if (inLow == leafLow) { if (inLow) hi.x = mid.x; else lo.x = mid.x; break; }
            if (inLow) hi.x = mid.x; else lo.x = mid.x;
        } else {
            bool inLow = uv.y < mid.y;
            if (inLow == leafLow) { if (inLow) hi.y = mid.y; else lo.y = mid.y; break; }
            if (inLow) hi.y = mid.y; else lo.y = mid.y;
        }
        vertical = !vertical;
    }

    vec2 size = max(hi - lo, vec2(1e-4));
    vec2 local = (uv - lo) / size;                    // 0..1 inside this window
    // Gaps are measured in wall space, so they stay even as the windows shrink.
    vec2 edge = min(uv - lo, hi - uv);
    float gap = min(edge.x, edge.y);

    // Eleven levels deep the last panes are a fraction of a percent wide, so a
    // fixed gap would eat them whole. Shrink it with the pane.
    float g = min(0.0085, 0.16 * min(size.x, size.y));
    float outer = smoothstep(g * 0.55, g, gap);       // window vs the gap
    float border = smoothstep(g, g * 1.7, gap);       // border ring vs body

    float tone = hash(lo * 37.0);
    vec3 body = mix(vec3(0.34, 0.28, 0.24), vec3(0.52, 0.44, 0.36), tone);
    body *= 0.86 + 0.28 * hash(uv * 64.0);            // keep the grain
    // A title bar, because every one of these is a window.
    body = mix(body * 1.18, body, smoothstep(0.0, 0.10, local.y));

    vec3 rim = mix(vec3(0.78, 0.62, 0.34), vec3(0.55, 0.66, 0.72), tone);
    vec3 gapColour = vec3(0.09, 0.08, 0.08);

    vec3 c = mix(rim, body, border);
    c = mix(gapColour, c, outer);
    return sideWall ? c * 0.72 : c;
}

float sdSeg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float sdBox(vec2 p, vec2 h) {
    vec2 d = abs(p) - h;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// kind 0 apple, 1 cloud, 2 grail. p is local, roughly -1..1, y down.
vec4 shape(int kind, vec2 p) {
    if (kind == 0) {
        // Two lobes and a dent, which is the whole trick to an apple.
        float body = min(length(p - vec2(-0.22, 0.12)) - 0.58,
                         length(p - vec2( 0.22, 0.12)) - 0.58);
        body = max(body, -(length(p - vec2(0.0, -0.80)) - 0.30));
        float a = smoothstep(0.05, -0.02, body);

        float stem = smoothstep(0.05, 0.0, sdSeg(p, vec2(0.02, -0.52), vec2(0.13, -0.95)) - 0.04);
        float leaf = smoothstep(0.04, 0.0,
                     length((p - vec2(0.26, -0.80)) * vec2(1.0, 2.2)) - 0.15);

        // Light from the upper left, so it reads as round.
        float lit = smoothstep(0.9, -0.6, length(p - vec2(-0.30, -0.28)));
        vec3 c = mix(vec3(0.52, 0.07, 0.07), vec3(0.92, 0.25, 0.18), lit);
        c += vec3(0.9, 0.7, 0.6) * smoothstep(0.28, 0.0, length(p - vec2(-0.30, -0.30))) * 0.7;
        c = mix(c, vec3(0.30, 0.18, 0.08), stem);
        c = mix(c, vec3(0.25, 0.55, 0.20), leaf);
        return vec4(c, clamp(a + stem + leaf, 0.0, 1.0));
    }

    if (kind == 1) {
        // The cloud they are selling. Puffy on top, flat underneath.
        float d = min(min(length(p - vec2(-0.46, 0.06)) - 0.40,
                          length(p - vec2( 0.02, -0.18)) - 0.54),
                          length(p - vec2( 0.48, 0.10)) - 0.38);
        d = min(d, sdBox(p - vec2(0.0, 0.18), vec2(0.50, 0.26)) - 0.06);
        d = max(d, p.y - 0.44);
        float a = smoothstep(0.05, -0.02, d);
        float top = smoothstep(0.5, -0.7, p.y);
        vec3 c = mix(vec3(0.24, 0.11, 0.36), vec3(0.62, 0.42, 0.85), top);
        // A cold rim so it looms out of the dark.
        c += vec3(0.35, 0.20, 0.55) * smoothstep(0.06, 0.0, abs(d)) * 1.2;
        return vec4(c, a);
    }

    // The grail, literally: a penguin, on a desk.
    // Desk: a top and two legs.
    float deskTop = sdBox(p - vec2(0.0, 0.60), vec2(0.66, 0.055));
    float legs = min(sdBox(p - vec2(-0.50, 0.82), vec2(0.055, 0.20)),
                     sdBox(p - vec2( 0.50, 0.82), vec2(0.055, 0.20)));
    float desk = min(deskTop, legs);

    // Body and head, one silhouette.
    float body = length((p - vec2(0.0, 0.14)) / vec2(0.32, 0.42)) - 1.0;
    body *= 0.32;
    float head = length(p - vec2(0.0, -0.26)) - 0.25;
    float bird = min(body, head);

    // Flippers.

    float d = min(desk, bird);
    float a = smoothstep(0.05, -0.02, d);

    // Colour it up, nearest feature last.
    vec3 c = mix(vec3(0.30, 0.20, 0.12), vec3(0.46, 0.31, 0.18),
            smoothstep(0.7, 0.4, p.y));                      // desk, lit from above
    c = mix(c, vec3(0.07, 0.07, 0.09), smoothstep(0.03, -0.02, bird));

    float belly = length((p - vec2(0.0, 0.20)) / vec2(0.20, 0.30)) - 1.0;
    float face = length((p - vec2(0.0, -0.20)) / vec2(0.17, 0.16)) - 1.0;
    c = mix(c, vec3(0.95, 0.94, 0.90), smoothstep(0.06, -0.02, min(belly, face) * 0.2));

    float feet = min(length((p - vec2(-0.16, 0.54)) / vec2(0.15, 0.07)) - 1.0,
                     length((p - vec2( 0.16, 0.54)) / vec2(0.15, 0.07)) - 1.0);
    float beak = length((p - vec2(0.0, -0.16)) / vec2(0.13, 0.07)) - 1.0;
    c = mix(c, vec3(0.98, 0.62, 0.10), smoothstep(0.10, -0.05, min(feet, beak) * 0.2));

    float eyes = min(length(p - vec2(-0.085, -0.31)) - 0.032,
                     length(p - vec2( 0.085, -0.31)) - 0.032);
    c = mix(c, vec3(0.05, 0.05, 0.06), smoothstep(0.02, -0.01, eyes));

    // It is the goal of the game; let it glow a little.
    c += vec3(0.9, 0.8, 0.5) * smoothstep(0.05, 0.0, abs(desk)) * 0.35;
    return vec4(c, a);
}

// A billboard. QML has already done the camera transform -- every step of it
// derived from uniforms alone, so computing it per pixel was five million
// answers to the same question. What arrives is where it lands on screen:
// xy centre, z half-size, w depth, with w <= 0 meaning gone or behind us.
void sprite(inout vec3 colour, vec4 s, vec2 uv, int kind, float wall) {
    if (s.w <= 0.0 || s.w >= wall)
        return;

    vec2 p = (uv - s.xy) / s.z;
    if (abs(p.x) > 1.2 || abs(p.y) > 1.2)
        return;

    vec4 shaded = shape(kind, p);
    if (shaded.a <= 0.001)
        return;

    float glow = 1.0 / (1.0 + s.w * s.w * 0.10);
    colour = mix(colour, shaded.rgb * clamp(glow, 0.25, 1.6), shaded.a);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 pos = vec2(posX, posY);
    vec2 dir = vec2(dirX, dirY);
    vec2 plane = vec2(planeX, planeY);

    float camX = 2.0 * uv.x - 1.0;
    vec2 ray = dir + plane * camX;
    if (abs(ray.x) < 1e-6) ray.x = 1e-6;
    if (abs(ray.y) < 1e-6) ray.y = 1e-6;

    ivec2 cell = ivec2(floor(pos));
    vec2 deltaDist = abs(1.0 / ray);
    ivec2 step;
    vec2 sideDist;

    if (ray.x < 0.0) { step.x = -1; sideDist.x = (pos.x - float(cell.x)) * deltaDist.x; }
    else             { step.x =  1; sideDist.x = (float(cell.x) + 1.0 - pos.x) * deltaDist.x; }
    if (ray.y < 0.0) { step.y = -1; sideDist.y = (pos.y - float(cell.y)) * deltaDist.y; }
    else             { step.y =  1; sideDist.y = (float(cell.y) + 1.0 - pos.y) * deltaDist.y; }

    bool sideWall = false;
    for (int i = 0; i < 64; ++i) {
        if (sideDist.x < sideDist.y) { sideDist.x += deltaDist.x; cell.x += step.x; sideWall = false; }
        else                         { sideDist.y += deltaDist.y; cell.y += step.y; sideWall = true; }
        if (tileAt(cell.x, cell.y) > 0)
            break;
    }

    float wallDist = sideWall ? (sideDist.y - deltaDist.y) : (sideDist.x - deltaDist.x);
    wallDist = max(wallDist, 0.02);

    float lineHeight = 1.0 / wallDist;
    float top = 0.5 - lineHeight * 0.5;
    float bottom = 0.5 + lineHeight * 0.5;

    vec3 colour;
    float depth;

    if (uv.y > top && uv.y < bottom) {
        float wallX = sideWall ? pos.x + wallDist * ray.x : pos.y + wallDist * ray.y;
        wallX = fract(wallX);
        float wallY = (uv.y - top) / max(bottom - top, 1e-5);
        colour = dwindle(vec2(wallX, wallY), sideWall);
        depth = wallDist;
    } else {
        // Floor and ceiling cast from the same row distance, mirrored.
        bool floorHalf = uv.y > 0.5;
        float p = abs(uv.y - 0.5);
        float rowDist = 0.5 / max(p, 1e-5);
        vec2 world = pos + rowDist * ray;
        vec2 tile = fract(world);
        float checker = mod(floor(world.x) + floor(world.y), 2.0);
        vec3 floorC = mix(vec3(0.20, 0.19, 0.18), vec3(0.28, 0.26, 0.23), checker);
        floorC *= 0.85 + 0.3 * hash(floor(world * 8.0));
        vec3 ceilC = vec3(0.10, 0.11, 0.14) * (0.8 + 0.4 * hash(floor(world * 4.0)));
        colour = floorHalf ? floorC : ceilC;
        depth = rowDist;
    }

    // Torchlight falloff. Quake's whole look is darkness with a lamp in it.
    float light = torch / (1.0 + depth * depth * 0.28);
    colour *= clamp(light, 0.05, 1.4);
    colour = mix(colour, vec3(0.03, 0.03, 0.05), clamp(depth * 0.055, 0.0, 0.85));

    // Sprites go over the lit world, in index order, each one only where it is
    // closer than the wall behind it.
    sprite(colour, apple0, uv, 0, depth);
    sprite(colour, apple1, uv, 0, depth);
    sprite(colour, apple2, uv, 0, depth);
    sprite(colour, apple3, uv, 0, depth);
    sprite(colour, apple4, uv, 0, depth);
    sprite(colour, apple5, uv, 0, depth);
    sprite(colour, apple6, uv, 0, depth);
    sprite(colour, apple7, uv, 0, depth);
    sprite(colour, grail, uv, 2, depth);
    sprite(colour, merchant0, uv, 1, depth);
    sprite(colour, merchant1, uv, 1, depth);
    sprite(colour, merchant2, uv, 1, depth);

    fragColor = vec4(pow(colour, vec3(0.85)), 1.0) * qt_Opacity;
}

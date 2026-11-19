#version 300 es
precision highp float;

uniform int u_lightStickCount;
uniform float u_time;
uniform vec2 u_resolution;
uniform int u_maxBounces;
uniform float u_ambientStrength;
uniform vec2 u_cameraOrbit;
uniform vec3 u_spotlightColor;

out vec4 fragColor;

const float LIGHT_POWER = 2.5;
const float LIGHT_STICK_POWER = 0.005;
const float FLOOR_Y = -2.0;
const float CHECKER_SIZE = 1.0;

// ---- glass parameters ----
const float GLASS_IOR = 1.5;
const float GLASS_F0 = 0.04; // glass reflectance
const vec3  GLASS_ABSORB = vec3(0.25, 0.08, 0.04); // glass absorbtion
const float GLASS_SHADOW_TRANSMIT = 0.55; // amount of light that passes through
const float GLASS_SHININESS = 128.0;

const int NUM_LIGHTS = 2;
const int NUM_CUBES = 11;
const int NUM_TORUSES = 2;
const int MAX_LIGHT_STICKS = 128;

struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Sphere {
    vec3 center;
    float radius;
    vec3 color;
    float reflectivity;
    float emission;
};

struct Cube {
    float halfSize;
    vec3 color;
    float reflectivity;
    mat4 transform;
};

struct Torus {
    float majorRadius;
    float minorRadius;
    vec3 color;
    float reflectivity;
    mat4 transform;
};

struct HitData {
    bool hit;
    float t;
    vec3 point;
    vec3 normal;
    vec3 color;
    float reflectivity;
    bool isLight;
    bool isGlass;
    float emission;
};

Sphere lights[NUM_LIGHTS];
Sphere lightSticks[MAX_LIGHT_STICKS];
Cube cubes[NUM_CUBES];
Torus toruses[NUM_TORUSES];
Sphere sphere;                  // the glass sphere

// Inverse transforms are computed once per fragment in a single loop
// (instead of calling inverse() inside every intersection function).
mat4 cubeInv[NUM_CUBES];
mat4 torusInv[NUM_TORUSES];

// ---------------------------------------------------------------------------
// Matrix helpers
// ---------------------------------------------------------------------------
mat4 translation(vec3 t) {
    mat4 m = mat4(1.0);
    m[3] = vec4(t, 1.0);
    return m;
}

mat4 scaling(vec3 s) {
    mat4 m = mat4(1.0);
    m[0][0] = s.x;
    m[1][1] = s.y;
    m[2][2] = s.z;
    return m;
}

mat4 rotateX(float angle) {
    float c = cos(angle), s = sin(angle);
    return mat4(
        1.0, 0.0, 0.0, 0.0,
        0.0,   c,   s, 0.0,
        0.0,  -s,   c, 0.0,
        0.0, 0.0, 0.0, 1.0
    );
}

mat4 rotateY(float angle) {
    float c = cos(angle), s = sin(angle);
    return mat4(
          c, 0.0,  -s, 0.0,
        0.0, 1.0, 0.0, 0.0,
          s, 0.0,   c, 0.0,
        0.0, 0.0, 0.0, 1.0
    );
}

mat4 rotateZ(float angle) {
    float c = cos(angle), s = sin(angle);
    return mat4(
          c,   s, 0.0, 0.0,
         -s,   c, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    );
}

// PRNG
float rand(float n) {
    return fract(sin(n * 12.9898) * 43758.5453123);
}

void initScene(float time) {
    // stage cube 1
    cubes[0] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(0.0, -1.8, -13.0)) * scaling(vec3(3.0, 0.4, 6.0))
    );

    // stage cube 2
    cubes[1] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(0.0, -1.8, -7.0)) * scaling(vec3(6.0, 0.4, 6.0))
    );

    // right seating
    cubes[2] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(7.5, -1.5, -9.0)) * rotateZ(0.9) * rotateY(3.14) * scaling(vec3(3.0, 1.0, 10.0))
    );

    // left angled seating
    cubes[3] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(-5.0, -1.5, -1.0)) * rotateY(0.785) * rotateZ(-0.9) * scaling(vec3(3.0, 1.0, 6.0))
    );

    // left seating
    cubes[4] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(-7.5, -1.5, -9.0)) * rotateZ(-0.9) * scaling(vec3(3.0, 1.0, 10.0))
    );

    // right angled seating
    cubes[5] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(5.0, -1.5, -1.0)) * rotateY(2.355) * rotateZ(-0.9) * scaling(vec3(3.0, 1.0, 6.0))
    );

    // back seating
    cubes[6] = Cube(
        0.5, 
        vec3(0.5), 
        0.01,
        translation(vec3(0.0, -1.5, 1.5)) * rotateY(1.57) * rotateZ(-0.9) * scaling(vec3(3.0, 0.5, 4.0))
    );

    vec4 wallMaterial = vec4(0.0, 0.0, 0.01, 0);

    // walls
    cubes[7]  = Cube(
        0.5, 
        wallMaterial.xyz, 
        wallMaterial.w, 
        translation(vec3(0.0, 0.0, -18.0)) * scaling(vec3(1000.0, 100.0, 0.5))
    );

    cubes[8]  = Cube(
        0.5, 
        wallMaterial.xyz, 
        wallMaterial.w, 
        translation(vec3(0.0, 0.0, 10.0))  * scaling(vec3(1000.0, 100.0, 0.5))
    );

    cubes[9]  = Cube(
        0.5, 
        wallMaterial.xyz, 
        wallMaterial.w, 
        translation(vec3(10.0, 0.0, 0.0))  * scaling(vec3(0.5, 100.0, 1000.0))
    );

    cubes[10] = Cube(
        0.5, 
        wallMaterial.xyz, 
        wallMaterial.w, 
        translation(vec3(-10.0, 0.0, 0.0)) * scaling(vec3(0.5, 100.0, 1000.0))
    );

    // glass sphere on stage
    float a = time * 0.5;
    sphere = Sphere(
        vec3(cos(a) * 2.5, sin(a * 1.3) * 0.8, -6.0 + sin(a) * 0.5),
        1.0,
        vec3(1.0),
        0.0,
        0.0
    );

    // spotlights (a sphere light inside of a torus)
    toruses[0] = Torus(
        0.4, 
        0.1, 
        vec3(1.0), 
        0.0,
        translation(vec3(-2.2, 3.5, -3.0)) * rotateY(1.57) * rotateZ(0.6) * rotateX(1.25) * scaling(vec3(1.0, 1.0, 7.5))
    );

    lights[0] = Sphere(
        vec3(-2.2, 3.6, -3.0), 
        0.3, 
        u_spotlightColor, 
        0.0, 
        1.0
    );

    toruses[1] = Torus(
        0.4, 
        0.1, 
        vec3(1.0), 
        0.0,
        translation(vec3(2.2, 3.5, -3.0)) * rotateY(1.57) * rotateZ(0.6) * rotateX(-1.25) * scaling(vec3(1.0, 1.0, 7.5))
    );

    lights[1] = Sphere(
        vec3(2.2, 3.6, -3.0), 
        0.3,
        u_spotlightColor, 
        0.0, 
        1.0
    );

    // precompute inverse transforms once
    for (int i = 0; i < NUM_CUBES; i++) {
        cubeInv[i] = inverse(cubes[i].transform);
    }
    for (int i = 0; i < NUM_TORUSES; i++) {
        torusInv[i] = inverse(toruses[i].transform);
    }

    // distribute light sticks accorss all the cubes
    for (int i = 0; i < u_lightStickCount; i++) {

        int section = int(mod(float(i), 5.0));
        int cubeIndex = 2 + section;

        // find lightstick position
        float localX = (rand(float(i) + 1.1) - 0.5) * 0.8 - 0.2;
        float localY = 0.75;
        float localZ = (rand(float(i) + 2.2) - 0.5) * 0.8;
        vec4 worldPos = cubes[cubeIndex].transform * vec4(localX, localY, localZ, 1.0);

        // bop up and down
        vec3 finalPos = worldPos.xyz + vec3(0.0, sin(time * 7.0 + rand(float(i) + 3.3) * 6.28) * 0.1, 0.0);

        // get a random colour between pink and cyan
        vec3 stickColor = mix(vec3(0.1, 0.8, 1.0), vec3(1.0, 0.2, 0.8), rand(float(i) + 4.4));

        // create the lightstick
        lightSticks[i] = Sphere(finalPos, 0.12, stickColor, 1.0, 0.5);
    }
}

bool intersectSphere(Ray ray, Sphere s, out float t) {
    vec3 oc = ray.origin - s.center;
    float b = dot(oc, ray.direction);
    float d = b * b - dot(oc, oc) + s.radius * s.radius;
    if (d < 0.0) return false;

    t = -b - sqrt(d);
    if (t < 0.001) t = -b + sqrt(d);  // ray starts inside
    return t > 0.001;
}

// rewritten intersectCube to allow a transformation
bool intersectCube(Ray ray, Cube c, mat4 inv, out float t, out vec3 normal) {
    vec3 localOrigin = (inv * vec4(ray.origin, 1.0)).xyz;
    vec3 localDir = (inv * vec4(ray.direction, 0.0)).xyz;

    float dirLen = length(localDir);
    localDir /= dirLen;

    vec3 invD = 1.0 / localDir;
    vec3 t0s = (-c.halfSize - localOrigin) * invD;
    vec3 t1s = ( c.halfSize - localOrigin) * invD;
    vec3 tmin = min(t0s, t1s);
    vec3 tmax = max(t0s, t1s);
    float t0 = max(max(tmin.x, tmin.y), tmin.z);
    float t1 = min(min(tmax.x, tmax.y), tmax.z);
    if (t1 < 0.0 || t0 > t1) {
        return false;
    }

    float localT = t0 > 0.001 ? t0 : t1;
    if (localT < 0.001) {
        return false;
    }

    t = localT / dirLen;
    if (t < 0.001) {
        return false;
    }

    vec3 localHit = localOrigin + localDir * localT;
    vec3 a = abs(localHit);
    vec3 localNormal;
    if (a.x > a.y && a.x > a.z) {
        localNormal = vec3(sign(localHit.x), 0.0, 0.0);
    } else if (a.y > a.z) {
        localNormal = vec3(0.0, sign(localHit.y), 0.0);
    } else {
        localNormal = vec3(0.0, 0.0, sign(localHit.z));
    }

    // correct normals
    normal = normalize(mat3(transpose(inv)) * localNormal);
    return true;
}

// ray march for torus (https://youtu.be/Ff0jJyyiVyw?si=U5yK5ft5z8DGlzXn)
bool intersectTorus(Ray ray, Torus tor, mat4 inv, out float t, out vec3 normal) {
    vec3 localOrigin = (inv * vec4(ray.origin, 1.0)).xyz;
    vec3 localDir = (inv * vec4(ray.direction, 0.0)).xyz;
    float dirLen = length(localDir);
    localDir /= dirLen;

    // check bounding sphere first (much faster)
    float outerRadius = tor.majorRadius + tor.minorRadius;
    float b = dot(localOrigin, localDir);
    float c = dot(localOrigin, localOrigin) - outerRadius * outerRadius;
    float disc = b * b - c;
    if (disc < 0.0) {
        return false;
    }
    float tNear = max(-b - sqrt(disc), 0.0);
    float tFar = -b + sqrt(disc);

    // step through
    float currentT = tNear;
    bool hit = false;
    for (int step = 0; step < 8; step++) {
        vec3 p = localOrigin + localDir * currentT;
        vec2 q = vec2(length(p.xy) - tor.majorRadius, p.z);
        float dist = length(q) - tor.minorRadius;
        if (dist < 0.001) { 
            hit = true;
            break;
        }
        currentT += dist;
        if (currentT > tFar) {
            break;
        }
    }
    if (!hit) {
        return false;
    }

    t = currentT / dirLen;
    if (t < 0.001) {
        return false;
    }

    vec3 localHit = localOrigin + localDir * currentT;
    float s = length(localHit.xy);
    float k = 1.0 - tor.majorRadius / s;
    vec3 localNormal = normalize(vec3(localHit.xy * k, localHit.z));

    normal = normalize(mat3(transpose(inv)) * localNormal);
    return true;
}

bool intersectFloor(Ray ray, out float t) {
    if (abs(ray.direction.y) < 0.0001) return false;
    t = (FLOOR_Y - ray.origin.y) / ray.direction.y;
    return t > 0.001;
}

HitData traceScene(Ray ray) {
    HitData hit;
    hit.hit = false;
    hit.t = 1e10;
    float t;
    vec3 n;

    // check if hit is light
    for (int i = 0; i < NUM_LIGHTS; i++) {
        if (intersectSphere(ray, lights[i], t) && t < hit.t) {
            hit = HitData(true, t, ray.origin + ray.direction * t, vec3(0.0), lights[i].color, 0.0, true, false, lights[i].emission);
        }
    }

    // check if hit is a lightstick
    for (int i = 0; i < MAX_LIGHT_STICKS; i++) {
        if (i >= u_lightStickCount) break;
        if (intersectSphere(ray, lightSticks[i], t) && t < hit.t) {
            hit = HitData(true, t, ray.origin + ray.direction * t, vec3(0.0), lightSticks[i].color, 0.0, true, false, lightSticks[i].emission);
        }
    }

    if (intersectFloor(ray, t) && t < hit.t) {
        vec3 p = ray.origin + ray.direction * t;
        vec2 cell = floor(p.xz / CHECKER_SIZE);
        vec3 color = mod(cell.x + cell.y, 2.0) < 1.0 ? vec3(1.0) : vec3(0.05);
        hit = HitData(true, t, p, vec3(0.0, 1.0, 0.0), color, 0.15, false, false, 0.0);
    }

    // check if hit is one of the cubes
    for (int i = 0; i < NUM_CUBES; i++) {
        if (intersectCube(ray, cubes[i], cubeInv[i], t, n) && t < hit.t) {
            hit = HitData(true, t, ray.origin + ray.direction * t, n, cubes[i].color, cubes[i].reflectivity, false, false, 0.0);
        }
    }

    // check if the hit is one of the toruses
    for (int i = 0; i < NUM_TORUSES; i++) {
        if (intersectTorus(ray, toruses[i], torusInv[i], t, n) && t < hit.t) {
            hit = HitData(true, t, ray.origin + ray.direction * t, n, toruses[i].color, toruses[i].reflectivity, false, false, 0.0);
        }
    }

    // check if it was the glass sphere
    if (intersectSphere(ray, sphere, t) && t < hit.t) {
        vec3 p = ray.origin + ray.direction * t;
        hit = HitData(true, t, p, (p - sphere.center) / sphere.radius, sphere.color, 0.0, false, true, 0.0);
    }

    return hit;
}

// how much light is left after traveling through an object (so that glass casts a partial shadow rather than a full one)
float shadowVisibility(Ray ray, float maxDist) {
    float t;
    vec3 n;

    if (intersectFloor(ray, t) && t < maxDist) return 0.0;

    for (int i = 0; i < NUM_CUBES; i++) {
        if (intersectCube(ray, cubes[i], cubeInv[i], t, n) && t < maxDist) return 0.0;
    }
    for (int i = 0; i < NUM_TORUSES; i++) {
        if (intersectTorus(ray, toruses[i], torusInv[i], t, n) && t < maxDist) return 0.0;
    }

    if (intersectSphere(ray, sphere, t) && t < maxDist) return GLASS_SHADOW_TRANSMIT;
    return 1.0;
}

vec3 trace(Ray ray) {
    vec3 color = vec3(0.0);
    vec3 attenuation = vec3(1.0);

    bool inGlass = false;
    bool hasPending = false;
    Ray pendingRay = ray;
    vec3 pendingAtten = vec3(0.0);
    bool pendingInGlass = false;

    //use loop to simulate the recursive process as GLSL doesn't support recursions
    for (int bounce = 0; bounce < u_maxBounces; bounce++) {
        if (bounce >= u_maxBounces) break;

        HitData hit = traceScene(ray);
        bool pathEnds = false;

        if (hit.hit && inGlass) {
            // exponential attenuation
            attenuation *= exp(-GLASS_ABSORB * hit.t);
        }

        // draw sky; i don't think it should be visible though?
        if (!hit.hit) {
            // sky gradient
            float t = 0.5 * (ray.direction.y + 1.0);
            color += attenuation * mix(vec3(0.09, 0.12, 0.18), vec3(0.18, 0.21, 0.27), t);
            pathEnds = true;
        } else if (hit.isLight) {
            color += attenuation * hit.color * hit.emission * LIGHT_POWER;
            pathEnds = true;
        } else if (hit.isGlass) {
            // glass logic
            vec3 P = hit.point;
            vec3 n = hit.normal;
            bool entering = dot(ray.direction, n) < 0.0;
            if (!entering) n = -n; // align n with the ray

            float eta = entering ? 1.0 / GLASS_IOR : GLASS_IOR;
            vec3 refracted = refract(ray.direction, n, eta);
            bool tir = dot(refracted, refracted) < 0.5;
            vec3 reflected = reflect(ray.direction, n);

            // Schlick Fresnel
            float F = 1.0;
            if (!tir) {
                float cosT = entering ? dot(-ray.direction, n) : dot(refracted, -n);
                F = GLASS_F0 + (1.0 - GLASS_F0) * pow(1.0 - cosT, 5.0);
            }

            // Phong for specular
            if (entering) {
                vec3 V = -ray.direction;
                vec3 spec = vec3(0.0);
                for (int i = 0; i < NUM_LIGHTS; i++) {
                    vec3 toLight = lights[i].center - P;
                    float d = length(toLight);
                    vec3 L = toLight / d;
                    float falloff = 1.0 / (1.0 + 0.1 * d * d);
                    float s = pow(max(dot(reflect(-L, n), V), 0.0), GLASS_SHININESS);
                    spec += lights[i].color * (s * lights[i].emission * LIGHT_POWER * falloff * 0.8);
                }
                color += attenuation * spec;
            }

            if (tir) {
                // all energy stays inside
                ray = Ray(P + n * 0.001, reflected);
            } else if (!hasPending) {
                // make the reflected ray queued
                hasPending = true;
                pendingRay = Ray(P + n * 0.001, reflected);
                pendingAtten = attenuation * F;
                pendingInGlass = !entering;

                attenuation *= (1.0 - F);
                ray = Ray(P - n * 0.001, refracted);
                inGlass = entering;
            } else {
                // approximate reflection since we are already waiting on a ray
                ray = Ray(P - n * 0.001, refracted);
                inGlass = entering;
            }

        } else {
            // just use phong for diffuse and specular
            vec3 N = hit.normal;
            vec3 V = -ray.direction;
            float shininess = 32.0;
            float ks = 0.3;

            vec3 diffuseSum = vec3(0.0);
            vec3 specSum = vec3(0.0);

            for (int i = 0; i < NUM_LIGHTS; i++) {
                vec3 toLight = lights[i].center - hit.point;
                float lightDist = length(toLight);
                vec3 L = toLight / lightDist;

                float vis = shadowVisibility(Ray(hit.point + N * 0.001, L), lightDist);
                float diff = max(dot(N, L), 0.0);
                float falloff = 1.0 / (1.0 + 0.1 * lightDist * lightDist);
                vec3 lc = lights[i].color * (lights[i].emission * LIGHT_POWER * falloff * vis);

                diffuseSum += lc * diff;
                if (diff > 0.0) {
                    float s = pow(max(dot(reflect(-L, N), V), 0.0), shininess);
                    specSum += lc * (ks * s);
                }
            }

            // diffuse only for lightsticks (there are so many; its cheaper to ignore shadows)
            for (int i = 0; i < MAX_LIGHT_STICKS; i++) {
                if (i >= u_lightStickCount) break;
                vec3 toLight = lightSticks[i].center - hit.point;
                float lightDist = length(toLight);
                if (lightDist > 8.0) continue;
                vec3 L = toLight / lightDist;
                float diff = max(dot(N, L), 0.0);
                float falloff = 1.0 / (1.0 + 0.1 * lightDist * lightDist);
                diffuseSum += lightSticks[i].color * (LIGHT_STICK_POWER * diff * falloff);
            }

            vec3 shading = hit.color * (diffuseSum + u_ambientStrength) + specSum;
            color += attenuation * shading * (1.0 - hit.reflectivity);

            if (hit.reflectivity == 0.0) {
                pathEnds = true;
            } else {
                attenuation *= hit.reflectivity;
                ray = Ray(hit.point + N * 0.001, reflect(ray.direction, N));
                inGlass = false;
            }
        }

        // basically no energy left sowe can just end it early to save computation
        if (max(attenuation.r, max(attenuation.g, attenuation.b)) < 0.003) pathEnds = true;

        if (pathEnds) {
            if (hasPending) {
                ray = pendingRay;
                attenuation = pendingAtten;
                inGlass = pendingInGlass;
                hasPending = false;
            } else {
                break;
            }
        }
    }

    return color;
}

void main() {
    initScene(u_time);

    float cp = cos(u_cameraOrbit.x), sp = sin(u_cameraOrbit.x);
    float cy = cos(u_cameraOrbit.y), sy = sin(u_cameraOrbit.y);
    mat3 rotX = mat3(1.0, 0.0, 0.0,  0.0, cp, -sp,  0.0, sp, cp);
    mat3 rotY = mat3(cy, 0.0, -sy,  0.0, 1.0, 0.0,  sy, 0.0, cy);
    mat3 camera = rotY * rotX;

    vec3 target = vec3(2.0, 1.5, 1.0);
    vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
    Ray ray = Ray(target + camera * vec3(0.0, 0.0, 7.0), camera * normalize(vec3(uv, -1.5)));

    fragColor = vec4(pow(trace(ray), vec3(1.0 / 2.2)), 1.0);
}
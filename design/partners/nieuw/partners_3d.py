"""Sixteen partners as soft 3D toy figures in six forms each, built from code in Blender and rendered with Cycles.

Run: blender -b --factory-startup -P partners_3d.py -- <output folder> [samples] [names, e.g. hommel,uil] [forms, e.g. 1,6]
Writes <name>-<form>.png (transparent, with the contact shadow in the alpha) and partners.blend.
Every figure stands on z = 0 and faces -Y. One camera for all, so the growth from form 1 to 6 shows.

Growth over the six forms:
- the whole figure grows (K) and gets a little taller;
- young forms have bigger eyes (EYE); from form 4 a confident brow line appears;
- each animal's own feature grows with F (0 at form 1, 1 at form 6), and some get new parts at later forms.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = args[0] if args else os.path.dirname(os.path.abspath(__file__))
SAMPLES = int(args[1]) if len(args) > 1 else 64
ALL = ['hommel', 'mol', 'kikker', 'uil', 'egel', 'slak', 'axolotl', 'zeehond',
       'pinguin', 'schildpad', 'konijn', 'wasbeer', 'lieveheersbeestje', 'octopus', 'eekhoorn', 'lammetje']
ONLY = args[2].split(',') if len(args) > 2 and args[2] != 'all' else ALL
FORMS = [int(x) for x in args[3].split(',')] if len(args) > 3 else [1, 2, 3, 4, 5, 6]

K = [0.55, 0.63, 0.71, 0.79, 0.87, 0.95]
EYES = [1.22, 1.14, 1.06, 1.0, 0.95, 0.9]

COLORS = {
    # shared
    'eye': '#241915', 'white': '#FFFFFF', 'blush': '#F48C86', 'mouth': '#4A2A22', 'nose': '#2E2422',
    'sclera': '#FFFDF8',
    # hommel
    'bee': '#FFC93C', 'beeBand': '#4A3226', 'wing': '#EAF3FF',
    # mol
    'mole': '#7A665C', 'moleBelly': '#B39C8C', 'molePink': '#F2959F', 'claw': '#FFF4E4',
    # kikker
    'frog': '#74BE57', 'frogSpot': '#5A9E44', 'frogBelly': '#F2EDC4',
    # uil
    'owl': '#56789E', 'owlWing': '#3F5C7E', 'owlFace': '#F4E8D2', 'owlBelly': '#DDE5EE',
    'amber': '#F4A93A', 'beak': '#EC8F3C',
    # egel
    'hedgehog': '#EBC79A', 'hedgeSnout': '#E0AB7B', 'spike': '#8C5A3A', 'paw': '#E9A08F',
    # slak
    'snail': '#9FD8C2', 'shell': '#F2836B', 'shellLine': '#C2563F',
    # axolotl
    'axo': '#F6A6B9', 'gill': '#E35D82', 'axoBelly': '#FCD6DF',
    # zeehond
    'seal': '#91A5B9', 'sealMuzzle': '#EEF2F5', 'sealSpot': '#6F8397',
    # pinguin
    'peng': '#34456A', 'pengWhite': '#F7F5F0', 'crest': '#F6C445',
    # schildpad
    'turtle': '#B9D27F', 'tShell': '#2F8C7E', 'tPlate': '#5DB8A5', 'tRim': '#257265',
    # konijn
    'bunny': '#BBA392', 'bunnyBelly': '#F4EBE2', 'bunnyEar': '#EE8E9E', 'tail': '#FFFFFF',
    # wasbeer
    'racc': '#8F929C', 'raccMask': '#45434C', 'raccLight': '#EEEBE6', 'raccInner': '#5C5A66',
    # lieveheersbeestje
    'bug': '#E2483D', 'bugDark': '#2E2629',
    # octopus
    'octo': '#B48AD8', 'octoSpot': '#9A6CC4', 'octoLight': '#E3D0F2',
    # eekhoorn
    'squirrel': '#E58A3E', 'squirrelTail': '#D2742E', 'tailTip': '#F6DFC0', 'cream': '#F6DFC0', 'acorn': '#B07A45', 'acornCap': '#6E4B2E',
    # lammetje
    'wool': '#E4D4B9', 'lambFace': '#D5AE8E', 'hoof': '#5A4842', 'horn': '#A87E55',
}

# Set per form before an animal is built.
FORM, F, EYE, BROW = 1, 0.0, 1.0, False


def grow(a, b):
    """From a at form 1 to b at form 6."""
    return a + (b - a) * F


def srgb(hexcode):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(hexcode[i:i + 2], 16)) for i in (1, 3, 5)) + (1.0,)


MATS = {}


def mat(key, rough=0.55, sheen=0.0, coat=0.0, sss=0.12, alpha=1.0, emit=False):
    """A soft vinyl-toy surface. emit=True gives a flat light colour (eye highlights)."""
    name = f'{key}/{rough}/{sheen}/{coat}/{sss}/{alpha}/{emit}'
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    if emit:
        nt.nodes.remove(bsdf)
        e = nt.nodes.new('ShaderNodeEmission')
        e.inputs['Color'].default_value = srgb(COLORS[key])
        e.inputs['Strength'].default_value = 1.0
        nt.links.new(e.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
    else:
        values = {
            'Base Color': srgb(COLORS[key]), 'Roughness': rough, 'Sheen Weight': sheen, 'Coat Weight': coat,
            'Coat Roughness': 0.15, 'Subsurface Weight': sss, 'Subsurface Scale': 0.04, 'Alpha': alpha,
        }
        for k, v in values.items():
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = v
    MATS[name] = m
    return m


def banded(key, band, stops, sheen=0.5):
    """Toy paint in bands along the object's own height (-1 .. 1): `stops` are (from, to) pairs in band colour."""
    m = bpy.data.materials.new(f'{key}-banded')
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    coord = nt.nodes.new('ShaderNodeTexCoord')
    split = nt.nodes.new('ShaderNodeSeparateXYZ')
    remap = nt.nodes.new('ShaderNodeMapRange')
    remap.inputs['From Min'].default_value = -1
    remap.inputs['From Max'].default_value = 1
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = srgb(COLORS[key])
    els[1].position = 1.0
    els[1].color = srgb(COLORS[key])
    for lo, hi in stops:
        a = els.new((lo + 1) / 2)
        a.color = srgb(COLORS[band])
        b = els.new((hi + 1) / 2)
        b.color = srgb(COLORS[key])
    nt.links.new(coord.outputs['Object'], split.inputs[0])
    nt.links.new(split.outputs['Z'], remap.inputs['Value'])
    nt.links.new(remap.outputs['Result'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.6
    bsdf.inputs['Sheen Weight'].default_value = sheen
    bsdf.inputs['Subsurface Weight'].default_value = 0.12
    bsdf.inputs['Subsurface Scale'].default_value = 0.04
    return m


ROOT = None


def finish(obj, material):
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.parent = ROOT
    return obj


def facing(normal):
    """Rotation that turns the object's -Y (its front) towards `normal`."""
    return Vector((0, -1, 0)).rotation_difference(Vector(normal).normalized()).to_euler()


def along(direction):
    """Rotation that turns the object's +Z along `direction`."""
    return Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_euler()


def ball(loc, size, material, normal=None, rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1, location=loc)
    obj = bpy.context.active_object
    obj.scale = size if isinstance(size, tuple) else (size,) * 3
    if normal is not None:
        obj.rotation_euler = facing(normal)
    elif rot is not None:
        obj.rotation_euler = [math.radians(a) for a in rot]
    return finish(obj, material)


def lathe(loc, rx, ry, half, profile, material):
    """A round body whose width follows profile(t) from the bottom (t = -1) to the top (t = 1)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    for v in obj.data.vertices:
        t = v.co.z
        s = profile(t)
        v.co.x *= rx * s
        v.co.y *= ry * s
        v.co.z = t * half
    obj.location = loc
    return finish(obj, material)


def drop(loc, radius, length, material, direction=(0, 0, 1), flat=1.0):
    """A soft teardrop from `loc` towards `direction`: tufts, beaks, claws, spikes, flippers."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=(0, 0, 0))
    obj = bpy.context.active_object
    for v in obj.data.vertices:
        z = v.co.z / radius
        v.co.y *= flat
        if z > 0:
            pull = z ** 1.5
            v.co.x *= 1 - 0.8 * pull
            v.co.y *= 1 - 0.8 * pull
            v.co.z = z * length
    obj.location = loc
    obj.rotation_euler = along(direction)
    return finish(obj, material)


def paddle(loc, direction, length, width, thickness, material):
    """A rounded flipper or leaf whose base sits at `loc` and which reaches `length` along `direction`."""
    d = Vector(direction).normalized()
    obj = ball(tuple(Vector(loc) + d * length * 0.8), (width, thickness, length), material)
    obj.rotation_euler = along(d)
    return obj


def tube(points, radii, material):
    curve = bpy.data.curves.new('tube', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = 1.0
    curve.bevel_resolution = 6
    curve.resolution_u = 16
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for p, co, r in zip(spline.bezier_points, points, radii):
        p.co = co
        p.handle_left_type = p.handle_right_type = 'AUTO'
        p.radius = r
    obj = bpy.data.objects.new('tube', curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.active_object, material)


def on(center, radii, az, el, out=0.0):
    """Point and normal on an ellipsoid; az = 0 is straight ahead (-Y), positive az to the figure's left (+X)."""
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    c, r = Vector(center), Vector(radii)
    n = Vector((d.x / r.x, d.y / r.y, d.z / r.z)).normalized()
    return c + Vector((d.x * r.x, d.y * r.y, d.z * r.z)) + n * out, n


def spread(n):
    """Evenly spread points on a sphere as (az, el) in degrees; az = 0 is straight ahead."""
    out = []
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        rr = math.sqrt(1 - z * z)
        phi = i * 2.399963
        out.append((math.degrees(math.atan2(rr * math.cos(phi), -rr * math.sin(phi))), math.degrees(math.asin(z))))
    return out


def eye(center, radii, az, el, r, iris=None, out=0.0, brow=True):
    """A glossy toy eye set into the surface, with two highlights; iris gives a coloured ring.
    Bigger on young forms; from form 4 a soft, slightly arched brow above it (brow=False where the face has its own markings)."""
    r *= EYE
    p, n = on(center, radii, az, el, out=out)
    left = Vector((-1, 0, 0))
    up = Vector((0, 0, 1))
    front = p + n * r * 0.3
    if iris:
        ball(p - n * r * 0.2, (r, r * 0.5, r), mat(iris, rough=0.25, coat=1.0, sss=0), normal=n)
        r_pupil = r * 0.58
        ball(front - n * r_pupil * 0.3, (r_pupil, r_pupil * 0.45, r_pupil), mat('eye', rough=0.2, coat=1.0, sss=0), normal=n)
        hl = r * 0.62
    else:
        ball(p - n * r * 0.25, (r, r * 0.55, r * 1.12), mat('eye', rough=0.2, coat=1.0, sss=0), normal=n)
        hl = r
    ball(front + up * hl * 0.36 + left * hl * 0.28, hl * 0.26, mat('white', emit=True))
    ball(front - up * hl * 0.32 - left * hl * 0.3, hl * 0.11, mat('white', emit=True))
    if BROW and brow:
        # Level and gently arched, the outer end a touch lower: determined, but friendly.
        side = 1 if az >= 0 else -1
        rr = Vector(radii)
        d = math.degrees(1.55 * r / rr.z)
        w = math.degrees(0.85 * r / rr.x)
        pts = []
        for u, lift in ((-1, 0.04), (0, 0.2), (1, -0.08)):
            q, _ = on(center, radii, az + side * u * w, el + d * (1 + lift), out=out + 0.012)
            pts.append(tuple(q))
        tube(pts, [r * 0.12, r * 0.16, r * 0.12], mat('mouth', rough=0.4, sss=0))


def smile(center, radii, width, el, dip, thick=0.022, out=0.0, key='mouth'):
    dip *= grow(1.0, 1.4)
    width *= grow(1.0, 1.2)
    pts = []
    for i in range(5):
        u = -1 + i / 2
        p, _ = on(center, radii, u * width, el - dip * (1 - u * u), out=out)
        pts.append(tuple(p))
    tube(pts, [thick * 0.8, thick, thick, thick, thick * 0.8], mat(key, rough=0.4, sss=0))


def blush(center, radii, az, el, r):
    p, n = on(center, radii, az, el, out=-r * 0.12)
    ball(p, (r * 1.15, r * 0.25, r * 0.8), mat('blush', rough=0.7), normal=n)


# --- The sixteen partners -------------------------------------------------------------------------
def hommel():
    """A round bumblebee. Grows: longer antennae, bigger wings, a third band (3+), a second pair of wings (5+)."""
    c, R = (0, 0, 1.0), (0.98, 0.92, 0.96)
    stops = [(-0.74, -0.52), (-0.34, -0.12)] if FORM < 3 else [(-0.86, -0.7), (-0.56, -0.4), (-0.27, -0.11)]
    ball(c, R, banded('bee', 'beeBand', stops))
    fuzz = mat('bee', rough=0.7, sheen=0.6)
    tufts = [(-0.13, 0.0, 0.17), (0.12, -0.02, 0.15), (0.0, 0.07, 0.19)]
    if FORM >= 4:
        tufts += [(-0.25, -0.06, 0.12), (0.24, -0.07, 0.12)]
    for dx, dz, s in tufts:
        ball((dx, -0.08, 1.9 + dz), s, fuzz)
    band = mat('beeBand', rough=0.6, sheen=0.4)
    wing = mat('wing', rough=0.15, sss=0, alpha=0.6)
    L, W, S = grow(0.75, 1.35), grow(0.75, 1.45), grow(1.0, 1.25)
    for side in (1, -1):
        eye(c, R, side * 22, 14, 0.16)
        blush(c, R, side * 40, -1, 0.12)
        tip = Vector((side * (0.2 + 0.34 * L), -0.3, 1.85 + 0.68 * L))
        tube([(side * 0.2, -0.25, 1.85), (side * (0.2 + 0.18 * L), -0.36, 1.85 + 0.4 * L), tuple(tip)], [0.035, 0.03, 0.026], band)
        ball(tuple(tip + Vector((0, 0, 0.06))), 0.1, mat('beeBand', rough=0.4, coat=0.5))
        ball((side * (0.45 + 0.17 * W), 0.55, 1.5 + 0.12 * W), (0.5 * W, 0.05, 0.32 * W), wing, rot=(0, side * -28, side * 25))
        if FORM >= 5:
            ball((side * (0.4 + 0.12 * W), 0.6, 1.15), (0.34 * W, 0.04, 0.2 * W), wing, rot=(0, side * 10, side * 25))
        ball((side * 0.98, -0.12, 0.86), (0.15 * S, 0.13 * S, 0.21 * S), band, rot=(0, side * -20, 0))
        ball((side * 0.38, -0.32, 0.1), (0.24 * S, 0.3 * S, 0.13), band)
    smile(c, R, 9, 0, 4)


def mol():
    """A pear-shaped mole. Grows: much bigger digging hands on thicker arms, longer claws, a tuft of hair (4+)."""
    c, half = (0, 0, 1.05), 1.02
    fur = mat('mole', rough=0.75, sheen=0.7)
    lathe(c, 0.95, 0.88, half, lambda t: 1.06 - 0.3 * (t + 1) / 2, fur)
    hc, hr = (0, 0, 1.25), (0.78, 0.74, 0.78)
    pink = mat('molePink', rough=0.45)
    p, n = on(hc, hr, 0, 30, out=0.05)
    ball(p, (0.2, 0.2, 0.16), mat('molePink', rough=0.35, coat=0.3), normal=n)
    for side in (1, -1):
        ball(p + n * 0.15 + Vector((side * 0.07, 0, 0.01)), (0.035, 0.02, 0.025), mat('mouth', rough=0.4, sss=0), normal=n)
    for side in (1, -1):
        eye(hc, hr, side * 24, 46, 0.065)
        blush(hc, hr, side * 38, 22, 0.1)
    smile(hc, hr, 8, 16, 3, thick=0.02)
    p, n = on(c, (0.95, 0.88, half), 0, -22, out=-0.2)
    ball(p, (0.58, 0.3, 0.62), mat('moleBelly', rough=0.75, sheen=0.5), normal=n)
    if FORM >= 4:
        for dx, dz, s in ((-0.08, 0.0, 0.1), (0.08, 0.0, 0.1), (0.0, 0.06, 0.12)):
            drop((dx, 0.0, 2.0 + dz), s, 0.2 + 0.05 * (FORM - 4), fur, direction=(dx * 3, 0.2, 1))
    H, C = grow(0.8, 1.45), grow(0.08, 0.2)
    claw = mat('claw', rough=0.3, sss=0)
    for side in (1, -1):
        palm = Vector((side * (0.95 + 0.16 * H), -0.4, 0.86))
        elbow = (side * (1.0 + 0.14 * H), -0.12, 1.2)
        tube([(side * 0.7, -0.02, 1.38), elbow, tuple(palm + Vector((0, 0.08, 0.2 * H)))], [0.16, 0.1 + 0.05 * H, 0.09 + 0.05 * H], fur)
        ball(tuple(palm), (0.3 * H, 0.11 * H, 0.27 * H), pink, rot=(10, side * 25, side * -15))
        for a in (-50, -20, 10, 40):
            ang = math.radians(a)
            d = Vector((side * math.sin(ang), -0.04, math.cos(ang)))
            tip = palm + Vector((d.x * 0.34 * H, -0.04, d.z * 0.3 * H))
            ball(tuple(tip), 0.085 * H, pink)
            drop(tuple(tip + Vector((d.x * 0.05, -0.02, d.z * 0.05)) * H), 0.045 * H, C * H, claw, direction=(d.x, -0.3, d.z))
        ball((side * 0.4, -0.42, 0.08), (0.26, 0.3, 0.1), pink)


def kikker():
    """A wide frog. Grows: strong jumping legs and bigger feet, more spots; taller eye bulges, folded calves (4+)."""
    c, half = (0, 0, 0.78), 0.8
    body = mat('frog', rough=0.35, coat=0.35)
    lathe(c, 1.12, 0.98, half, lambda t: 1.0 - 0.12 * (t + 1) / 2, body)
    fc, fr = (0, 0, 0.8), (1.06, 0.95, 0.78)
    p, n = on(fc, fr, 0, -40, out=-0.12)
    ball(p, (0.74, 0.25, 0.4), mat('frogBelly', rough=0.5, coat=0.2), normal=n)
    for side in (1, -1):
        g = grow(0.32, 0.4)
        bc, br = (side * 0.46, -0.2, 1.4 + 0.4 * (g - 0.32)), (g + 0.02, g, g)
        ball(bc, br, body)
        eye(bc, br, side * 6, 8, 0.2)
        blush(fc, fr, side * 48, 10, 0.13)
    smile(fc, fr, 32, 20, 7, thick=0.024)
    spot = mat('frogSpot', rough=0.35, coat=0.35)
    spots = [(0, 75, 0.12), (-150, 50, 0.1), (45, 50, 0.1), (150, 45, 0.09), (-40, 55, 0.09), (100, 30, 0.08), (-100, 30, 0.08), (180, 20, 0.1)]
    for az, el, s in spots[:2 + FORM]:
        q, m = on(c, (1.06, 0.93, half * 0.97), az, el, out=-0.02)
        ball(q, (s, s * 0.25, s), spot, normal=m)
    T, P = grow(0.85, 1.35), grow(0.9, 1.25)
    toe = body
    for side in (1, -1):
        ball((side * (0.9 + 0.1 * T), 0.18, 0.3 + 0.06 * T), (0.36 * T, 0.5 * T, 0.3 * T), body, rot=(0, 0, side * -12))
        foot = Vector((side * 1.0, -0.42, 0.07))
        ball(tuple(foot), (0.28 * P, 0.36 * P, 0.08), body, rot=(0, 0, side * -20))
        if FORM >= 4:
            calf = ball((side * (1.02 + 0.1 * T), -0.15, 0.2), (0.17 * T, 0.5 * T, 0.14 * T), body)
            calf.rotation_euler = (0, 0, math.radians(side * -16))
        hand = Vector((side * 0.42, -0.86, 0.08))
        ball(tuple(hand), (0.16, 0.2, 0.08), body)
        for base, spread_, length, s in ((foot, 0.22 * P, 0.34 * P, 0.07 * P), (hand, 0.12, 0.2, 0.07)):
            for a in (-30, 0, 30):
                ang = math.radians(a - side * 15)
                ball(tuple(base + Vector((math.sin(ang) * spread_, -math.cos(ang) * length, 0.02))), s, toe)


def uil():
    """An egg-shaped owl. Grows: taller ear tufts, bigger wings, chest marks (3+), a second tuft (6)."""
    c, half = (0, 0, 1.1), 1.1
    body = mat('owl', rough=0.7, sheen=0.5)
    wingm = mat('owlWing', rough=0.7, sheen=0.5)
    lathe(c, 0.9, 0.82, half, lambda t: 1.04 - 0.14 * (t + 1) / 2, body)
    hc, hr = (0, 0, 1.25), (0.82, 0.76, 0.9)
    for side in (1, -1):
        p, n = on(hc, hr, side * 20, 22, out=-0.08)
        ball(p, (0.36, 0.13, 0.34), mat('owlFace', rough=0.7, sheen=0.4), normal=n)
    for side in (1, -1):
        eye(hc, hr, side * 20, 22, 0.19, iris='amber', out=0.06)
    p, n = on(hc, hr, 0, 8)
    drop(tuple(p), 0.08, 0.18, mat('beak', rough=0.35, coat=0.3), direction=(0, -0.6, -1))
    bc, br = c, (0.9 * 0.95, 0.82 * 0.95, half)
    p, n = on(bc, br, 0, -35, out=-0.1)
    ball(p, (0.5, 0.2, 0.52), mat('owlBelly', rough=0.7, sheen=0.4), normal=n)
    marks = [(-14, -22), (14, -22), (0, -32), (-22, -38), (22, -38), (0, -48)]
    for az, el in marks[:max(0, 2 * (FORM - 2))]:
        q, m = on(bc, br, az, el, out=0.035)
        drop(tuple(q), 0.035, 0.08, wingm, direction=tuple(-m + Vector((0, 0, -0.6))), flat=0.5)
    T, Wg = grow(0.28, 0.62), grow(0.65, 0.98)
    for side in (1, -1):
        drop((side * 0.45, 0.0, 2.02), 0.16, T, body, direction=(side * 0.55, 0.1, 1))
        if FORM == 6:
            drop((side * 0.3, 0.05, 2.08), 0.11, T * 0.6, body, direction=(side * 0.3, 0.15, 1))
        wing_c = Vector((side * 0.86, 0.06, 1.18 + 0.1 * F - 0.42 * Wg))
        wing = ball(tuple(wing_c), (0.14 + 0.05 * F, 0.36, 0.5 * Wg), wingm)
        wing.rotation_euler = along((side * 0.12, 0, 1))
        for j in range(2 + (FORM >= 4) + (FORM >= 6)):
            y = 0.06 + (j - (1 + (FORM >= 4) * 0.5 + (FORM >= 6) * 0.5)) * 0.2
            drop((side * 0.9, y, wing_c.z - 0.34 * Wg), 0.085, 0.2, wingm, direction=(side * 0.2, 0, -1), flat=0.55)
        for a in (-25, 0, 25):
            ang = math.radians(a)
            drop((side * 0.3 + math.sin(ang) * 0.06, -0.62, 0.06), 0.06, 0.16, mat('beak', rough=0.4), direction=(math.sin(ang) * 0.6, -1, -0.15))


def egel():
    """A hedgehog. Grows: more and longer spikes."""
    c, half = (0, 0, 0.95), 0.95
    body = mat('hedgehog', rough=0.7, sheen=0.5)
    lathe(c, 0.95, 0.9, half, lambda t: 1.04 - 0.16 * (t + 1) / 2, body)
    R = (0.92, 0.87, half)
    spike = mat('spike', rough=0.6, sheen=0.3)
    L, rad = grow(0.24, 0.46), grow(0.09, 0.115)
    for az, el in spread(int(grow(150, 330))):
        if el < -25 or (abs(az) < 62 and el < 52):
            continue
        p, nrm = on(c, R, az, el, out=-0.05)
        drop(tuple(p), rad, L, spike, direction=tuple(nrm + Vector((0, 0.45, 0.15))))
    p, nrm = on(c, R, 0, 8)
    drop(tuple(p - nrm * 0.12), 0.21, 0.36, mat('hedgeSnout', rough=0.55, sheen=0.3), direction=(0, -1, -0.1))
    ball(tuple(p + Vector((0, -0.3, -0.04))), (0.11, 0.09, 0.085), mat('nose', rough=0.25, coat=0.6, sss=0))
    for side in (1, -1):
        eye(c, R, side * 27, 28, 0.12)
        blush(c, R, side * 44, 8, 0.11)
        ball((side * 0.36, -0.42, 0.08), (0.2, 0.24, 0.1), mat('paw', rough=0.5))
        ball((side * 0.84, -0.3, 0.75), (0.13, 0.12, 0.17), mat('paw', rough=0.5))
    smile(c, R, 9, -8, 3, out=0.02)


def slak():
    """A snail. Grows: a bigger shell with more turns, round knobs along the back of the shell (4+)."""
    body = mat('snail', rough=0.35, coat=0.4)
    ball((0, 0.15, 0.26), (0.52, 1.15, 0.27), body)
    tube([(0, -0.55, 0.3), (0, -0.75, 0.7), (0, -0.8, 1.05)], [0.34, 0.36, 0.4], body)
    hc, hr = (0, -0.8, 1.22), (0.46, 0.42, 0.44)
    ball(hc, hr, body)
    for side in (1, -1):
        tube([(side * 0.14, -0.82, 1.55), (side * 0.25, -0.88, 1.85), (side * 0.32, -0.9, 2.02)], [0.07, 0.06, 0.055], body)
        ec, er = (side * 0.33, -0.92, 2.1), (0.17, 0.17, 0.17)
        ball(ec, er, mat('sclera', rough=0.3, coat=0.5, sss=0))
        eye(ec, er, side * 6, 2, 0.11)
        blush(hc, hr, side * 40, -8, 0.1)
    smile(hc, hr, 13, -14, 4)
    S = grow(0.8, 1.2)
    sc = Vector((0, 0.4, 0.24 + 0.78 * S))
    rx, ry = 0.5 * S, 0.78 * S
    shell = mat('shell', rough=0.4, coat=0.5)
    ball(tuple(sc), (rx, ry, ry), shell)
    line = mat('shellLine', rough=0.4, coat=0.5)
    turns = grow(0.32, 0.42)
    for side in (1, -1):
        pts = []
        for k in range(41):
            a = k * turns
            r = (0.68 - 0.6 * k / 40) * S
            x = rx * math.sqrt(max(0.0, 1 - (r / ry) ** 2)) + 0.012
            pts.append((side * x, sc.y + r * math.sin(a), sc.z + r * math.cos(a)))
        tube(pts, [0.05 * S] * len(pts), line)
    if FORM >= 4:
        n = 2 * (FORM - 3) + 1
        for i in range(n):
            a = math.radians(10 + 100 * i / max(1, n - 1))
            q = sc + Vector((0, ry * math.sin(a), ry * math.cos(a))) * 0.97
            ball(tuple(q), 0.09 + 0.015 * (FORM - 4), line)


def axolotl():
    """An axolotl. Grows: longer, fuller gills, a longer tail, a fin along the back (4+)."""
    body = mat('axo', rough=0.3, coat=0.5)
    gill = mat('gill', rough=0.4, coat=0.3)
    ball((0, 0.1, 0.55), (0.58, 0.62, 0.5), body)
    T = grow(0.8, 1.3)
    tube([(0, 0.45, 0.45), (0.12, 0.45 + 0.5 * T, 0.42), (0.32, 0.45 + 0.9 * T, 0.52)], [0.32, 0.2, 0.05], body)
    if FORM >= 4:
        drop((0, 0.3, 0.98), 0.14, 0.5 + 0.12 * (FORM - 4), gill, direction=(0, 1, 0.35), flat=0.3)
    p, n = on((0, 0.1, 0.55), (0.58, 0.62, 0.5), 0, -10, out=-0.08)
    ball(p, (0.4, 0.14, 0.33), mat('axoBelly', rough=0.4, coat=0.3), normal=n)
    hc, hr = (0, -0.05, 1.2), (0.88, 0.72, 0.6)
    ball(hc, hr, body)
    G = grow(0.7, 1.3)
    frills = [0.45, 0.7, 0.92] if FORM < 4 else [0.35, 0.52, 0.68, 0.84, 0.98]
    for side in (1, -1):
        eye(hc, hr, side * 38, 16, 0.13)
        blush(hc, hr, side * 54, -2, 0.1)
        for i, (up, length) in enumerate(((0.8, 0.5), (0.3, 0.58), (-0.2, 0.46))):
            base = Vector((side * 0.74, 0.12, 1.32 + 0.1 * (1 - i)))
            d = Vector((side, 0.3, up)).normalized()
            drop(tuple(base), 0.075, length * G, gill, direction=tuple(d))
            for j in frills:
                ball(tuple(base + d * length * G * j + Vector((0, 0, 0.05))), 0.065, gill)
        for y in (-0.3, 0.45):
            ball((side * 0.5, y, 0.12), (0.16, 0.2, 0.12), body)
    smile(hc, hr, 24, -6, 5)


def zeehond():
    """A seal pup lying on its belly. Grows: a longer body, bigger paddle flippers, more spots;
    from form 4 the chest and head lift proudly and whiskers appear."""
    body = mat('seal', rough=0.55, sheen=0.4)
    spotm = mat('sealSpot', rough=0.5)
    B, P, L = grow(1.0, 1.2), grow(0.85, 1.3), grow(0.0, 0.2)
    ball((0, 0.3 * B, 0.42), (0.72, 1.0 * B, 0.42), body)
    ball((0, -0.15, 0.7 + 0.3 * L), (0.66, 0.64, 0.52 + 0.3 * L), body)
    hc, hr = (0, -0.35, 1.08 + 0.8 * L), (0.66, 0.6, 0.6)
    ball(hc, hr, body)
    for side in (1, -1):
        eye(hc, hr, side * 27, 14, 0.17)
        blush(hc, hr, side * 46, -4, 0.11)
        base = (side * 0.6, -0.3, 0.3 + 0.1 * L)
        paddle(base, (side * 0.9, -0.5, -0.4), 0.36 * P, 0.22 * P, 0.09, body)
        paddle((side * 0.14, 1.2 * B, 0.17), (side * 0.55, 1, 0.08), 0.3 * P, 0.2 * P, 0.07, body)
    p, n = on(hc, hr, 0, -12, out=-0.06)
    ball(p, (0.27, 0.15, 0.18), mat('sealMuzzle', rough=0.55, sheen=0.4), normal=n)
    ball(tuple(p + n * 0.13 + Vector((0, 0, 0.07))), (0.09, 0.06, 0.06), mat('nose', rough=0.25, coat=0.6, sss=0))
    for side in (1, -1):
        for dx, dz in ((0.12, 0.0), (0.17, -0.05), (0.1, -0.08)):
            ball(tuple(p + n * 0.13 + Vector((side * dx, 0, dz))), 0.016, spotm)
        if FORM >= 4:
            for dz in (0.03, -0.04):
                start = p + n * 0.1 + Vector((side * 0.17, 0, dz))
                tube([tuple(start), tuple(start + Vector((side * 0.2, -0.1, dz * 2 + 0.01))), tuple(start + Vector((side * 0.38, -0.12, dz * 3 - 0.04)))],
                     [0.011, 0.009, 0.006], spotm)
    head_spots = [(-60, 30, 0.07), (70, 10, 0.06), (120, 40, 0.06), (-110, 15, 0.05)]
    back_spots = [(0.3, 0.6, 0.78, 0.08), (-0.25, 0.9, 0.72, 0.06), (0.05, 0.25, 0.86, 0.05), (-0.3, 0.4, 0.78, 0.05), (0.2, 1.05, 0.66, 0.06)]
    for az, el, s in head_spots[:1 + FORM // 2]:
        q, m = on(hc, hr, az, el, out=-0.01)
        ball(q, (s, s * 0.25, s), spotm, normal=m)
    for x, y, z, s in back_spots[:FORM - 1]:
        ball((x, y * B, z), (s, s, s * 0.3), spotm)


def pinguin():
    """A penguin. Grows: bigger flippers, a yellow crest above the eyes (4+) that gets longer."""
    c, half = (0, 0, 1.0), 1.0
    body = mat('peng', rough=0.5, sheen=0.3)
    white = mat('pengWhite', rough=0.6, sheen=0.3)
    lathe(c, 0.85, 0.8, half, lambda t: 1.05 - 0.12 * (t + 1) / 2, body)
    R = (0.83, 0.78, half)
    p, n = on(c, R, 0, -18, out=-0.12)
    ball(p, (0.6, 0.22, 0.68), white, normal=n)
    for side in (1, -1):
        p, n = on(c, R, side * 18, 30, out=-0.07)
        ball(p, (0.3, 0.12, 0.28), white, normal=n)
    Fl = grow(0.85, 1.3)
    for side in (1, -1):
        eye(c, R, side * 18, 33, 0.12, out=0.03)
        blush(c, R, side * 36, 18, 0.1)
        paddle((side * 0.76, -0.02, 1.1), (side * 0.4, 0, -1), 0.36 * Fl, 0.16 * Fl, 0.07, body)
        ball((side * 0.3, -0.45, 0.05), (0.2, 0.28, 0.07), mat('beak', rough=0.4))
        if FORM >= 4:
            crest = mat('crest', rough=0.6, sheen=0.5)
            q, m = on(c, R, side * 28, 50, out=-0.02)
            for j in range(FORM - 2):
                drop(tuple(q + Vector((side * 0.04 * j, 0.03 * j, 0.02 * j))), 0.05, 0.22 + 0.06 * (FORM - 4) + 0.03 * j, crest,
                     direction=(side * 1, 0.4 + 0.15 * j, 0.5 - 0.1 * j))
    p, n = on(c, R, 0, 22)
    drop(tuple(p), 0.09, 0.2, mat('beak', rough=0.35, coat=0.3), direction=(0, -1, -0.25))


def schildpad():
    """A turtle. Grows: a higher shell with bigger plates, round studs along the shell ridge (4+)."""
    skin = mat('turtle', rough=0.45, coat=0.3)
    H = grow(0.6, 0.8)
    sc, sr = (0, 0.15, 0.5), (1.0, 1.05, H)
    ball(sc, sr, mat('tShell', rough=0.4, coat=0.5))
    ball((0, 0.15, 0.42), (1.07, 1.12, 0.16), mat('tRim', rough=0.4, coat=0.5))
    plate = mat('tPlate', rough=0.4, coat=0.5)
    P = grow(0.85, 1.15)
    for az, el, s in [(0, 88, 0.3)] + [(a, 38, 0.24) for a in range(0, 360, 60)]:
        p, n = on(sc, sr, az, el, out=-0.03)
        ball(p, (s * P, s * 0.22, s * 0.85 * P), plate, normal=n)
    if FORM >= 4:
        n_k = 2 * (FORM - 3) + 1
        for i in range(n_k):
            ang = 62 + 100 * i / max(1, n_k - 1)
            q, m = on(sc, sr, 0 if ang <= 90 else 180, ang if ang <= 90 else 180 - ang, out=-0.02)
            ball(tuple(q + m * 0.04), 0.115 + 0.025 * (FORM - 4), mat('tRim', rough=0.4, coat=0.5))
    tube([(0, -0.7, 0.45), (0, -0.95, 0.7), (0, -1.02, 0.95)], [0.24, 0.25, 0.27], skin)
    hc, hr = (0, -1.05, 1.15), (0.5, 0.46, 0.46)
    ball(hc, hr, skin)
    L = grow(1.0, 1.25)
    for side in (1, -1):
        eye(hc, hr, side * 30, 14, 0.12)
        blush(hc, hr, side * 48, -4, 0.09)
        for y in (-0.55, 0.8):
            ball((side * 0.78, y, 0.14), (0.24 * L, 0.26 * L, 0.17 * L), skin)
    smile(hc, hr, 14, -10, 4)
    drop((0, 1.15, 0.32), 0.1, 0.25, skin, direction=(0, 1, -0.3))


def konijn():
    """A rabbit. Grows: longer ears that stand more alert, big strong hind feet, powerful haunches (4+)."""
    c, half = (0, 0, 0.95), 0.95
    body = mat('bunny', rough=0.75, sheen=0.6)
    lathe(c, 0.9, 0.85, half, lambda t: 1.05 - 0.15 * (t + 1) / 2, body)
    R = (0.88, 0.83, half)
    E, Ft = grow(0.75, 1.15), grow(0.9, 1.35)
    for side in (1, -1):
        base = Vector((side * 0.28, 0.05, 1.7))
        up = Vector((side * (0.25 + 0.12 * F), 0.12, 1)).normalized()
        ear = ball(tuple(base + up * 0.45 * E), (0.2, 0.09, 0.5 * E), body)
        ear.rotation_euler = along(up)
        inner = ball(tuple(base + up * 0.48 * E + Vector((0, -0.07, 0))), (0.12, 0.04, 0.38 * E), mat('bunnyEar', rough=0.6))
        inner.rotation_euler = along(up)
        eye(c, R, side * 24, 24, 0.13)
        blush(c, R, side * 42, 10, 0.11)
        ball((side * 0.35, -0.42 - 0.08 * (Ft - 1), 0.07), (0.22 * Ft, 0.36 * Ft, 0.1 * Ft), body)
        ball((side * 0.78, -0.35, 0.72), (0.13, 0.12, 0.17), body)
        if FORM >= 4:
            ball((side * 0.64, 0.12, 0.4), (0.3 + 0.04 * (FORM - 4), 0.44, 0.32 + 0.04 * (FORM - 4)), body)
    p, n = on(c, R, 0, 13, out=0.02)
    ball(p, (0.07, 0.05, 0.05), mat('bunnyEar', rough=0.4, coat=0.4), normal=n)
    smile(c, R, 8, 6, 3)
    p, n = on(c, R, 0, -30, out=-0.1)
    ball(p, (0.46, 0.2, 0.46), mat('bunnyBelly', rough=0.75, sheen=0.6), normal=n)
    ball((0, 0.85, 0.5), 0.2, mat('tail', rough=0.9, sheen=0.8))


def wasbeer():
    """A raccoon. Grows: a longer tail with more rings, a wider mask; from form 4 pale brow patches."""
    c, half = (0, 0, 0.95), 0.95
    body = mat('racc', rough=0.75, sheen=0.6)
    mask = mat('raccMask', rough=0.6, sheen=0.4)
    light = mat('raccLight', rough=0.7, sheen=0.5)
    lathe(c, 0.9, 0.85, half, lambda t: 1.05 - 0.13 * (t + 1) / 2, body)
    R = (0.88, 0.83, half)
    M = grow(1.0, 1.2)
    for side in (1, -1):
        p, n = on(c, R, side * 24, 25, out=-0.06)
        ball(p, (0.27 * M, 0.12, 0.17 * M), mask, normal=n)
        eye(c, R, side * 24, 25, 0.12, out=0.04, brow=False)
        ear = ball((side * 0.52, 0.04, 1.7), (0.22, 0.13, 0.2), body)
        ear.rotation_euler = along((side * 0.35, 0, 1))
        inner = ball((side * 0.53, -0.07, 1.7), (0.13, 0.06, 0.12), mat('raccInner', rough=0.7, sheen=0.4))
        inner.rotation_euler = along((side * 0.35, 0, 1))
        ball((side * 0.3, -0.42, 0.07), (0.18, 0.24, 0.09), mask)
        ball((side * 0.8, -0.32, 0.72), (0.12, 0.11, 0.16), mask)
        if FORM >= 4:
            q, m = on(c, R, side * 24, 43, out=-0.02)
            ball(q, (0.13, 0.05, 0.05), light, normal=m)
    p, n = on(c, R, 0, 7, out=-0.06)
    ball(p, (0.3, 0.16, 0.2), light, normal=n)
    ball(tuple(p + n * 0.15 + Vector((0, 0, 0.06))), (0.08, 0.06, 0.06), mat('nose', rough=0.25, coat=0.6, sss=0))
    smile(c, R, 8, 2, 3, out=0.08)
    p, n = on(c, R, 0, -30, out=-0.1)
    ball(p, (0.48, 0.2, 0.48), light, normal=n)
    T = grow(0.7, 1.25)
    a, b, d = Vector((0.5, 0.6, 0.35)), Vector((0.5 + 0.55 * T, 0.55, 0.75 * T)), Vector((0.5 + 0.5 * T, 0.75, 1.35 * T))
    rings = 4 + FORM
    for i in range(rings):
        t = i / (rings - 1)
        pos = (1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * d
        ball(tuple(pos), (0.25 - 0.08 * t) * grow(0.9, 1.1), mask if i % 2 else body)


def lieveheersbeestje():
    """A ladybird. Grows: more dots, longer antennae, see-through wings peeking out (5+)."""
    sc, sr = (0, 0.12, 0.72), (0.92, 0.95, 0.7)
    ball(sc, sr, mat('bug', rough=0.3, coat=0.7))
    dark = mat('bugDark', rough=0.4, coat=0.4)
    pts = []
    for k in range(9):
        a = math.radians(42 + k * 15)
        pts.append((0, sc[1] - sr[1] * 1.01 * math.cos(a), sc[2] + sr[2] * 1.01 * math.sin(a)))
    tube(pts, [0.03] * len(pts), dark)
    dots = [(50, 45, 0.16), (-50, 45, 0.16), (95, 20, 0.15), (-95, 20, 0.15), (140, 45, 0.14), (-140, 45, 0.14),
            (115, 70, 0.12), (-115, 70, 0.12), (70, 15, 0.1), (-70, 15, 0.1), (165, 25, 0.11), (-165, 25, 0.11)]
    for az, el, s in dots[:2 * FORM]:
        p, n = on(sc, sr, az, el, out=-0.02)
        ball(p, (s, s * 0.25, s), dark, normal=n)
    if FORM >= 5:
        wing = mat('wing', rough=0.15, sss=0, alpha=0.6)
        for side in (1, -1):
            ball((side * 0.55, 0.95, 0.75), (0.45, 0.05, 0.25) if FORM == 5 else (0.6, 0.05, 0.3), wing, rot=(0, side * -15, side * 35))
    hc, hr = (0, -0.78, 0.72), (0.52, 0.42, 0.44)
    ball(hc, hr, dark)
    A = grow(0.8, 1.3)
    for side in (1, -1):
        eye(hc, hr, side * 28, 16, 0.14, iris='sclera', out=0.03, brow=False)
        blush(hc, hr, side * 50, -8, 0.09)
        tip = (side * (0.15 + 0.27 * A), -0.92 - 0.1 * A, 1.08 + 0.5 * A)
        tube([(side * 0.15, -0.9, 1.08), (side * (0.15 + 0.15 * A), -0.92 - 0.13 * A, 1.08 + 0.32 * A), tip], [0.03, 0.026, 0.022], dark)
        ball((tip[0], tip[1], tip[2] + 0.04), 0.07, dark)
        for y in (-0.4, 0.1, 0.6):
            tube([(side * 0.6, y, 0.25), (side * 0.85, y - 0.05, 0.12), (side * 0.9, y - 0.12, 0.03)], [0.05, 0.045, 0.04], dark)
    smile(hc, hr, 14, -10, 4, key='blush', out=0.01)


def octopus():
    """An octopus. Grows: longer arms that curl at the tips (4+), a taller mantle, more spots, suckers (3+)."""
    half = grow(0.75, 0.95)
    c = (0, 0, 1.25 + half - 0.75)
    body = mat('octo', rough=0.35, coat=0.4)
    light = mat('octoLight', rough=0.4, coat=0.3)
    lathe(c, 0.8, 0.75, half, lambda t: 0.94 + 0.1 * (t + 1) / 2, body)
    R = (0.78, 0.73, half)
    T = grow(0.75, 1.3)
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        cs, sn = math.sin(a), -math.cos(a)
        rz = [(0.4, 0.75), (0.85 * T, 0.3), (1.12 * T, 0.11), (1.28 * T, 0.28)]
        radii = [0.22, 0.17 * grow(0.9, 1.15), 0.1 * grow(0.9, 1.15), 0.05]
        if FORM >= 4:
            curl = 0.12 * (FORM - 3)
            rz += [(1.34 * T, 0.28 + curl), (1.2 * T, 0.3 + 2 * curl)]
            radii = [0.22, 0.17 * grow(0.9, 1.15), 0.11 * grow(0.9, 1.15), 0.075, 0.05, 0.028]
        tube([(r * cs, r * sn, z) for r, z in rz], radii, body)
        if FORM >= 3:
            for j in range(FORM - 2):
                t = 0.62 + 0.08 * j
                q = Vector((t * 1.25 * T * cs, t * 1.25 * T * sn, 0.11 + 0.12))
                ball(tuple(q), 0.045, light)
    for side in (1, -1):
        eye(c, R, side * 24, -10, 0.15)
        blush(c, R, side * 42, -22, 0.1)
    smile(c, R, 10, -28, 4)
    spots = [(60, 40, 0.09), (-70, 50, 0.11), (110, 20, 0.08), (0, 70, 0.1), (-30, 30, 0.07), (150, 50, 0.09), (-130, 30, 0.08)]
    for az, el, s in spots[:FORM + 1]:
        p, n = on(c, R, az, el, out=-0.01)
        ball(p, (s, s * 0.25, s), mat('octoSpot', rough=0.35, coat=0.4), normal=n)


def eekhoorn():
    """A squirrel holding an acorn. Grows: a much bigger tail that arches over the back with a cream tip, longer ear tufts."""
    c, half = (0, 0, 0.9), 0.9
    body = mat('squirrel', rough=0.7, sheen=0.6)
    cream = mat('cream', rough=0.7, sheen=0.5)
    tail = mat('squirrelTail', rough=0.75, sheen=0.7)
    lathe(c, 0.85, 0.8, half, lambda t: 1.05 - 0.15 * (t + 1) / 2, body)
    R = (0.83, 0.78, half)
    T = grow(0.7, 1.2)
    base = Vector((0.15, 0.7, 0.3))
    ctrl = [base + (Vector(q) - base) * T for q in ((0.15, 0.7, 0.3), (1.35, 1.1, 0.55), (1.25, 0.9, 2.0), (0.2, 0.65, 2.0))]
    for i in range(17):
        t = i / 16
        pos = sum((w * q for w, q in zip(((1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3), ctrl)), Vector())
        r = (0.26 + 0.2 * math.sin(math.pi * min(1.0, t ** 0.8 * 1.05)) ** 0.7) * T
        ball(tuple(pos), r, mat('tailTip' if t > 0.82 else 'squirrelTail', rough=0.75, sheen=0.7))
    p, n = on(c, R, 0, -25, out=-0.1)
    ball(p, (0.48, 0.2, 0.5), cream, normal=n)
    p, n = on(c, R, 0, 8, out=-0.05)
    ball(p, (0.28, 0.12, 0.18), cream, normal=n)
    ball(tuple(p + n * 0.1 + Vector((0, 0, 0.07))), (0.07, 0.05, 0.05), mat('nose', rough=0.25, coat=0.6, sss=0))
    smile(c, R, 7, 2, 3, out=0.06)
    tuft = grow(0.08, 0.26)
    for side in (1, -1):
        eye(c, R, side * 24, 24, 0.13)
        blush(c, R, side * 42, 10, 0.1)
        drop((side * 0.35, 0.05, 1.6), 0.16, 0.36, body, direction=(side * 0.3, 0, 1), flat=0.55)
        drop((side * 0.42, 0.05, 1.9), 0.06, tuft, tail, direction=(side * 0.3, 0, 1))
        ball((side * 0.33, -0.42, 0.07), (0.2, 0.3, 0.09), body)
        ball((side * 0.15, -0.8, 0.86), 0.09, body)
    ball((0, -0.86, 0.84), (0.13, 0.12, 0.16), mat('acorn', rough=0.35, coat=0.5))
    ball((0, -0.86, 0.97), (0.15, 0.14, 0.07), mat('acornCap', rough=0.8))


def lammetje():
    """A lamb. Grows: a fuller fleece, curled horns from form 3 that grow into big ram horns."""
    wool = mat('wool', rough=0.9, sheen=0.8, sss=0.2)
    face = mat('lambFace', rough=0.6, sheen=0.3)
    hoof = mat('hoof', rough=0.5)
    c, R = (0, 0.1, 0.98), (0.8, 0.8, 0.72)
    ball(c, (0.85, 0.85, 0.78), wool)
    for az, el in spread(int(grow(45, 95))):
        if el < -45:
            continue
        p, n = on(c, R, az, el)
        ball(p, grow(0.28, 0.24), wool)
    for side in (1, -1):
        for y in (-0.35, 0.5):
            tube([(side * 0.38, y, 0.4), (side * 0.38, y, 0.08)], [0.11, 0.1], hoof)
    hc, hr = (0, -0.68, 1.12), (0.46, 0.38, 0.44)
    ball(hc, hr, face)
    for x, z, s in ((-0.15, 1.52, 0.17), (0.15, 1.52, 0.17), (0.0, 1.6, 0.19)):
        ball((x, -0.6, z), s, wool)
    for side in (1, -1):
        eye(hc, hr, side * 26, 10, 0.12)
        blush(hc, hr, side * 46, -8, 0.09)
        drop((side * 0.4, -0.58, 1.25), 0.11, 0.38, face, direction=(side, 0.1, -0.35), flat=0.4)
        if FORM >= 3:
            hs = (FORM - 2) / 4
            pts, radii = [], []
            steps = 14
            for k in range(steps + 1):
                a = 2 * math.pi * 1.05 * hs * k / steps
                r = (0.14 + 0.2 * hs) * (1 - 0.5 * k / steps)
                # A curl beside the face: it starts on top of the head and winds back, down and forward.
                pts.append((side * (0.46 + 0.1 * hs * k / steps), -0.78 + r * math.sin(a), 1.5 + r * (math.cos(a) - 1)))
                radii.append((0.075 + 0.07 * hs) * (1 - 0.55 * k / steps))
            tube(pts, radii, mat('horn', rough=0.5, coat=0.3))
    p, n = on(hc, hr, 0, -14, out=0.01)
    ball(p, (0.06, 0.04, 0.04), mat('bunnyEar', rough=0.4, coat=0.4), normal=n)
    smile(hc, hr, 9, -24, 3)


BUILDERS = {'hommel': hommel, 'mol': mol, 'kikker': kikker, 'uil': uil,
            'egel': egel, 'slak': slak, 'axolotl': axolotl, 'zeehond': zeehond,
            'pinguin': pinguin, 'schildpad': schildpad, 'konijn': konijn, 'wasbeer': wasbeer,
            'lieveheersbeestje': lieveheersbeestje, 'octopus': octopus, 'eekhoorn': eekhoorn, 'lammetje': lammetje}

# --- Scene ----------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.film_transparent = True
scene.view_settings.view_transform = 'Standard'
scene.view_settings.exposure = -0.35

world = bpy.data.worlds.new('World')
scene.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = srgb('#FFF1E6')
world.node_tree.nodes['Background'].inputs[1].default_value = 0.42


def area(name, loc, energy, size, color='#FFFFFF', shadow=True):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.size = size
    data.color = srgb(color)[:3]
    data.use_shadow = shadow
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return obj


area('Key', (-3.5, -4.5, 7.0), 1300, 4.0, '#FFF4E8')
area('Fill', (5.0, -4.0, 3.0), 150, 5.0, '#EEF2FF', shadow=False)
area('Rim', (1.5, 5.0, 4.5), 300, 3.0, shadow=False)

bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
ground = bpy.context.active_object
ground.is_shadow_catcher = True

cam_data = bpy.data.cameras.new('Camera')
cam_data.lens = 72
cam = bpy.data.objects.new('Camera', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 0, 1.2))
cam.location = target + Vector((-3.0, -8.6, 2.2))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()

for name in ONLY:
    for form in FORMS:
        for obj in list(bpy.data.objects):
            if obj.type in ('MESH', 'EMPTY') and obj is not ground:
                bpy.data.objects.remove(obj, do_unlink=True)
        FORM, F, EYE, BROW = form, (form - 1) / 5, EYES[form - 1], form >= 4
        ROOT = bpy.data.objects.new(f'{name}-{form}', None)
        scene.collection.objects.link(ROOT)
        BUILDERS[name]()
        k = K[form - 1]
        ROOT.scale = (k, k, k * (1 + 0.1 * F))
        scene.render.filepath = os.path.join(OUT, f'{name}-{form}.png')
        bpy.ops.render.render(write_still=True)
        print('wrote', scene.render.filepath, flush=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'partners.blend'))

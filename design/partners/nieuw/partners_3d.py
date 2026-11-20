"""Sixteen partners as soft 3D toy figures in six forms each, built from code in Blender and rendered with Cycles.

Run: blender -b --factory-startup -P partners_3d.py -- <output folder> [samples] [names, e.g. hommel,uil] [forms, e.g. 1,6]
Writes <name>-<form>.png (transparent, with the contact shadow in the alpha) and partners.blend.
Every figure stands on z = 0 and faces -Y. One camera for all, so the growth from form 1 to 6 shows.

The six forms change the body plan, not just the size (the figure is fitted to the frame per form, see HEIGHTS):
1 baby: almost all head, stubby nubs, palest colours. 2 toddler: small limbs. 3 junior: its own torso and a first
signature feature. 4 athlete: stands upright, broad shoulders, adult markings. 5 strong: muscular, V-shaped chest,
wide stance, big signature feature. 6 champion: heroic flex pose, the fullest signature feature, deepest colours.
Eyes shrink relative to the head as it matures; from form 4 a friendly brow line appears.
"""
import colorsys
import math
import os
import sys
from types import SimpleNamespace

import bpy
import numpy as np
from mathutils import Euler, Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = args[0] if args else os.path.dirname(os.path.abspath(__file__))
SAMPLES = int(args[1]) if len(args) > 1 else 64
ALL = ['hommel', 'mol', 'kikker', 'uil', 'egel', 'slak', 'axolotl', 'zeehond',
       'pinguin', 'schildpad', 'konijn', 'wasbeer', 'lieveheersbeestje', 'octopus', 'eekhoorn', 'lammetje']
ONLY = args[2].split(',') if len(args) > 2 and args[2] != 'all' else ALL
FORMS = [int(x) for x in args[3].split(',')] if len(args) > 3 else [1, 2, 3, 4, 5, 6]

# The athletic anatomy per form (index = form - 1). Lengths are in design units; every figure is about T tall
# before it is fitted to the frame, and then scaled to HEIGHTS (frame fractions of the 4.0 tall picture).
T = 3.0
HEAD = [0.88, 0.72, 0.58, 0.48, 0.44, 0.42]       # head height / total height
LEG = [0.0, 0.06, 0.15, 0.24, 0.26, 0.26]         # leg length / total height
SHOULDER = [0.5, 0.56, 0.62, 0.7, 0.78, 0.84]     # torso half-width
LIMB = [0.11, 0.12, 0.14, 0.19, 0.25, 0.29]       # arm radius
ARM = [0.3, 0.45, 0.65, 0.95, 1.1, 1.2]           # shoulder to fist
MUSCLE = [0.0, 0.0, 0.1, 0.4, 0.8, 1.0]           # biceps, thighs, shoulder caps, V-taper
SHOULDER_Z = [0.5, 0.6, 0.72, 0.82, 0.84, 0.86]   # shoulder height between hip and neck
HEIGHTS = [1.0, 1.4, 1.9, 2.45, 2.9, 3.3]       # on-screen height of each form
EYES = [1.3, 1.2, 1.08, 0.96, 0.88, 0.82]         # eye size relative to the head

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
    'hedgehog': '#EBC79A', 'hedgeSnout': '#E0AB7B', 'hedgehogBelly': '#F7E3C0', 'spike': '#8C5A3A', 'paw': '#E9A08F',
    # slak
    'snail': '#9FD8C2', 'shell': '#F2836B', 'shellLine': '#C2563F',
    # axolotl
    'axo': '#F6A6B9', 'gill': '#E35D82', 'axoBelly': '#FCD6DF',
    # zeehond
    'seal': '#91A5B9', 'sealMuzzle': '#EEF2F5', 'sealSpot': '#6F8397',
    # pinguin
    'peng': '#34456A', 'pengWhite': '#F7F5F0', 'crest': '#F6C445',
    # schildpad
    'turtle': '#B9D27F', 'tShell': '#2F8C7E', 'tPlate': '#5DB8A5', 'tRim': '#257265', 'tBelly': '#DCE8B8',
    # konijn
    'bunny': '#C8946A', 'bunnyBelly': '#FBF3EA', 'bunnyEar': '#EE8E9E', 'tail': '#FFFFFF', 'bunnyTip': '#6B5648',
    # wasbeer
    'racc': '#8F929C', 'raccMask': '#45434C', 'raccLight': '#EEEBE6', 'raccInner': '#5C5A66',
    # lieveheersbeestje
    'bug': '#E2483D', 'bugDark': '#2E2629', 'bugFoot': '#7A6A6C',
    # octopus
    'octo': '#B48AD8', 'octoSpot': '#9A6CC4', 'octoLight': '#E3D0F2',
    # eekhoorn
    'squirrel': '#E58A3E', 'squirrelTail': '#D2742E', 'tailTip': '#F6DFC0', 'cream': '#F6DFC0', 'acorn': '#B07A45', 'acornCap': '#6E4B2E',
    # lammetje
    'wool': '#E4D4B9', 'lambFace': '#CFA67F', 'lambLimb': '#A58B78', 'hoof': '#5A4842', 'horn': '#A87E55',
}

# Set per form before an animal is built.
FORM, F, EYE, BROW = 1, 0.0, 1.0, False


def grow(a, b):
    """From a at form 1 to b at form 6."""
    return a + (b - a) * F


NEUTRAL = {'eye', 'white', 'blush', 'mouth', 'nose', 'sclera', 'claw', 'wing', 'crest'}


def shade(key, hexcode):
    """Palest and softest at form 1, deeper and richer towards form 6 (about 23% darker for saturated colours)."""
    if key in NEUTRAL:
        return hexcode
    r, g, b = (int(hexcode[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, sat, v = colorsys.rgb_to_hsv(r, g, b)
    sat = min(1.0, sat * (0.88 + 0.32 * F))
    v = min(1.0, v * (1.07 - 0.3 * F * (0.35 + 0.65 * min(1.0, sat * 2.5))))
    return '#%02X%02X%02X' % tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, sat, v))


def srgb(hexcode):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(hexcode[i:i + 2], 16)) for i in (1, 3, 5)) + (1.0,)


MATS = {}


def mat(key, rough=0.55, sheen=0.0, coat=0.0, sss=0.12, alpha=1.0, emit=False):
    """A soft vinyl-toy surface. emit=True gives a flat light colour (eye highlights)."""
    name = f'{FORM}/{key}/{rough}/{sheen}/{coat}/{sss}/{alpha}/{emit}'
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    if emit:
        nt.nodes.remove(bsdf)
        e = nt.nodes.new('ShaderNodeEmission')
        e.inputs['Color'].default_value = srgb(shade(key, COLORS[key]))
        e.inputs['Strength'].default_value = 1.0
        nt.links.new(e.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
    else:
        values = {
            'Base Color': srgb(shade(key, COLORS[key])), 'Roughness': rough, 'Sheen Weight': sheen, 'Coat Weight': coat,
            'Coat Roughness': 0.15, 'Subsurface Weight': sss, 'Subsurface Scale': 0.04, 'Alpha': alpha,
        }
        for k, v in values.items():
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = v
    MATS[name] = m
    return m


def matte(material):
    """A copy of a material without gloss or sheen: feet and hooves stay soft instead of catching the key light."""
    name = material.name + '/matte'
    if name not in MATS:
        m = material.copy()
        m.name = name
        bsdf = m.node_tree.nodes.get('Principled BSDF')
        if bsdf:
            bsdf.inputs['Coat Weight'].default_value = 0.0
            bsdf.inputs['Sheen Weight'].default_value = 0.0
            bsdf.inputs['Roughness'].default_value = max(0.65, bsdf.inputs['Roughness'].default_value)
        MATS[name] = m
    return MATS[name]


def banded(key, band, stops, sheen=0.5):
    """Toy paint in bands along the object's own height (-1 .. 1, bottom to top): `stops` are (from, to) pairs in band colour."""
    m = bpy.data.materials.new(f'{FORM}/{key}-banded')
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    coord = nt.nodes.new('ShaderNodeTexCoord')
    split = nt.nodes.new('ShaderNodeSeparateXYZ')
    remap = nt.nodes.new('ShaderNodeMapRange')
    remap.inputs['From Min'].default_value = 0
    remap.inputs['From Max'].default_value = 1
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = srgb(shade(key, COLORS[key]))
    els[1].position = 1.0
    els[1].color = srgb(shade(key, COLORS[key]))
    for lo, hi in stops:
        a = els.new((lo + 1) / 2)
        a.color = srgb(shade(band, COLORS[band]))
        b = els.new((hi + 1) / 2)
        b.color = srgb(shade(key, COLORS[key]))
    nt.links.new(coord.outputs['Generated'], split.inputs[0])
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


def lathe(loc, rx, ry, half, profile, material, square=2.0):
    """A round body whose width follows profile(t) from the bottom (t = -1) to the top (t = 1).
    square > 2 squares off the upper half into broad shoulders."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    for v in obj.data.vertices:
        t = v.co.z
        s = profile(t)
        if t > 0 and square != 2.0:
            s *= (1 - t ** square) ** (1 / square) / math.sqrt(max(1 - t * t, 1e-6))
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
    curve.bevel_resolution = 10
    curve.resolution_u = 24
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



def bulge(a, b, r, material, shift=(0, 0, 0)):
    """A muscle: a rounded oblong between a and b, `shift` pushes it to one side of the limb."""
    a, b = Vector(a), Vector(b)
    obj = ball(tuple((a + b) / 2 + Vector(shift)), (r, r, (b - a).length * 0.5), material)
    obj.rotation_euler = along(b - a)
    return obj


def face(P, eyes, mouth, blush_at=(40, -2, 0.11), iris=None, out=0.0, brow=True, thick=0.022):
    """Eyes, blush and smile on the head ellipsoid of plan P. Sizes are for a head of radius 0.85 and scale with it.
    eyes = (az, el, r); mouth = (width, el, dip)."""
    az, el, r = eyes
    for side in (1, -1):
        eye(P.hc, P.hr, side * az, el, r * P.u, iris=iris, out=out, brow=brow)
        blush(P.hc, P.hr, side * blush_at[0], blush_at[1], blush_at[2] * P.u)
    smile(P.hc, P.hr, mouth[0], mouth[1], mouth[2], thick=thick * P.u)


def pose_of(side):
    """Default arm poses: hanging up to form 4, ready from 5, and at form 6 one arm flexed (-X) and one fist on the hip."""
    if FORM <= 4:
        return 'hang'
    if FORM == 5:
        return 'ready'
    return 'flex' if side < 0 else 'hip'


def athlete(skin, *, torso=None, head=None, limb=None, hand=None, leg=None, foot=None, belly=None, arms=True,
            head_w=1.0, head_d=0.92, torso_d=0.8, torso_w=1.0, thigh=1.0, bicep=1.0, hand_size=1.0, leg_scale=1.0, toes=0,
            poses=None, head_ball=True, sink=0.36, head_scale=1.0, head_fwd=0.0):
    """The shared body of the upright partners: head, torso, arms with biceps, legs with thighs and feet.
    What changes per form: the head shrinks from 88% to 42% of the height, the torso gets its own shape and
    broadens into a V, limbs appear (nubs, small, real, muscular), the stance widens, and from form 6 one arm flexes.
    Returns the anchors the species decorate: head centre and radii (hc, hr, u), torso (tc, trx, try_, half, top),
    the shoulder, hand and foot positions and the muscle level M."""
    f = FORM - 1
    M = MUSCLE[f]
    torso, head, limb = torso or skin, head or skin, limb or skin
    hand, leg, foot = hand or limb, leg or limb, foot or leg
    hz = HEAD[f] * T / 2 * head_scale
    P = SimpleNamespace(M=M, hz=hz, u=hz / 0.85, hr=(hz * head_w, hz * head_w * head_d, hz), hc=(0, 0, T - hz))
    top = T - hz * 2 * sink
    L = LEG[f] * T * leg_scale
    base = L * 0.85
    rx = SHOULDER[f] * (1 - 0.1 * (1 - M)) * torso_w
    ry = rx * torso_d
    P.hc = (0, -head_fwd * ry, T - hz)
    half = (top - base) / 2
    P.tc, P.rx, P.ry, P.half, P.top, P.base = (0, 0, base + half), rx, ry, half, top, base
    lathe(P.tc, rx, ry, half, lambda t: 1 + 0.3 * M * t, torso, square=2 + 0.8 * M)
    if head_ball:
        ball(P.hc, P.hr, head)
    if belly:
        R = (rx, ry, half)
        if M >= 0.8:
            p, n = on(P.tc, R, 0, 30, out=0.04 * ry)
            ball(p, (rx * 0.78, ry * 0.2, half * 0.34), belly, normal=n)
            p, n = on(P.tc, R, 0, -8, out=-0.08)
            ball(p, (rx * 0.42, ry * 0.2, half * 0.52), belly, normal=n)
        else:
            p, n = on(P.tc, R, 0, -8, out=-0.1)
            ball(p, (rx * (0.55 + 0.1 * M), ry * 0.22, half * 0.62), belly, normal=n)
    ra = LIMB[f]
    LA = ARM[f]
    P.shoulder, P.hand, P.foot, P.pose = {}, {}, {}, {}
    zs = base + SHOULDER_Z[f] * (top - base)
    t = (zs - P.tc[2]) / half
    sx = rx * (1 + 0.3 * M * t) * math.sqrt(max(0.05, 1 - t * t)) * 0.95
    for side in (1, -1):
        S = Vector((side * sx, 0, zs))
        P.shoulder[side] = S
        if arms:
            pose = (poses or pose_of)(side)
            P.pose[side] = pose
            if pose == 'hang':
                E = S + Vector((side * 0.18 * LA, -0.06 * LA, -0.5 * LA))
                H = E + Vector((side * 0.08 * LA, -0.2 * LA, -0.48 * LA))
            elif pose == 'ready':
                E = S + Vector((side * 0.6 * LA, 0, -0.3 * LA))
                H = E + Vector((side * 0.1 * LA, -0.35 * LA, -0.5 * LA))
            elif pose == 'flex':
                E = S + Vector((side * 0.78 * LA, 0, 0.0))
                H = E + Vector((side * 0.05 * LA, -0.12 * LA, 0.8 * LA))
            elif pose == 'hold':
                E = S + Vector((side * 0.3 * LA, -0.25 * LA, -0.55 * LA))
                H = Vector((side * 0.17 * rx, -ry * 0.95 - ra, zs - 0.42 * (zs - base)))
            else:
                E = S + Vector((side * 0.62 * LA, 0.1 * LA, -0.4 * LA))
                H = Vector((side * rx * 0.6, -ry * 0.8, base + 0.45 * (zs - base)))
            P.hand[side] = H
            ball(tuple(S), ra * (1.1 + 0.2 * M), limb)
            M1, M2 = S + (E - S) * 0.5 + Vector((0, 0, ra * 0.15 * M)), E + (H - E) * 0.5
            tube([tuple(p) for p in (S, M1, E, M2, H)],
                 [ra * 1.1, ra * (1 + 0.5 * M) * bicep, ra * (1 + 0.1 * M), ra * (0.9 + 0.25 * M), ra * 0.8], limb)
            ball(tuple(H), ra * 1.2 * hand_size, hand)
        rl = ra * 1.25 * thigh
        fr = min(ra * 1.45, 0.34)
        fh = fr * 0.7
        ax = side * (rx * 0.5 + 0.1 + 0.14 * M)
        if L > 0.05:
            hip = Vector((side * rx * 0.36, 0, base + half * 0.6))
            knee = Vector((side * (rx * 0.5 + 0.08 + 0.08 * M), -0.1, L * 0.5))
            ankle = Vector((ax, 0, fh * 1.3))
            tube([tuple(p) for p in (hip, hip.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.45), ankle)],
                 [rl * 0.85, rl * (1.1 + 0.4 * M), rl, rl * (1 + 0.2 * M), rl * 0.8], leg)
            fc = Vector((ax, -fr * 0.7, fh))
            fs = Vector((fr * 1.05, fr * 1.5, fh))
        else:
            fc = Vector((side * rx * 0.55, -ry * 0.55, 0.13))
            fs = Vector((0.22, 0.3, 0.13))
        ball(tuple(fc), tuple(fs), matte(foot))
        P.foot[side] = fc
        for j in range(toes):
            q = fc + Vector(((j - (toes - 1) / 2) * fs.x * 0.7, -fs.y * 0.85, fs.z * 0.05))
            ball(tuple(q), fs.x * 0.34, matte(foot))
    return P


# --- The sixteen partners -------------------------------------------------------------------------
def hommel():
    """A bumblebee. Grows: from a fuzzy ball with tiny wings to a broad-shouldered athlete with a third band,
    a fuzzy mane collar (5+), four big wings (5+) and longer antennae; at form 6 it flexes."""
    fuzz = mat('bee', rough=0.7, sheen=0.6)
    band = mat('beeBand', rough=0.6, sheen=0.4)
    stops = [(-0.7, -0.4), (-0.15, 0.15)] if FORM < 3 else [(-0.9, -0.7), (-0.5, -0.3), (-0.1, 0.1)]
    P = athlete(fuzz, torso=banded('bee', 'beeBand', stops), limb=band, hand=band, foot=band, head_w=1.08, toes=2)
    face(P, (22, 14, 0.17), (9, 0, 4))
    top = P.hc[2] + P.hr[2]
    for dx, dz, s in ((-0.13, 0.0, 0.17), (0.12, -0.02, 0.15), (0.0, 0.07, 0.19), (-0.26, -0.08, 0.12), (0.25, -0.09, 0.12)):
        if FORM >= 4 or abs(dx) < 0.2:
            ball((dx * P.u, -0.08 * P.u, top - 0.1 * P.u + dz * P.u), s * P.u, fuzz)
    A = P.u * grow(0.9, 2.0)
    for side in (1, -1):
        base = Vector((side * 0.2 * P.u, -0.2 * P.u, top - 0.15 * P.u))
        tip = base + Vector((side * 0.3 * A, -0.05 * A, 0.75 * A))
        tube([tuple(base), tuple(base + Vector((side * 0.12 * A, -0.1 * A, 0.4 * A))), tuple(tip)], [0.035 * P.u, 0.03 * P.u, 0.026 * P.u], band)
        ball(tuple(tip + Vector((0, 0, 0.06 * P.u))), 0.1 * P.u, mat('beeBand', rough=0.4, coat=0.5))
    wing = mat('wing', rough=0.15, sss=0, alpha=0.6)
    Lw = [0.6, 0.75, 0.95, 1.2, 1.4, 1.65][FORM - 1]
    for side in (1, -1):
        c = Vector((side * (P.rx * 0.35 + Lw * 0.42), P.ry * 0.9, P.top - 0.2 + Lw * 0.3))
        ball(tuple(c), (Lw * 0.5, 0.05, Lw * 0.3), wing, rot=(0, side * -28, side * 25))
        if FORM >= 5:
            c = Vector((side * (P.rx * 0.3 + Lw * 0.34), P.ry * 0.95, P.top - 0.55 + Lw * 0.15))
            ball(tuple(c), (Lw * 0.38, 0.05, Lw * 0.2), wing, rot=(0, side * 8, side * 22))
    if FORM >= 5:
        n = 7 if FORM == 5 else 9
        for i in range(n):
            q, m = on(P.hc, P.hr, -105 + 210 * i / (n - 1), -52, out=-0.02)
            ball(tuple(q), (0.2 + 0.04 * (FORM - 5)) * P.u, fuzz)


def mol():
    """A mole. Grows: from a round brown ball with tiny pink hands to an upright digger with a shoulder hump (4+),
    huge pink hands with long claws and a tuft of hair (4+); at form 6 it flexes."""
    fur = mat('mole', rough=0.75, sheen=0.7)
    pink = mat('molePink', rough=0.45)
    claw = mat('claw', rough=0.3, sss=0)
    P = athlete(fur, belly=mat('moleBelly', rough=0.75, sheen=0.5), hand=pink, foot=pink, hand_size=1.7, bicep=1.15, head_w=0.95)
    u = P.u
    p, n = on(P.hc, P.hr, 0, 26, out=0.05 * u)
    ball(p, (0.2 * u, 0.2 * u, 0.16 * u), mat('molePink', rough=0.35, coat=0.3), normal=n)
    for side in (1, -1):
        ball(p + n * 0.15 * u + Vector((side * 0.07 * u, 0, 0.01 * u)), (0.035 * u, 0.02 * u, 0.025 * u), mat('mouth', rough=0.4, sss=0), normal=n)
    face(P, (26, 46, 0.085), (8, 14, 3), blush_at=(38, 18, 0.1), thick=0.02)
    if FORM >= 4:
        top = P.hc[2] + P.hr[2]
        for dx, dz, s in ((-0.1, 0.0, 0.12), (0.1, 0.0, 0.12), (0.0, 0.06, 0.14)):
            drop((dx * u, 0.0, top - 0.1 * u + dz * u), s * u, (0.25 + 0.1 * (FORM - 4)) * u, fur, direction=(dx * 3, 0.2, 1))
        ball((0, P.ry * 0.45, P.top + 0.05), (P.rx * 0.85, P.ry * 0.8, 0.3 + 0.1 * P.M), fur)
    if FORM >= 3:
        hr = LIMB[FORM - 1] * 1.2 * 1.7
        C = grow(0.5, 1.0) * hr
        for side in (1, -1):
            H = P.hand[side]
            for a in (-42, -14, 14, 42):
                d = Vector((math.sin(math.radians(a)) * 0.9, -0.7, 0.7))
                drop(tuple(H + d.normalized() * hr * 0.85), 0.2 * hr, C, claw, direction=tuple(d))


def kikker():
    """A frog. Grows: from a green ball with big eye bulges to an upright athlete on huge thighs with big webbed feet,
    darker adult stripes and spots (4+), a segmented belly that reads as abs (5+); at form 6 it flexes."""
    body = mat('frog', rough=0.35, coat=0.35)
    spot = mat('frogSpot', rough=0.35, coat=0.35)
    P = athlete(body, foot=mat('frog', rough=0.5, coat=0.1), belly=mat('frogBelly', rough=0.5, coat=0.2), head_w=1.28, head_d=0.82, thigh=1.35, toes=3, leg_scale=0.9)
    u, hx, hy, hz = P.u, *P.hr
    g = grow(0.34, 0.4) * u
    for side in (1, -1):
        bc, br = (side * 0.5 * hx, -0.1 * hy, P.hc[2] + hz * 0.7), (g, g * 0.95, g)
        ball(bc, br, body)
        eye(bc, br, side * 6, 8, 0.2 * u)
        blush(P.hc, P.hr, side * 52, -8, 0.13 * u)
    smile(P.hc, P.hr, 34, 4, 8, thick=0.024 * u)
    if FORM >= 4:
        for az, el, s in [(0, 72, 0.12), (-35, 62, 0.1), (35, 62, 0.1), (60, 40, 0.08), (-60, 40, 0.08)][:FORM - 1]:
            q, m = on(P.hc, P.hr, az, el, out=-0.02)
            ball(q, (s * u, s * u * 0.25, s * u), spot, normal=m)
        for side in (1, -1):
            pts = [tuple(on(P.tc, (P.rx, P.ry, P.half), side * 82, el, out=-0.01)[0]) for el in (45, 15, -15, -40)]
            tube(pts, [0.04 * u] * 4, spot)
    if FORM >= 5:
        R = (P.rx, P.ry, P.half)
        for el, w in ((-6, 22), (-22, 20), (-38, 16)):
            pts = [tuple(on(P.tc, R, az, el - 0.0004 * az * az, out=0.12 * P.ry)[0]) for az in (-w, 0, w)]
            tube(pts, [0.02 * u] * 3, spot)
        tube([tuple(on(P.tc, R, 0, 10, out=0.12 * P.ry)[0]), tuple(on(P.tc, R, 0, -48, out=0.12 * P.ry)[0])], [0.02 * u] * 2, spot)


def flipper(P, side, pose, material, feather=None, feathers=0, width=1.0):
    """A wing or flipper used as an arm: a broad rounded paddle from the shoulder, optionally with feather tips.
    pose: hang, ready, spread (out and up), up (a flexed flipper), hip."""
    f = FORM - 1
    S = P.shoulder[side]
    ra = LIMB[f]
    reach = ARM[f] * 1.1
    d = Vector({'hang': (side * 0.2, 0, -1), 'ready': (side * 0.7, 0, -0.75), 'spread': (side, 0.1, 0.5),
                'up': (side * 0.5, 0, 1), 'hip': (side * 0.4, -0.1, -1)}[pose]).normalized()
    ball(tuple(S), ra * (1.2 + 0.3 * P.M), material)
    paddle(tuple(S), tuple(d), reach / 1.8, ra * (1.5 + 0.7 * P.M) * width, ra * 0.8, material)
    tip = S + d * reach * 0.95
    side_axis = Vector((0, 1, 0)).cross(d).normalized() if abs(d.y) < 0.9 else Vector((1, 0, 0))
    for j in range(feathers):
        k = (j - (feathers - 1) / 2) / max(1, feathers - 1)
        fd = (d + side_axis * k * 0.7 * side).normalized()
        drop(tuple(tip - d * reach * 0.12 + side_axis * k * ra * 1.2 * side), ra * 0.55, reach * 0.4, feather or material, direction=tuple(fd), flat=0.5)


def uil():
    """An owl. Grows: from a round blue ball to a tall owl on visible legs with wings that act as arms (primary feathers
    from form 3), chest chevrons (4+), bigger ear tufts and a second tuft (6); at form 6 one wing is spread wide."""
    body = mat('owl', rough=0.7, sheen=0.5)
    wing = mat('owlWing', rough=0.7, sheen=0.5)
    orange = mat('beak', rough=0.4)
    P = athlete(body, belly=mat('owlBelly', rough=0.7, sheen=0.4), arms=False, leg=orange, foot=orange, toes=3, head_w=1.12, torso_w=0.9, thigh=0.75, leg_scale=0.9)
    u = P.u
    for side in (1, -1):
        p, n = on(P.hc, P.hr, side * 20, 20, out=-0.08 * u)
        ball(p, (0.37 * u, 0.13 * u, 0.35 * u), mat('owlFace', rough=0.7, sheen=0.4), normal=n)
        eye(P.hc, P.hr, side * 20, 20, 0.19 * u, iris='amber', out=0.06 * u)
    p, n = on(P.hc, P.hr, 0, 4)
    drop(tuple(p), 0.08 * u, 0.2 * u, mat('beak', rough=0.35, coat=0.3), direction=(0, -0.6, -1))
    top = P.hc[2] + P.hr[2]
    T_ = u * grow(0.35, 0.85)
    for side in (1, -1):
        drop((side * 0.45 * u, 0.05 * u, top - 0.15 * u), 0.17 * u, T_, body, direction=(side * 0.55, 0.1, 1))
        if FORM == 6:
            drop((side * 0.3 * u, 0.05 * u, top - 0.1 * u), 0.11 * u, T_ * 0.6, body, direction=(side * 0.3, 0.15, 1))
        pose = 'spread' if FORM == 6 and side < 0 else 'ready' if FORM == 5 else 'hang'
        flipper(P, side, pose, wing, feathers=0 if FORM < 3 else min(5, FORM), width=0.8)
    if FORM >= 4:
        R = (P.rx, P.ry, P.half)
        for row in range(FORM - 3):
            for k in range(2 * row + 3):
                az = (k - (2 * row + 2) / 2) * 13
                q, m = on(P.tc, R, az, 14 - row * 17, out=0.1 * P.ry)
                drop(tuple(q), 0.045 * P.rx, 0.14 * P.rx, wing, direction=(0, -0.3, -1), flat=0.5)


def egel():
    """A hedgehog. Grows: from a round cream ball with a few small spikes to an upright athlete whose spike mane
    covers head and back and grows much longer and denser; at form 6 it flexes."""
    body = mat('hedgehog', rough=0.7, sheen=0.5)
    paw = mat('paw', rough=0.5)
    spike = mat('spike', rough=0.6, sheen=0.3)
    P = athlete(body, belly=mat('hedgehogBelly', rough=0.7, sheen=0.5), hand=paw, foot=paw, head_w=1.1)
    u = P.u
    face(P, (27, 28, 0.12), (9, -8, 3), blush_at=(44, 8, 0.11), out=0.0)
    p, nrm = on(P.hc, P.hr, 0, 8)
    drop(tuple(p - nrm * 0.12 * u), 0.21 * u, 0.36 * u, mat('hedgeSnout', rough=0.55, sheen=0.3), direction=(0, -1, -0.1))
    ball(tuple(p + Vector((0, -0.3 * u, -0.04 * u))), (0.11 * u, 0.09 * u, 0.085 * u), mat('nose', rough=0.25, coat=0.6, sss=0))
    L, rad = grow(0.2, 0.75) * u, grow(0.09, 0.17) * u
    for az, el in spread(int(grow(150, 420))):
        if el > 42 or (abs(az) > 80 and el > -20):
            q, m = on(P.hc, P.hr, az, el, out=-0.05 * u)
            drop(tuple(q), rad, L, spike, direction=tuple(m + Vector((0, 0.45, 0.15))))
    R = (P.rx, P.ry, P.half)
    for az, el in spread(int(grow(70, 360))):
        if abs(az) > 70 and el > -35:
            q, m = on(P.tc, R, az, el, out=-0.05)
            drop(tuple(q), rad * 0.9, L * 0.85, spike, direction=tuple(m + Vector((0, 0.5, -0.1))))


def slak():
    """A snail. Grows: from a head on a small foot with a tiny shell to a tall, strong body with a muscular neck, chest and
    foot, taller eye stalks and a huge shell with studs along its edge (4+) and rings of studs on its side (5+)."""
    f = FORM - 1
    body = mat('snail', rough=0.35, coat=0.4)
    Lf, Wf = [0.8, 1.0, 1.2, 1.4, 1.5, 1.6][f], [0.45, 0.5, 0.55, 0.62, 0.7, 0.78][f]
    ball((0, 0.35, 0.26), (Wf, Lf, 0.27 + 0.05 * f / 5), body)
    Hh, hr, rc = [0.9, 1.2, 1.65, 2.05, 2.35, 2.6][f], [0.8, 0.72, 0.64, 0.58, 0.56, 0.56][f], [0.3, 0.32, 0.36, 0.46, 0.56, 0.62][f]
    yh = -0.45
    tube([(0, -0.2, 0.3), (0, yh - 0.05, (Hh - hr) * 0.5 + 0.2), (0, yh, Hh - hr * 0.4)], [rc * 1.05, rc, rc * 0.85], body)
    P = SimpleNamespace(hc=(0, yh, Hh), hr=(hr, hr * 0.92, hr), u=hr / 0.85)
    ball(P.hc, P.hr, body)
    if FORM >= 4:
        ball((0, yh - 0.25, Hh * 0.5), (rc * 1.15, rc * 0.85, 0.5 * Hh * 0.45), body)
    if FORM >= 5:
        for side in (1, -1):
            ball((side * rc * 0.95, yh - 0.2, Hh * 0.62), 0.26 * rc / 0.46, body)
    Ls, er = [0.4, 0.6, 0.8, 1.0, 1.2, 1.35][f], [0.28, 0.26, 0.22, 0.2, 0.19, 0.18][f]
    for side in (1, -1):
        base = Vector((side * 0.14, yh - 0.02, Hh + hr * 0.82))
        tube([tuple(base), tuple(base + Vector((side * 0.1, -0.04, Ls * 0.5))), tuple(base + Vector((side * 0.16, -0.06, Ls)))], [0.08, 0.07, 0.065], body)
        ec = base + Vector((side * 0.19, -0.08, Ls + er * 0.6))
        ball(tuple(ec), er, mat('sclera', rough=0.3, coat=0.5, sss=0))
        eye(tuple(ec), (er, er, er), side * 6, 2, er * 0.65)
        blush(P.hc, P.hr, side * 42, -8, 0.1 * P.u)
    smile(P.hc, P.hr, 13, -14, 4, thick=0.022 * P.u)
    Sr = [0.55, 0.72, 0.95, 1.2, 1.4, 1.62][f]
    rx, ry = 0.52 * Sr, Sr
    sc = Vector((0, 0.35 + 0.35 * Sr, 0.28 + Sr * 0.9))
    ball(tuple(sc), (rx, ry, ry), mat('shell', rough=0.4, coat=0.5))
    line = mat('shellLine', rough=0.4, coat=0.5)
    turns = grow(0.32, 0.45)
    for side in (1, -1):
        pts = []
        for k in range(41):
            r = (0.87 - 0.77 * k / 40) * Sr
            x = rx * math.sqrt(max(0.0, 1 - (r / ry) ** 2)) + 0.012
            pts.append((side * x, sc.y + r * math.sin(k * turns), sc.z + r * math.cos(k * turns)))
        tube(pts, [0.06 * Sr] * len(pts), line)
    if FORM >= 4:
        n = 2 * (FORM - 3) + 1
        for i in range(n):
            a = math.radians(10 + 100 * i / max(1, n - 1))
            ball(tuple(sc + Vector((0, ry * math.sin(a), ry * math.cos(a))) * 0.97), 0.09 * Sr / 0.9, line)
    if FORM >= 5:
        for side in (1, -1):
            for k in range(FORM + 1):
                a = math.radians(30 + 60 * k)
                r = Sr * 0.62
                ball((side * rx * 0.88, sc.y + r * math.sin(a), sc.z + r * math.cos(a)), 0.11 * Sr, line)


def axolotl():
    """An axolotl. Grows: from a pink ball with tiny gills to an upright athlete with a big gill mane (more and longer
    stalks every form), and a long tail that curls round beside its legs; at form 6 it flexes."""
    body = mat('axo', rough=0.3, coat=0.5)
    gill = mat('gill', rough=0.4, coat=0.3)
    P = athlete(body, foot=mat('axo', rough=0.5, coat=0.1), belly=mat('axoBelly', rough=0.4, coat=0.3), head_w=1.32, head_d=0.82, toes=3, leg_scale=0.85)
    u, hx, hy, hz = P.u, *P.hr
    face(P, (38, 14, 0.13), (24, -6, 5), blush_at=(54, -2, 0.1))
    G = grow(0.8, 2.3) * u
    stalks = [(0.8, 0.5), (0.3, 0.58), (-0.2, 0.46), (1.3, 0.4), (-0.6, 0.38), (1.7, 0.34)][:min(6, 2 + FORM)]
    for side in (1, -1):
        for i, (up, length) in enumerate(stalks):
            base = Vector((side * hx * 0.82, P.hc[1] + 0.12 * u, P.hc[2] + hz * 0.25 + 0.1 * u * (1 - i % 3)))
            d = Vector((side, 0.3, up)).normalized()
            drop(tuple(base), 0.075 * u, length * G, gill, direction=tuple(d))
            for j in ((0.45, 0.7, 0.92) if FORM < 4 else (0.35, 0.52, 0.68, 0.84, 0.98)):
                ball(tuple(base + d * length * G * j + Vector((0, 0, 0.05 * u))), 0.065 * u, gill)
    Tl = grow(0.6, 1.5)
    t0 = Vector((P.rx * 0.3, P.ry * 0.8, P.base + 0.3))
    pts = [t0, Vector((P.rx + 0.5 * Tl, P.ry + 0.5 * Tl, 0.3)), Vector((P.rx + 1.0 * Tl, P.ry * 0.2, 0.22)), Vector((P.rx + 1.1 * Tl, -P.ry * 0.4, 0.15))]
    tube([tuple(q) for q in pts], [P.rx * 0.45, P.rx * 0.3, 0.1, 0.04], body)


def on_tilted(center, radii, rot, direction, out=0.0):
    """Point and normal on an ellipsoid turned by the Euler angles `rot`, seen from a world `direction`."""
    m = Euler(rot).to_matrix()
    d = m.inverted() @ Vector(direction).normalized()
    r = Vector(radii)
    n = Vector((d.x / r.x, d.y / r.y, d.z / r.z)).normalized()
    return Vector(center) + m @ (Vector((d.x * r.x, d.y * r.y, d.z * r.z)) + n * out), m @ n


def zeehond():
    """A seal pup. Grows: from a head on a small lying body to a seal that rises up on straight front flippers with its
    chest out, a thick neck, an adult spotted coat and whiskers (4+); at form 6 one flipper flexes."""
    f = FORM - 1
    body = mat('seal', rough=0.55, sheen=0.4)
    spotm = mat('sealSpot', rough=0.5)
    pale = mat('sealMuzzle', rough=0.55, sheen=0.4)
    pitch = math.radians([0, 6, 20, 38, 50, 56][f])
    W, Lb, Hb = [0.65, 0.72, 0.78, 0.88, 0.98, 1.06][f], [0.8, 0.95, 1.1, 1.25, 1.35, 1.45][f], [0.45, 0.5, 0.55, 0.65, 0.72, 0.78][f]
    rot = (-pitch, 0, 0)
    C = Vector((0, 0.3, math.hypot(Lb * math.sin(pitch), Hb * math.cos(pitch))))
    ball(tuple(C), (W, Lb, Hb), body).rotation_euler = rot
    fdir = Vector((0, -math.cos(pitch), math.sin(pitch)))
    hz = [1.0, 0.92, 0.84, 0.78, 0.76, 0.76][f]
    hc = C + fdir * Lb * 0.85 + Vector((0, 0, hz * 0.6))
    P = SimpleNamespace(hc=tuple(hc), hr=(hz * 0.95, hz * 0.9, hz), u=hz / 0.85)
    ball(P.hc, P.hr, body)
    if FORM >= 4:
        ball(tuple(C + fdir * Lb * 0.95 - Vector((0, 0, 0.1))), (W * 0.85, W * 0.8, hz * 0.8), body)
        p, n = on_tilted(C, (W, Lb, Hb), rot, (0, -1, 0.1), out=-0.1)
        ball(tuple(p), (W * 0.6, 0.2, Hb * 0.75), pale, normal=n)
    face(P, (27, 14, 0.17), (9, -12, 3), blush_at=(46, -4, 0.11))
    p, n = on(P.hc, P.hr, 0, -12, out=-0.06 * P.u)
    ball(p, (0.27 * P.u, 0.15 * P.u, 0.18 * P.u), pale, normal=n)
    ball(tuple(p + n * 0.13 * P.u + Vector((0, 0, 0.07 * P.u))), (0.09 * P.u, 0.06 * P.u, 0.06 * P.u), mat('nose', rough=0.25, coat=0.6, sss=0))
    for side in (1, -1):
        if FORM >= 4:
            for dz in (0.03, -0.04):
                start = p + n * 0.1 * P.u + Vector((side * 0.17 * P.u, 0, dz * P.u))
                tube([tuple(start), tuple(start + Vector((side * 0.2, -0.1, dz * 2 + 0.01)) * P.u), tuple(start + Vector((side * 0.38, -0.12, dz * 3 - 0.04)) * P.u)],
                     [0.011 * P.u, 0.009 * P.u, 0.006 * P.u], spotm)
    for az, el, s in [(-60, 30, 0.07), (70, 10, 0.06), (120, 40, 0.06), (-110, 15, 0.05)][:1 + FORM // 2]:
        q, m = on(P.hc, P.hr, az, el, out=-0.01)
        ball(q, (s * P.u, s * P.u * 0.25, s * P.u), spotm, normal=m)
    if FORM >= 4:
        dirs = [(0.9, -0.3, 0.4), (-0.9, -0.3, 0.4), (0.7, 0.2, 0.7), (-0.7, 0.2, 0.7), (0.95, 0.3, 0.1), (-0.95, 0.3, 0.1), (0.5, -0.7, 0.5), (-0.5, -0.7, 0.5)]
        for d in dirs[:2 * (FORM - 3)]:
            q, m = on_tilted(C, (W, Lb, Hb), rot, d, out=-0.02)
            ball(tuple(q), (0.2, 0.04, 0.16), spotm, normal=m)
    Pw = grow(0.85, 1.4)
    for side in (1, -1):
        S = C + fdir * Lb * 0.55 + Vector((side * W * 0.85, 0, -Hb * 0.2))
        ra = grow(0.1, 0.3)
        if FORM <= 2:
            paddle((side * 0.6, -0.2 - 0.1 * f, 0.22), (side * 0.9, -0.5, -0.3), 0.3 * Pw, 0.18 * Pw, 0.08, body)
        elif FORM == 6 and side < 0:
            E = S + Vector((side * 0.85, -0.1, 0.2))
            H = E + Vector((side * 0.12, -0.15, 0.8))
            tube([tuple(S), tuple(E)], [ra * 1.1, ra], body)
            bulge(S + (E - S) * 0.15, S + (E - S) * 0.85, ra * 1.5, body, shift=(0, 0, ra * 0.3))
            tube([tuple(E), tuple(H)], [ra * 0.95, ra * 0.8], body)
            paddle(tuple(H), (side * 0.15, 0, 1), 0.35 * Pw, 0.3 * Pw, 0.09, body)
        else:
            E = Vector((side * (W + 0.2), S.y - 0.12, S.z * 0.5))
            H = Vector((side * (W + 0.3), S.y - 0.35, 0.1))
            ball(tuple(S), ra * 1.3, body)
            tube([tuple(S), tuple(E), tuple(H)], [ra * 1.1, ra, ra * 0.9], body)
            if FORM >= 4:
                bulge(S, E, ra * (1 + 0.4 * (FORM - 3) / 3), body)
            paddle(tuple(H), (side * 0.3, -1, 0), 0.2 * Pw, 0.2 * Pw, 0.07, body)
        paddle((side * 0.25, C.y + Lb * math.cos(pitch) * 0.9, 0.12), (side * 0.6, 1, 0.0), 0.4 * Pw, 0.2 * Pw, 0.07, body)


def pinguin():
    """A penguin. Grows: from a dark ball with a white face to a tall emperor with a broad white chest, a yellow neck
    patch (4+), a yellow crest that grows long (4+) and flippers that gain size; at form 6 one flipper flexes."""
    body = mat('peng', rough=0.5, sheen=0.3)
    white = mat('pengWhite', rough=0.6, sheen=0.3)
    orange = mat('beak', rough=0.4)
    crest = mat('crest', rough=0.6, sheen=0.5)
    P = athlete(body, belly=white, arms=False, leg=orange, foot=orange, toes=3, head_w=1.12, torso_d=0.88, torso_w=0.85, thigh=0.7, leg_scale=0.6, sink=0.62)
    u = P.u
    for side in (1, -1):
        p, n = on(P.hc, P.hr, side * 20, -14, out=-0.07 * u)
        ball(p, (0.2 * u, 0.09 * u, 0.2 * u), white, normal=n)
        eye(P.hc, P.hr, side * 18, 22, 0.12 * u * 1.15, out=0.03 * u, brow=False)
        blush(P.hc, P.hr, side * 36, 6, 0.1 * u)
        pose = 'up' if FORM == 6 and side < 0 else 'hip' if FORM == 6 else 'ready' if FORM == 5 else 'hang'
        flipper(P, side, pose, body, width=0.7)
        if FORM >= 4:
            q, m = on(P.hc, P.hr, side * 46, 14, out=-0.04 * u)
            ball(tuple(q), (0.2 * u, 0.07 * u, 0.32 * u), crest, normal=m)
            for j in range(FORM - 2):
                q, m = on(P.hc, P.hr, side * 40, 36, out=-0.03 * u)
                drop(tuple(q + Vector((side * 0.04 * j, 0.03 * j, 0.02 * j)) * u), 0.05 * u, (0.25 + 0.08 * (FORM - 4) + 0.04 * j) * u, crest,
                     direction=(side, 0.4 + 0.15 * j, 0.5 - 0.1 * j))
    p, n = on(P.hc, P.hr, 0, 6)
    drop(tuple(p), 0.09 * u, 0.22 * u, mat('beak', rough=0.35, coat=0.3), direction=(0, -1, -0.25))
    if FORM >= 4:
        p, n = on(P.tc, (P.rx, P.ry, P.half), 0, 58, out=0.0)
        ball(p, (P.rx * 0.6, P.ry * 0.16, P.half * 0.2), crest, normal=n)


def schildpad():
    """A turtle. Grows: from a green ball with a tiny shell to an upright athlete with a domed shell on its back, a ridge of
    round studs along the shell (4+), bigger plates and a cream belly; at form 6 it flexes."""
    skin = mat('turtle', rough=0.45, coat=0.3)
    P = athlete(skin, foot=mat('turtle', rough=0.5, coat=0.1), belly=mat('tBelly', rough=0.5, coat=0.2), head_w=1.0, toes=3, leg_scale=0.9)
    u = P.u
    face(P, (30, 14, 0.12), (14, -10, 4), blush_at=(48, -4, 0.09))
    H0 = P.top - P.base
    sr = (P.rx * 1.4, 0.6 + 0.4 * P.M + 0.1 * u, H0 * (0.62 + 0.12 * F))
    sc = (0, P.ry * 0.9 + sr[1] * 0.6, P.base + H0 * 0.55)
    shell = mat('tShell', rough=0.4, coat=0.5)
    ball(sc, sr, shell)
    ball((0, sc[1], P.base + H0 * 0.55 - sr[2] * 0.75), (sr[0] * 1.06, sr[1] * 1.06, 0.14), mat('tRim', rough=0.4, coat=0.5))
    plate = mat('tPlate', rough=0.4, coat=0.5)
    s = grow(0.2, 0.3) * H0
    for az, el in [(90, 62), (-90, 62), (110, 28), (-110, 28), (150, 44), (-150, 44), (0, 80), (180, 80), (85, 10), (-85, 10)]:
        p, n = on(sc, sr, az, el, out=-0.03)
        ball(p, (s, s * 0.22, s * 0.85), plate, normal=n)
    if FORM >= 4:
        n_k = 2 * (FORM - 3) + 1
        for i in range(n_k):
            ang = 40 + 100 * i / max(1, n_k - 1)
            q, m = on(sc, sr, 180 if ang > 90 else 0, 180 - ang if ang > 90 else ang, out=-0.02)
            ball(tuple(q + m * 0.05), (0.1 + 0.03 * (FORM - 4)) * H0 / 1.5, mat('tRim', rough=0.4, coat=0.5))
    drop((0, P.ry + 0.9 * sr[1], P.base + 0.15), 0.1 * u, 0.3 * u, skin, direction=(0, 1, -0.3))


def konijn():
    """A rabbit. Grows: from a round taupe ball with small ears to a tall, athletic rabbit on long legs with huge haunches and
    pale socks (4+), tall ears with dark tips (4+) that stand more alert; at form 6 it flexes."""
    body = mat('bunny', rough=0.75, sheen=0.6)
    sock = mat('bunnyBelly' if FORM >= 4 else 'bunny', rough=0.75, sheen=0.6)
    P = athlete(body, belly=mat('bunnyBelly', rough=0.75, sheen=0.6), foot=sock, thigh=1.5, leg_scale=1.2, head_w=0.96)
    u = P.u
    face(P, (24, 14, 0.13), (8, -4, 3), blush_at=(42, 0, 0.11))
    E = grow(0.8, 1.9)
    top = P.hc[2] + P.hr[2]
    for side in (1, -1):
        base = Vector((side * 0.3 * u, 0.05 * u, top - 0.2 * u))
        up = Vector((side * (0.25 + 0.15 * F), 0.12, 1)).normalized()
        ear = ball(tuple(base + up * 0.45 * u * E), (0.2 * u, 0.09 * u, 0.5 * u * E), body)
        ear.rotation_euler = along(up)
        inner = ball(tuple(base + up * 0.48 * u * E + Vector((0, -0.07 * u, 0))), (0.12 * u, 0.04 * u, 0.38 * u * E), mat('bunnyEar', rough=0.6))
        inner.rotation_euler = along(up)
        if FORM >= 4:
            tip = ball(tuple(base + up * 0.92 * u * E), (0.16 * u, 0.08 * u, 0.14 * u * E), mat('bunnyTip', rough=0.7, sheen=0.5))
            tip.rotation_euler = along(up)
    p, n = on(P.hc, P.hr, 0, 8, out=0.02 * u)
    ball(p, (0.07 * u, 0.05 * u, 0.05 * u), mat('bunnyEar', rough=0.4, coat=0.4), normal=n)
    ball((0, P.ry + 0.1, P.base + 0.3), 0.2 + 0.1 * F, mat('tail', rough=0.9, sheen=0.8))


def wasbeer():
    """A raccoon. Grows: from a grey ball with a dark mask to an upright, muscular raccoon with a wider mask, round ears, pale
    brow patches and a dark nose stripe (4+) and a huge ringed tail that sweeps out in a visible S-curve beside it; at form 6 it flexes."""
    body = mat('racc', rough=0.75, sheen=0.6)
    mask = mat('raccMask', rough=0.6, sheen=0.4)
    light = mat('raccLight', rough=0.7, sheen=0.5)
    P = athlete(body, belly=light, hand=mask, foot=mask, bicep=1.1, head_w=1.05)
    u = P.u
    M = grow(1.0, 1.25)
    for side in (1, -1):
        p, n = on(P.hc, P.hr, side * 24, 22, out=-0.06 * u)
        ball(p, (0.28 * u * M, 0.12 * u, 0.18 * u * M), mask, normal=n)
        eye(P.hc, P.hr, side * 24, 22, 0.12 * u, out=0.04 * u, brow=False)
        top = P.hc[2] + P.hr[2]
        d = (side * 0.35, 0, 1)
        ear = ball((side * 0.52 * u, 0.04 * u, top - 0.18 * u), (0.22 * u, 0.13 * u, 0.2 * u), body)
        ear.rotation_euler = along(d)
        inner = ball((side * 0.53 * u, -0.07 * u, top - 0.18 * u), (0.13 * u, 0.06 * u, 0.12 * u), mat('raccInner', rough=0.7, sheen=0.4))
        inner.rotation_euler = along(d)
        if FORM >= 4:
            q, m = on(P.hc, P.hr, side * 24, 42, out=-0.02 * u)
            ball(q, (0.14 * u, 0.05 * u, 0.05 * u), light, normal=m)
    p, n = on(P.hc, P.hr, 0, 4, out=-0.06 * u)
    ball(p, (0.3 * u, 0.16 * u, 0.2 * u), light, normal=n)
    ball(tuple(p + n * 0.15 * u + Vector((0, 0, 0.06 * u))), (0.08 * u, 0.06 * u, 0.06 * u), mat('nose', rough=0.25, coat=0.6, sss=0))
    smile(P.hc, P.hr, 8, -4, 3, out=0.08 * u, thick=0.022 * u)
    if FORM >= 4:
        q, m = on(P.hc, P.hr, 0, 48, out=-0.02 * u)
        ball(q, (0.07 * u, 0.04 * u, 0.26 * u), mask, normal=m)
    Tl = grow(0.8, 1.7)
    H0 = P.top - P.base
    c = [Vector(q) for q in ((P.rx * 0.4, P.ry * 0.9, P.base + 0.3), (P.rx + 1.3 * Tl, P.ry + 0.3, 0.4 * Tl + 0.1),
                             (P.rx + 0.1 * Tl, P.ry + 0.6, P.base + H0 * 0.7), (P.rx + 1.0 * Tl, P.ry + 0.4, P.base + H0 * 0.75 + 0.6 * Tl))]
    rings = 8 + 2 * FORM
    for i in range(rings):
        t = i / (rings - 1)
        pos = sum((w * q for w, q in zip(((1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3), c)), Vector())
        ball(tuple(pos), (0.3 - 0.1 * t) * Tl * (0.8 + 0.2 * F) * P.rx / 0.7, mask if i % 2 else body)


def lieveheersbeestje():
    """A ladybird. Grows: from a red ball with a black face to an upright athlete on two legs with arms, a red shell that wraps
    its back and sides, gets bigger and gains dots, long antennae, translucent wings (5+) that open wide at form 6; at form 6 it flexes."""
    red = mat('bug', rough=0.3, coat=0.7)
    dark = mat('bugDark', rough=0.4, coat=0.4)
    P = athlete(dark, head=red, torso=red, belly=dark, foot=mat('bugFoot', rough=0.7), head_w=1.02, toes=2)
    u, hx, hy, hz = P.u, *P.hr
    p, n = on(P.hc, P.hr, 0, -6, out=-0.1 * u)
    ball(p, (hx * 0.68, hy * 0.14, hz * 0.52), dark, normal=n)
    for side in (1, -1):
        eye(P.hc, P.hr, side * 26, 4, 0.15 * u, iris='sclera', out=0.03 * u, brow=False)
        blush(P.hc, P.hr, side * 52, -8, 0.09 * u)
    smile(P.hc, P.hr, 14, -14, 4, key='blush', out=0.01 * u, thick=0.022 * u)
    top = P.hc[2] + hz
    A = u * grow(0.9, 1.9)
    for side in (1, -1):
        base = Vector((side * 0.2 * u, -0.1 * u, top - 0.1 * u))
        tip = base + Vector((side * 0.3 * A, -0.05 * A, 0.7 * A))
        tube([tuple(base), tuple(base + Vector((side * 0.12 * A, -0.08 * A, 0.4 * A))), tuple(tip)], [0.03 * u, 0.026 * u, 0.022 * u], dark)
        ball(tuple(tip + Vector((0, 0, 0.04 * u))), 0.07 * u, dark)
        if FORM >= 3:
            q, m = on(P.hc, P.hr, side * 34, 64, out=-0.02 * u)
            ball(q, (0.11 * u, 0.03 * u, 0.11 * u), dark, normal=m)
    H0 = P.top - P.base
    sr = (P.rx * 1.3, P.ry * 0.95 + 0.25, H0 * (0.62 + 0.08 * F))
    sc = (0, P.ry * 0.55 + 0.1, P.base + H0 * 0.55)
    ball(sc, sr, red)
    dots = [(75, 35, 0.2), (-75, 35, 0.2), (105, 10, 0.18), (-105, 10, 0.18), (130, 45, 0.16), (-130, 45, 0.16),
            (88, 62, 0.14), (-88, 62, 0.14), (58, 6, 0.12), (-58, 6, 0.12), (150, 25, 0.13), (-150, 25, 0.13)]
    for az, el, s in dots[:min(12, 2 * FORM)]:
        q, m = on(sc, sr, az, el, out=-0.02)
        ball(q, (s * H0 * 0.55, 0.03, s * H0 * 0.55), dark, normal=m)
        if abs(az) < 100 and el > 5:
            q, m = on(P.tc, (P.rx, P.ry, P.half), az * 0.75, el * 0.8 - 10, out=-0.02)
            ball(q, (s * P.rx * 0.5, 0.03, s * P.rx * 0.5), dark, normal=m)
    if FORM >= 5:
        wing = mat('wing', rough=0.15, sss=0, alpha=0.6)
        Lw = 0.9 if FORM == 5 else 1.45
        for side in (1, -1):
            ball((side * (P.rx + 0.3 * Lw), sc[1] + sr[1] * 0.9, P.top - 0.1 + 0.2 * Lw), (Lw * 0.45, 0.05, Lw * 0.28), wing,
                 rot=(0, side * (-15 if FORM == 5 else -35), side * (35 if FORM == 5 else 20)))


def octopus():
    """An octopus. Grows: from a purple ball on stubby arm tips to a tall mantle on thick, curling arms with suckers;
    at form 5 one front arm and at form 6 both front arms are raised in a flex."""
    f = FORM - 1
    body = mat('octo', rough=0.35, coat=0.4)
    light = mat('octoLight', rough=0.4, coat=0.3)
    hz = HEAD[f] * T / 2
    hx = hz * [1.0, 0.98, 0.92, 0.82, 0.78, 0.76][f]
    P = SimpleNamespace(hc=(0, 0, T - hz), hr=(hx, hx * 0.95, hz), u=hz / 0.85)
    ball(P.hc, P.hr, body)
    z0 = T - 2 * hz
    ra, Lr = [0.14, 0.15, 0.18, 0.21, 0.24, 0.27][f], [0.3, 0.5, 0.75, 1.0, 1.15, 1.3][f]
    ball((0, 0, z0 + 0.25), (hx * 0.85, hx * 0.8, 0.35), body)
    skip = {5: (7,), 6: (7, 0)}.get(FORM, ())
    reach = 0.6 * hx + 1.2 * Lr + 0.3
    for k in range(8):
        if k in skip:
            continue
        a = math.radians(k * 45 + 22.5)
        cs, sn = math.sin(a), -math.cos(a)
        wig = 0.3 * Lr * (1 if k % 2 else -1)
        pts, radii = [], []
        for i in range(10):
            t = i / 9
            r = 0.5 * hx + (reach - 0.5 * hx) * t ** 0.85
            rad = ra * (1.2 - 1.05 * t ** 0.8)
            curl = max(0.0, (t - 0.75) / 0.25) ** 2
            z = max(rad * 0.9, (z0 + 0.25) * (1 - t) ** 1.5) + curl * (0.35 + 0.5 * Lr if FORM >= 4 else 0.15)
            r -= curl * 0.15 * Lr
            lat = wig * math.sin(t * math.pi * 1.4)
            pts.append((r * cs - lat * sn, (r * sn + lat * cs) * 0.7, z))
            radii.append(rad)
        tube(pts, radii, body)
        for i in range(4, min(9, 3 + FORM)) if FORM >= 3 else ():
            ball((pts[i][0], pts[i][1], pts[i][2] + radii[i] * 0.85), radii[i] * 0.35, light)
    for side in (-1, 1):
        if (side < 0 and FORM >= 5) or (side > 0 and FORM >= 6):
            # A tentacle that arcs out and up from the side of the mantle, tapers and ends in a spiral that curls outward and down.
            big = side < 0 and FORM == 6
            H = (0.3 + 0.5 * Lr) * (1.15 if big else 0.85 if FORM == 6 else 1.0)
            rs = (0.38 + 0.14 * Lr) * (1.0 if big else 0.85)
            turns = 1.5 if big or FORM == 5 else 1.3
            S = Vector((side * hx * 0.7, 0.0, z0 + 0.35))
            pts, radii = [], []
            for i in range(9):
                t = i / 8
                pts.append(Vector((side * (0.7 * hx + 0.9 * H * t), 0.0, z0 + 0.35 + H * t ** 2.0 * 1.3)))
                radii.append(ra * (1.6 * (1 - 0.75 * t) ** 1.2 + 0.1))
            E = pts[-1]
            C = E + Vector((side * rs, 0, 0))
            for j in range(1, 14):
                u = j / 13
                phi = turns * 2 * math.pi * u
                r = rs * (1 - 0.75 * u)
                pts.append(Vector((C.x - side * r * math.cos(phi), 0.0, C.z + r * math.sin(phi))))
                radii.append(max(0.02, ra * 0.5 * (1 - u) + 0.02))
            tube([tuple(q) for q in pts], radii, body)
            for j in range(15, len(pts) - 1, 2):
                inner = (C - pts[j]).normalized()
                ball(tuple(pts[j] + inner * radii[j] * 0.9), max(0.025, radii[j] * 0.4), light)
    face(P, (24, -6, 0.15), (10, -26, 4), blush_at=(42, -20, 0.1))
    spots = [(60, 40, 0.09), (-70, 50, 0.11), (110, 20, 0.08), (0, 70, 0.1), (-30, 30, 0.07), (150, 50, 0.09), (-130, 30, 0.08),
             (40, 62, 0.1), (-45, 64, 0.1)]
    for az, el, s in spots[:FORM + 1 + (2 if FORM >= 4 else 0)]:
        p, n = on(P.hc, P.hr, az, el, out=-0.01)
        ball(p, (s * P.u * 1.2, s * P.u * 0.3, s * P.u * 1.2), mat('octoSpot', rough=0.35, coat=0.4), normal=n)


def eekhoorn():
    """A squirrel holding an acorn. Grows: from an orange ball with a small tail to a tall, muscular squirrel with a huge tail
    that arches over its head with a cream tip, longer ear tufts and a bigger acorn; at form 6 it flexes with one arm
    and holds the acorn with the other."""
    body = mat('squirrel', rough=0.7, sheen=0.6)
    cream = mat('cream', rough=0.7, sheen=0.5)
    tail = mat('squirrelTail', rough=0.75, sheen=0.7)
    P = athlete(body, foot=mat('squirrel', rough=0.7), belly=cream, poses=lambda side: 'flex' if FORM == 6 and side < 0 else 'hold', head_w=0.98)
    u = P.u
    face(P, (24, 22, 0.13), (7, 0, 3), blush_at=(42, 8, 0.1), out=0.0)
    p, n = on(P.hc, P.hr, 0, 6, out=-0.05 * u)
    ball(p, (0.28 * u, 0.12 * u, 0.18 * u), cream, normal=n)
    ball(tuple(p + n * 0.1 * u + Vector((0, 0, 0.07 * u))), (0.07 * u, 0.05 * u, 0.05 * u), mat('nose', rough=0.25, coat=0.6, sss=0))
    top = P.hc[2] + P.hr[2]
    tuft = u * grow(0.1, 0.35)
    for side in (1, -1):
        drop((side * 0.38 * u, 0.05 * u, top - 0.2 * u), 0.16 * u, 0.4 * u, body, direction=(side * 0.3, 0, 1), flat=0.55)
        drop((side * 0.45 * u, 0.05 * u, top + 0.1 * u), 0.06 * u, tuft, tail, direction=(side * 0.3, 0, 1))
    H0 = P.top - P.base
    TL = grow(0.8, 1.9)
    ctrl = [Vector(q) for q in ((0.15 * P.rx, P.ry, P.base + 0.2 * H0), (P.rx * 0.9 + 0.9 * TL, P.ry + 0.5, P.base + 0.5 * H0),
                                (P.rx * 0.9 + 0.7 * TL, P.ry + 0.4, P.base + H0 + 0.6 * TL), (0.25 * P.rx, P.ry * 0.9, P.base + H0 + 0.9 * TL))]
    for i in range(33):
        t = i / 32
        pos = sum((w * q for w, q in zip(((1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3), ctrl)), Vector())
        r = (0.26 + 0.2 * math.sin(math.pi * min(1.0, t ** 0.8 * 1.05)) ** 0.7) * TL * 0.8
        ball(tuple(pos), r, mat('tailTip' if t > 0.82 else 'squirrelTail', rough=0.75, sheen=0.7))
    centre = P.hand[1] if FORM == 6 else (P.hand[1] + P.hand[-1]) / 2
    a = P.rx * grow(0.22, 0.4)
    ball(tuple(centre + Vector((0, -0.02, 0.0))), (a, a * 0.95, a * 1.1), mat('acorn', rough=0.35, coat=0.5))
    ball(tuple(centre + Vector((0, -0.02, a * 0.95))), (a * 1.15, a * 1.1, a * 0.5), mat('acornCap', rough=0.8))


def lammetje():
    """A lamb. Grows: from a woolly ball to an upright ram with a fleece torso, a short neck with the face clear of the fleece (4+) and
    curled horns from form 3 that grow into big ram horns; at form 6 it flexes."""
    wool = mat('wool', rough=0.9, sheen=0.8, sss=0.2)
    face_m = mat('lambFace', rough=0.6, sheen=0.3)
    hoof = mat('hoof', rough=0.5)
    P = athlete(face_m, torso=wool, limb=mat('lambLimb', rough=0.7, sheen=0.3), hand=hoof, foot=hoof, head_w=0.9, head_d=0.92,
                sink=0.62 if FORM >= 4 else 0.36, head_scale=1.0 + 0.08 * max(0, FORM - 3), head_fwd=0.35 if FORM >= 4 else 0.0)
    u, hx, hy, hz = P.u, *P.hr
    face(P, (26, 10, 0.12), (9, -22, 3), blush_at=(46, -8, 0.09))
    p, n = on(P.hc, P.hr, 0, -12, out=0.01 * u)
    ball(p, (0.06 * u, 0.04 * u, 0.04 * u), mat('bunnyEar', rough=0.4, coat=0.4), normal=n)
    R = (P.rx, P.ry, P.half)
    for az, el in spread(int(grow(24, 50))):
        if -50 < el < 38 and not (abs(az) < 65 and el > (-40 if FORM >= 4 else -15)):
            q, m = on(P.tc, R, az, el, out=0.0)
            ball(tuple(q), P.rx * 0.55, wool)
    top = P.hc[2] + hz
    for x, z, s in ((-0.15, -0.12, 0.17), (0.15, -0.12, 0.17), (0.0, -0.04, 0.19)):
        ball((x * u, -0.1 * u, top + z * u), s * u, wool)
    for side in (1, -1):
        drop((side * hx * 0.95, hy * 0.0, P.hc[2] + hz * 0.1), 0.11 * u, 0.4 * u, face_m, direction=(side, 0.1, -0.35), flat=0.4)
        if FORM >= 3:
            hs = (FORM - 2) / 4
            q = hz / 0.45
            pts, radii = [], []
            for k in range(15):
                a = 2 * math.pi * 1.05 * hs * k / 14
                r = (0.14 + 0.2 * hs) * q * (1 - 0.5 * k / 14)
                pts.append((side * (hx * 1.0 + 0.1 * hs * q * k / 14), P.hc[1] - 0.1 * u + r * math.sin(a), top - 0.1 * u + r * (math.cos(a) - 1)))
                radii.append((0.075 + 0.07 * hs) * q * (1 - 0.55 * k / 14))
            tube(pts, radii, mat('horn', rough=0.5, coat=0.3))


BUILDERS = {
    'hommel': hommel,
    'mol': mol,
    'kikker': kikker,
    'uil': uil,
    'egel': egel,
    'slak': slak,
    'axolotl': axolotl,
    'zeehond': zeehond,
    'pinguin': pinguin,
    'schildpad': schildpad,
    'konijn': konijn,
    'wasbeer': wasbeer,
    'lieveheersbeestje': lieveheersbeestje,
    'octopus': octopus,
    'eekhoorn': eekhoorn,
    'lammetje': lammetje,
}

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
target = Vector((0, 0, 1.45))
cam.location = target + Vector((-2.65, -7.6, 1.95))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()

def fit(root, height, max_width=3.7):
    """Scale the figure so it is `height` tall on screen (or `max_width` wide if the pose is wider), centred, feet on z = 0,
    and small enough that nothing, including the nearest foot or arm, is cropped by the frame."""
    bpy.context.view_layer.update()
    pts = []
    for obj in root.children_recursive:
        if obj.type == 'MESH':
            co = np.empty(len(obj.data.vertices) * 3)
            obj.data.vertices.foreach_get('co', co)
            m = np.array(obj.matrix_world)
            pts.append(co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3])
    pts = np.concatenate(pts)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    s = min(height / (hi[2] - lo[2]), max_width / (hi[0] - lo[0]))
    cx, inv = -(lo[0] + hi[0]) / 2, np.array(cam.matrix_world.inverted())
    sample = pts[::7]
    for _ in range(20):
        w = sample * s + np.array([cx * s, 0, -lo[2] * s])
        pc = w @ inv[:3, :3].T + inv[:3, 3]
        k = cam_data.lens / cam_data.sensor_width / -pc[:, 2]
        u, v = 0.5 + pc[:, 0] * k, 0.5 + pc[:, 1] * k
        if v.min() > 0.06 and v.max() < 0.96 and u.min() > 0.03 and u.max() < 0.97:
            break
        s *= 0.97
    root.scale = (s, s, s)
    root.location = (cx * s, 0, -lo[2] * s)


for name in ONLY:
    for form in FORMS:
        for obj in list(bpy.data.objects):
            if obj.type in ('MESH', 'EMPTY') and obj is not ground:
                bpy.data.objects.remove(obj, do_unlink=True)
        FORM, F, EYE, BROW = form, (form - 1) / 5, EYES[form - 1], form >= 4
        ROOT = bpy.data.objects.new(f'{name}-{form}', None)
        scene.collection.objects.link(ROOT)
        BUILDERS[name]()
        fit(ROOT, HEIGHTS[form - 1])
        scene.render.filepath = os.path.join(OUT, f'{name}-{form}.png')
        bpy.ops.render.render(write_still=True)
        print('wrote', scene.render.filepath, flush=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'partners.blend'))

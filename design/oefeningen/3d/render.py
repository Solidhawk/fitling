"""Tekent de houdingen uit poses.py als speelgoedfiguur, in de stijl van de partners.

blender -b --factory-startup -P render.py -- <uitvoermap> [oefening ...] [--test]
--test tekent alleen begin, midden en eind. Daarna maakt build.py de bestanden voor de app.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import poses  # noqa: E402

WIDTH, HEIGHT = 440, 330
MARGIN = 1.1
SAMPLES = 64
COLOURS = {
    'body': ('#C3AEE8', 0.3), 'cloth': ('#43335F', 0.5), 'work': ('#F58A78', 0.32), 'shoe': ('#86D45A', 0.3),
    'eye': ('#231A33', 0.08), 'white': ('#FFFFFF', 0.1), 'blush': ('#EE7E96', 0.4),
    'iron': ('#3A3048', 0.24), 'steel': ('#B7AFC4', 0.22), 'frame': ('#958BA8', 0.35), 'rope': ('#E9C27C', 0.6),
}
TRUNK_SHAPE = [(0, -0.07), (0.12, -0.03), (0.135, 0.07), (0.122, 0.19), (0.152, 0.33), (0.168, 0.43), (0.12, 0.52),
               (0.05, 0.56), (0.048, 0.64), (0, 0.67)]
SHORTS_SHAPE = [(0, -0.095), (0.105, -0.075), (0.15, 0), (0.147, 0.075), (0.128, 0.115), (0, 0.118)]
TROUSER_SHAPE = [(0, -0.122), (0.075, -0.1), (0.108, -0.045), (0.112, 0.03), (0.105, 0.12), (0, 0.125)]
DELTOID_SHAPE = [(0, -0.075), (0.045, -0.06), (0.074, -0.015), (0.075, 0.05), (0.06, 0.11), (0, 0.116)]
RIGHT = Vector((1, 0, 0))


def linear(hexcode):
    def channel(value):
        value /= 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return tuple(channel(int(hexcode[i:i + 2], 16)) for i in (1, 3, 5)) + (1.0,)


def make_materials():
    made = {}
    for name, (colour, roughness) in COLOURS.items():
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value = linear(colour)
        shader.inputs['Roughness'].default_value = roughness
        shader.inputs['Coat Weight'].default_value = 0.18
        made[name] = material
    return made


def smooth_profile(points, steps=9):
    out = []
    for i in range(len(points) - 1):
        p = [Vector(points[k]) for k in (max(i - 1, 0), i, i + 1, min(i + 2, len(points) - 1))]
        for step in range(steps):
            t = step / steps
            q = 0.5 * (2 * p[1] + (p[2] - p[0]) * t + (2 * p[0] - 5 * p[1] + 4 * p[2] - p[3]) * t * t
                       + (3 * p[1] - p[0] - 3 * p[2] + p[3]) * t ** 3)
            out.append((max(q.x, 0.0001), q.y))
    return out + [(max(points[-1][0], 0.0001), points[-1][1])]


def limb_profile(length, start, end, belly):
    arc = [math.pi / 2 * i / 10 for i in range(11)]
    out = [(max(start * math.sin(t), 0.0001), -start * math.cos(t)) for t in arc]
    for i in range(1, 16):
        t = i / 16
        out.append((start + (end - start) * t + belly * math.sin(math.pi * t), length * t))
    return out + [(max(end * math.cos(t), 0.0001), length + end * math.sin(t)) for t in arc]


def radius_at(profile, z):
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return profile[0][0] if z < profile[0][1] else profile[-1][0]


class Straight:
    """A line from a to b with a front: what limbs and equipment are turned round."""

    def __init__(self, a, b, front):
        a, b, front = Vector(a), Vector(b), Vector(front)
        self.start, self.axis = a, (b - a).normalized()
        front = front - self.axis * front.dot(self.axis)
        if front.length < 1e-4:
            front = self.axis.orthogonal()
        self.front = front.normalized()
        self.right = self.front.cross(self.axis).normalized()

    def at(self, z):
        return self.start + self.axis * z, self.right, self.front


class Spine:
    """The curve from the pelvis through the waist to the neck."""

    def __init__(self, pose):
        self.p0, self.p2 = Vector(pose.pelvis), Vector(pose.neck)
        self.p1 = 2 * Vector(pose.waist) - (self.p0 + self.p2) / 2

    def at(self, z):
        t = min(max(z / poses.TRUNK, 0.0), 1.0)
        centre = self.p0 * (1 - t) ** 2 + self.p1 * 2 * t * (1 - t) + self.p2 * t * t
        along = ((self.p1 - self.p0) * (1 - t) + (self.p2 - self.p1) * t).normalized()
        centre += along * (z - t * poses.TRUNK)
        return centre, RIGHT, Vector((0, -along.z, along.y))


class Painter:
    def __init__(self, materials):
        self.materials, self.objects = materials, []

    def clear(self):
        for obj in self.objects:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.meshes.remove(data)
        self.objects = []

    def mesh(self, verts, faces, colour, rounded=True):
        data = bpy.data.meshes.new('part')
        data.from_pydata([tuple(v) for v in verts], [], faces)
        data.update()
        for polygon in data.polygons:
            polygon.use_smooth = rounded
        data.materials.append(self.materials[colour])
        obj = bpy.data.objects.new('part', data)
        bpy.context.scene.collection.objects.link(obj)
        self.objects.append(obj)
        return obj

    def turned(self, line, profile, colour, wide=1.0, deep=1.0, n=56):
        verts = []
        for r, z in profile:
            centre, right, front = line.at(z)
            for i in range(n):
                a = 2 * math.pi * i / n
                verts.append(centre + right * (r * wide * math.sin(a)) + front * (r * deep * math.cos(a)))
        faces = [(j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i)
                 for j in range(len(profile) - 1) for i in range(n)]
        return self.mesh(verts, faces, colour)

    def muscle(self, line, profile, middle, half_length, around, half_width, wide=1.0, deep=1.0):
        """An oval lying on the surface of a turned shape; angles in degrees from its front."""
        rings, n = 12, 44
        verts = []
        for ring in range(rings + 1):
            share = ring / rings
            lift = 0.0015 + 0.006 * math.sqrt(max(1 - share * share, 0))
            for i in range(n):
                a = 2 * math.pi * i / n
                z = middle + half_length * share * math.cos(a)
                angle = math.radians(around + half_width * share * math.sin(a))
                centre, right, front = line.at(z)
                r = radius_at(profile, z)
                verts.append(centre + right * ((r * wide + lift) * math.sin(angle))
                             + front * ((r * deep + lift) * math.cos(angle)))
        faces = [(j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i)
                 for j in range(rings) for i in range(n)]
        return self.mesh(verts, faces, 'work')

    def ball(self, centre, axes, colour, flat_bottom=None, n=24):
        x, y, z = axes
        lowest = -1 if flat_bottom is None else flat_bottom
        # One point at each pole: a ring of tiny faces there shades as a dent.
        verts = [Vector(centre) + z * lowest]
        for j in range(1, n):
            polar = math.pi * j / n
            down, r = max(-math.cos(polar), lowest), math.sin(polar)
            for i in range(40):
                a = 2 * math.pi * i / 40
                verts.append(Vector(centre) + x * (r * math.cos(a)) + y * (r * math.sin(a)) + z * down)
        top = len(verts)
        verts.append(Vector(centre) + z)
        faces = [(0, 1 + (i + 1) % 40, 1 + i) for i in range(40)]
        faces += [(1 + j * 40 + i, 1 + j * 40 + (i + 1) % 40, 1 + (j + 1) * 40 + (i + 1) % 40, 1 + (j + 1) * 40 + i)
                  for j in range(n - 2) for i in range(40)]
        faces += [(top - 40 + i, top - 40 + (i + 1) % 40, top) for i in range(40)]
        return self.mesh(verts, faces, colour)

    def rod(self, a, b, radius, colour):
        a, b = Vector(a), Vector(b)
        length = (b - a).length
        if length < 1e-4:
            return None
        edge = min(radius * 0.4, length / 3)
        profile = [(0.0001, 0), (radius - edge, 0), (radius, edge), (radius, length - edge), (radius - edge, length),
                   (0.0001, length)]
        return self.turned(Straight(a, b, (0, -1, 0)), profile, colour, n=32)

    def box(self, centre, size, colour, bevel):
        half = Vector(size) / 2
        verts = [Vector(centre) + Vector((x * half.x, y * half.y, z * half.z))
                 for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        obj = self.mesh(verts, faces, colour)
        round_off = obj.modifiers.new('rand', 'BEVEL')
        round_off.width, round_off.segments = bevel, 4
        return obj


def draw_muscles(paint, name, spine, trunk, shorts, thigh, thigh_shape):
    if name == 'back':
        for side in (-1, 1):
            paint.muscle(spine, trunk, 0.30, 0.135, 180 + 52 * side, 43, 1.12, 0.8)
    elif name == 'core':
        paint.muscle(spine, trunk, 0.215, 0.125, 0, 72, 1.12, 0.8)
    elif name == 'glutes':
        for side in (-1, 1):
            paint.muscle(spine, shorts, 0.0, 0.075, 180 - 56 * side, 50, 1.13, 0.88)
            # The trouser leg too: bent at the hip, it covers the shorts.
            paint.muscle(thigh[side], smooth_profile(TROUSER_SHAPE), 0.0, 0.085, 180 - 28 * side, 72)
    elif name == 'quads':
        for side in (-1, 1):
            paint.muscle(thigh[side], thigh_shape, 0.245, 0.13, 0, 56)
    elif name == 'hamstrings':
        for side in (-1, 1):
            paint.muscle(thigh[side], thigh_shape, 0.25, 0.115, 180 - 24 * side, 72)


def draw_figure(paint, pose, muscles):
    spine = Spine(pose)
    trunk, shorts = smooth_profile(TRUNK_SHAPE), smooth_profile(SHORTS_SHAPE)
    paint.turned(spine, trunk, 'body', 1.12, 0.8)
    paint.turned(spine, shorts, 'cloth', 1.13, 0.88)

    up = Vector(pose.head_up).normalized()
    face = Vector((0, -up.z, up.y))
    head = Vector(pose.head)
    paint.rod(Vector(pose.neck) + up * 0.05, head - up * 0.08, 0.046, 'body')
    paint.ball(head, (RIGHT * 0.15, face * 0.145, up * 0.155), 'body')
    for side in (-1, 1):
        paint.ball(head + RIGHT * (0.056 * side) + face * 0.136 + up * 0.005,
                   (RIGHT * 0.026, face * 0.014, up * 0.034), 'eye')
        paint.ball(head + RIGHT * (0.056 * side - 0.006) + face * 0.148 + up * 0.018,
                   (RIGHT * 0.009, face * 0.006, up * 0.011), 'white')
        paint.ball(head + RIGHT * (0.093 * side) + face * 0.113 - up * 0.04,
                   (RIGHT * 0.023, face * 0.01, up * 0.014), 'blush')

    thigh_shape = limb_profile(poses.THIGH, 0.098, 0.062, 0.006)
    thighs = {}
    for side in (-1, 1):
        part = pose.sides[side]
        toe, sole = Vector(part.toe).normalized(), Vector(part.sole)
        sole = (sole - toe * sole.dot(toe)).normalized()
        # The front of a leg is the side the knee points to.
        hip, knee, ankle = Vector(part.hip), Vector(part.knee), Vector(part.ankle)
        leg = (ankle - hip).normalized()
        bent = (knee - hip) - leg * (knee - hip).dot(leg)
        ahead = bent if bent.length > 0.012 else toe - leg * toe.dot(leg)
        thighs[side] = Straight(hip, knee, ahead)
        paint.turned(thighs[side], thigh_shape, 'body')
        paint.turned(thighs[side], smooth_profile(TROUSER_SHAPE), 'cloth')
        paint.turned(Straight(knee, ankle, ahead), limb_profile(poses.SHIN, 0.062, 0.042, 0.012), 'body')
        across = sole.cross(toe).normalized()
        shoe = ankle + toe * 0.06 + sole * 0.041
        paint.ball(shoe, (across * 0.07, toe * 0.135, -sole * 0.064), 'shoe', flat_bottom=-0.78)

        shoulder, elbow, wrist = Vector(part.shoulder), Vector(part.elbow), Vector(part.wrist)
        upper = Straight(shoulder, elbow, spine.at(poses.TRUNK)[2])
        fore = Straight(elbow, wrist, upper.front)
        paint.turned(upper, limb_profile(poses.UPPER, 0.066, 0.045, 0.006), 'body')
        paint.turned(fore, limb_profile(poses.FORE, 0.045, 0.034, 0.006), 'body')
        if 'shoulders' in muscles:
            paint.turned(upper, smooth_profile(DELTOID_SHAPE), 'work')
        paint.ball(wrist + fore.axis * 0.012, (fore.right * 0.045, fore.front * 0.04, fore.axis * 0.052), 'body')
    for name in muscles:
        draw_muscles(paint, name, spine, trunk, shorts, thighs, thigh_shape)


def draw_prop(paint, prop):
    kind = prop[0]
    if kind == 'rod':
        paint.rod(*prop[1:])
    elif kind in ('box', 'cushion'):
        paint.box(*prop[1:], bevel=0.03 if kind == 'cushion' else 0.012)
    elif kind == 'wheel':
        centre = Vector(prop[1])
        paint.rod(centre - RIGHT * 0.02, centre + RIGHT * 0.02, 0.06, 'steel')
    elif kind == 'dumbbell':
        centre, axis = Vector(prop[1]), Vector(prop[2]).normalized()
        paint.rod(centre - axis * 0.09, centre + axis * 0.09, 0.022, 'steel')
        for side in (-1, 1):
            middle = centre + axis * (0.108 * side)
            paint.rod(middle - axis * 0.042, middle + axis * 0.042, 0.084, 'iron')
    elif kind == 'barbell':
        centre = Vector(prop[1])
        paint.rod(centre - RIGHT * 0.64, centre + RIGHT * 0.64, 0.021, 'steel')
        paint.rod(centre - RIGHT * 0.16, centre + RIGHT * 0.16, 0.04, 'cloth')
        for side in (-1, 1):
            paint.rod(centre + RIGHT * (0.46 * side), centre + RIGHT * (0.54 * side), 0.15, 'iron')
            paint.rod(centre + RIGHT * (0.54 * side), centre + RIGHT * (0.565 * side), 0.055, 'steel')
    elif kind == 'kettlebell':
        held, along = Vector(prop[1]), Vector(prop[2]).normalized()
        ahead = along.cross(RIGHT).normalized()
        paint.rod(held - RIGHT * 0.07, held + RIGHT * 0.07, 0.017, 'iron')
        for side in (-1, 1):
            paint.rod(held + RIGHT * (0.066 * side), held + along * 0.1 + RIGHT * (0.06 * side), 0.017, 'iron')
        paint.ball(held + along * 0.155, (RIGHT * 0.105, ahead * 0.1, along * 0.1), 'iron')
    else:
        raise ValueError(f'onbekend onderdeel {kind}')


def look_at(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()


def prepare_stage():
    scene = bpy.context.scene
    size = 6
    floor_data = bpy.data.meshes.new('floor')
    floor_data.from_pydata([(-size, -size, 0), (size, -size, 0), (size, size, 0), (-size, size, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new('floor', floor_data)
    floor.is_shadow_catcher = True
    scene.collection.objects.link(floor)

    camera_data = bpy.data.cameras.new('camera')
    camera_data.lens, camera_data.sensor_fit, camera_data.sensor_height = 85, 'VERTICAL', 36
    camera = bpy.data.objects.new('camera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    lights = []
    for watts, size in ((150, 2.8), (40, 2.0), (22, 1.5)):
        data = bpy.data.lights.new('light', 'AREA')
        data.energy, data.size = watts, size
        data.use_shadow = watts > 100  # only the key light throws a shadow
        light = bpy.data.objects.new('light', data)
        scene.collection.objects.link(light)
        lights.append(light)

    scene.world = bpy.data.worlds.new('world')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes['Background']
    background.inputs[0].default_value = linear('#EFE9F8')
    background.inputs[1].default_value = 0.42

    scene.render.engine = 'CYCLES'
    addon = bpy.context.preferences.addons.get('cycles')
    if addon:
        for kind in ('OPTIX', 'CUDA', 'ONEAPI', 'METAL'):
            try:
                addon.preferences.compute_device_type = kind
            except TypeError:
                continue
            addon.preferences.refresh_devices()
            if any(device.type == kind for device in addon.preferences.devices):
                for device in addon.preferences.devices:
                    device.use = device.type == kind
                scene.cycles.device = 'GPU'
                break
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.seed = 0  # the same grain in every frame
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = WIDTH, HEIGHT
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'
    return camera, lights


def draw(paint, motion, k):
    paint.clear()
    pose = motion.pose(k)
    draw_figure(paint, pose, motion.muscles)
    for prop in pose.props:
        draw_prop(paint, prop)


def whole_movement(paint, motion):
    """Every point the figure and the equipment reach during the movement."""
    points = []
    for k in (0, 0.25, 0.5, 0.75, 1):
        draw(paint, motion, k)
        points += [vertex.co.copy() for obj in paint.objects for vertex in obj.data.vertices]
    return points


def aim(camera, lights, view, points):
    """Frames all of `points`, so nothing leaves the picture halfway through."""
    round_figure, high = math.radians(view.azimuth), math.radians(view.elevation)
    away = Vector((math.sin(round_figure) * math.cos(high), -math.cos(round_figure) * math.cos(high), math.sin(high)))
    across = Vector((0, 0, 1)).cross(away).normalized()
    upward = away.cross(across).normalized()
    per_meter = camera.data.lens / camera.data.sensor_height
    target, height = sum(points, Vector((0, 0, 0))) / len(points), 2.0
    for _ in range(6):
        distance = height * per_meter
        sideways, vertical = [], []
        for point in points:
            offset = point - target
            scale = distance / max(distance - offset.dot(away), 0.1)
            sideways.append(offset.dot(across) * scale)
            vertical.append(offset.dot(upward) * scale)
        target += across * (max(sideways) + min(sideways)) / 2 + upward * (max(vertical) + min(vertical)) / 2
        height = MARGIN * max(max(vertical) - min(vertical), (max(sideways) - min(sideways)) * HEIGHT / WIDTH)
    camera.location = target + away * (height * per_meter)
    look_at(camera, target)
    # The lights go round with the camera, so every exercise is lit the same.
    turn = Matrix.Rotation(math.radians(view.azimuth - 34), 3, 'Z')
    for light, place in zip(lights, ((-0.9, -1.5, 4.0), (2.6, -1.4, 1.5), (0.6, 2.6, 2.4))):
        light.location = Vector((target.x, target.y, 0)) + turn @ Vector(place)
        look_at(light, target)


def main():
    given = sys.argv[sys.argv.index('--') + 1:]
    test = '--test' in given
    out, *chosen = [a for a in given if a != '--test']
    bpy.ops.wm.read_factory_settings(use_empty=True)
    paint = Painter(make_materials())
    camera, lights = prepare_stage()
    last = poses.FRAMES - 1
    for slug in chosen or list(poses.EXERCISES):
        motion = poses.EXERCISES[slug]
        aim(camera, lights, motion.camera, whole_movement(paint, motion))
        for index in (0, last // 2, last) if test else range(poses.FRAMES):
            draw(paint, motion, index / last)
            bpy.context.scene.render.filepath = os.path.join(out, slug, f'{index:02d}.png')
            bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    main()

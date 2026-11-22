"""Squats, uitvalspassen, deadlifts, billen en kuiten."""
import math

import gear
from moves_press import seated_feet, with_barbell, with_dumbbells
from rig import (ANKLE, LACES_DOWN, RIGHT, TRUNK, UP, V, body, flat_foot, forward, hanging, hip, kneeling, lean, leg,
                 limb_front, mix, on_the_ball, sagittal, shoulder, standing)


def on_hips(pelvis):
    return lambda s: (pelvis + (0.255 * s, -0.02, 0.1), V(s, 0.5, 0))


def at_sides(neck, out=0.25, ahead=0.02):
    return lambda s: (V(neck.x + out * s, neck.y - ahead, hanging(neck, out, neck.y - ahead, 0.549)), V(0, 1, 0))


def squat_down(k, deep, lean_from, lean_to, high=0.936):
    pelvis = V(0, 0.012 + (deep.y - 0.012) * k + 0.025 * math.sin(math.pi * k), mix(high, deep.z, k))
    up = lean(mix(lean_from, lean_to, k))
    return pelvis, up, forward(up), pelvis + up * TRUNK


def back_squat(k):
    pelvis, up, front, neck = squat_down(k, V(0, 0.25, 0.435), 8, 42)
    bar = neck - front * 0.125 - up * 0.02
    pose = body(pelvis, neck, lean(4 + 20 * k), standing(0.205, 24),
                lambda s: (bar + front * 0.03 + (0.34 * s, 0, 0), RIGHT * (0.2 * s) - up - front * 0.2))
    pose.loads = [('barbell', bar, 0.15)]
    pose.props = [('barbell', bar, 0.15)]
    return pose


def front_squat(k):
    pelvis, up, front, neck = squat_down(k, V(0, 0.205, 0.41), 2, 22)
    bar = neck + front * 0.155 + up * 0.045
    pose = body(pelvis, neck, lean(2 + 8 * k), standing(0.205, 26),
                lambda s: (bar - front * 0.035 + up * 0.035 + (0.25 * s, 0, 0), front + RIGHT * (0.1 * s)))
    pose.loads = [('barbell', bar, 0.15)]
    pose.props = [('barbell', bar, 0.15)]
    return pose


def bodyweight_squat(k):
    pelvis, up, front, neck = squat_down(k, V(0, 0.255, 0.425), 3, 38)
    ahead = sagittal(mix(12, 92, k))
    return body(pelvis, neck, lean(3 + 16 * k), standing(0.2, 22),
                lambda s: (shoulder(neck, s) + ahead * 0.55, V(0.4 * s, 0.6, -0.3)))


def sumo_squat(k):
    pelvis, up, front, neck = squat_down(k, V(0, 0.15, 0.44), 4, 18, 0.895)
    held = V(0, neck.y - 0.1, hanging(neck, 0.05, neck.y - 0.1, 0.551))
    pose = body(pelvis, neck, lean(2 + 8 * k), standing(0.36, 40),
                lambda s: (held + (0.05 * s, 0, 0), V(0.4 * s, 1, 0)))
    pose.loads = [('dumbbell', held - (0, 0, 0.11), 0.15)]
    pose.props = [('dumbbell', held - (0, 0, 0.11), UP)]
    return pose


def hack_squat(k):
    up = lean(-22)
    front = forward(up)
    start = V(0, 0, 0.86)
    pelvis = start - up * (0.43 * k)
    neck = pelvis + up * TRUNK
    toe, sole = V(0, -0.97, 0.24), V(0, -0.24, -0.97)
    pose = body(pelvis, neck, lean(-12), lambda s: (V(0.18 * s, -0.45, 0.17), V(0.2 * s, -1, 0.3), toe, sole),
                lambda s: (neck + front * 0.16 + (0.3 * s, 0, 0), RIGHT * (0.3 * s) - up))
    pose.props = [('slab', pelvis - front * 0.17, neck - front * 0.17 + up * 0.18, front, 0.32, 0.07, 'cloth'),
                  ('slab', V(0, -0.64, 0.12), V(0, -0.28, 0.03), V(0, 0.24, 0.97), 0.6, 0.04, 'frame')]
    for s in (-1, 1):
        rail = start - front * 0.27 + (0.23 * s, 0, 0)
        low, high = rail - up * 0.74, rail + up * 0.78
        pose.props += [('rod', low, high, 0.025, 'frame'), ('rod', high, V(high.x, high.y, 0.03), 0.025, 'frame'),
                       ('box', V(high.x, mix(low.y, high.y, 0.5), 0.025), V(0.08, 0.8, 0.05), 'frame'),
                       ('rod', neck - front * 0.12 + (0.2 * s, 0, 0), neck + front * 0.16 + (0.3 * s, 0, 0), 0.022,
                        'frame'),
                       ('plate', pelvis - front * 0.27 + up * 0.2 + (0.36 * s, 0, 0), RIGHT)]
    return pose


def split_stance(k, high, deep, front_foot, back_foot, tilt, hands):
    pelvis = mix(high, deep, k)
    neck = pelvis + lean(tilt) * TRUNK
    return body(pelvis, neck, lean(tilt * 0.4), lambda s: front_foot if s > 0 else back_foot, hands(pelvis, neck))


def split_squat(k):
    ankle, _, toe, sole = on_the_ball(-0.13, 0.47, 55)
    return split_stance(k, V(0, 0.02, 0.815), V(0, 0.02, 0.505), flat_foot(0.13, -0.4),
                        (ankle, V(0, -0.6, -1), toe, sole), 6, lambda pelvis, neck: on_hips(pelvis))


def bulgarian_split_squat(k):
    back = V(-0.13, 0.62, 0.505), V(0, -0.5, -1), V(0, 0.95, -0.3), V(0, 0.3, 0.95)
    pose = split_stance(k, V(0, 0.02, 0.835), V(0, 0.06, 0.48), flat_foot(0.13, -0.36), back, 17,
                        lambda pelvis, neck: at_sides(neck, 0.27))
    pose.props = gear.bench(V(0, 0.71, 0.43), V(0.55, 0.3, 0))
    return with_dumbbells(pose, lambda s: V(0, 1, 0), V(0, 0, -0.035))


def lunge(k, moving, travel):
    """One foot steps `travel` along Y, the hips sink between the two feet."""
    behind = -1 if moving > 0 else 1
    pelvis = V(0, travel * 0.475 * k, mix(0.928, 0.505, k))
    neck = pelvis + lean(7 * k) * TRUNK
    stepped = min(k / 0.8, 1)
    stride = travel * (1 - (1 - stepped) ** 1.6)
    lifted = 0.09 * math.sin(math.pi * stepped)

    def feet(s):
        y = stride if s == moving else 0.0
        rises = lifted if s == moving else 0.0
        back = (s == moving) == (travel > 0)
        if not back:
            return flat_foot(0.13 * s, y, ANKLE + rises)
        ankle, _, toe, sole = on_the_ball(0.13 * s, y, 55 * k)
        return ankle + (0, 0, rises), V(0, -1, -0.6 * k), toe, sole

    return pelvis, neck, feet, behind


def walking_lunge(k):
    pelvis, neck, feet, _ = lunge(k, 1, -0.8)
    pose = body(pelvis, neck, lean(2), feet, at_sides(neck, 0.26))
    return with_dumbbells(pose, lambda s: V(0, 1, 0), V(0, 0, -0.035))


def reverse_lunge(k):
    pelvis, neck, feet, _ = lunge(k, -1, 0.8)
    return body(pelvis, neck, lean(2), feet, on_hips(pelvis))


def step_up(k):
    pelvis = V(0, mix(0.02, -0.39, k), mix(0.92, 1.288, k))
    neck = pelvis + lean(8 + 20 * math.sin(math.pi * k)) * TRUNK

    def feet(s):
        if s > 0:
            return flat_foot(0.13, -0.4, 0.36 + ANKLE)
        return flat_foot(-0.13, mix(0.05, -0.4, k * k), ANKLE + 0.36 * k + 0.19 * math.sin(math.pi * k) * k ** 0.3)

    pose = body(pelvis, neck, lean(4), feet, at_sides(neck, 0.27))
    pose.props = gear.bench(V(0, -0.46, 0.36), V(0.55, 0.38, 0))
    return with_dumbbells(pose, lambda s: V(0, 1, 0), V(0, 0, -0.035))


def lateral_lunge(k):
    pelvis = V(0.6 * k, 0.012 + 0.2 * k, mix(0.932, 0.5, k))
    neck = pelvis + lean(4 + 32 * k) * TRUNK

    def feet(s):
        if s < 0:
            return flat_foot(-0.13, 0)
        stepped = min(k / 0.75, 1)
        x = mix(0.13, 0.9, 1 - (1 - stepped) ** 1.5)
        toe = V(0.2, -1, 0).unit()
        return V(x, 0, ANKLE + 0.07 * math.sin(math.pi * stepped)), V(0.4, -1, 0), toe, V(0, 0, -1)

    return body(pelvis, neck, lean(2 + 12 * k), feet,
                lambda s: (neck + (0.05 * s, -0.27, -0.2), V(s, 0.2, -0.8)))


def deadlift_up(k, feet, low, high, grip, bar_y, tilt, radius):
    """The weight on straight arms from the floor until standing. `bar_y` is where it is at the floor and on top."""
    pelvis = mix(low, high, k)
    up = lean(mix(tilt, 0, k))
    neck = pelvis + up * TRUNK
    y = mix(bar_y[0], bar_y[1], k)
    held = V(0, y, max(hanging(neck, grip, y), radius))
    pose = body(pelvis, neck, lean(mix(tilt * 0.7, 0, k)), feet,
                lambda s: (held + (grip * s, 0, 0), V(0.3 * s, 1, 0)))
    return pose, held


def deadlift(k):
    pose, held = deadlift_up(k, standing(0.17, 10), V(0, 0.28, 0.503), V(0, 0.005, 0.93), 0.29, (-0.16, -0.19), 55,
                             0.22)
    pose.loads = [('barbell', held, 0.22)]
    pose.props = [('barbell', held, 0.22)]
    return pose


def sumo_deadlift(k):
    pose, held = deadlift_up(k, standing(0.4, 38), V(0, 0.19, 0.47), V(0, 0.005, 0.885), 0.15, (-0.16, -0.17), 50,
                             0.22)
    pose.loads = [('barbell', held, 0.22)]
    pose.props = [('barbell', held, 0.22)]
    return pose


def kettlebell_deadlift(k):
    pose, held = deadlift_up(k, standing(0.26, 22), V(0, 0.24, 0.52), V(0, 0.005, 0.915), 0.04, (-0.09, -0.18), 50,
                             0.256)
    pose.loads = [('kettlebell', held - (0, 0, 0.152), 0.1)]
    pose.props = [('kettlebell', held, V(0, 0, -1))]
    return pose


def hinge_down(k, grip, bar_y):
    pelvis = V(0, mix(0.01, 0.27, k), mix(0.93, 0.835, k))
    neck = pelvis + lean(mix(3, 70, k)) * TRUNK
    y = mix(bar_y, bar_y + 0.01, k)
    held = V(0, y, hanging(neck, grip, y, 0.551))
    return body(pelvis, neck, lean(mix(2, 52, k)), standing(0.17, 10),
                lambda s: (held + (grip * s, 0, 0), V(0.3 * s, 1, 0)))


def romanian_deadlift(k):
    return with_barbell(hinge_down(k, 0.3, -0.195), V(0, 0, -0.02))


def dumbbell_romanian_deadlift(k):
    return with_dumbbells(hinge_down(k, 0.22, -0.2), below=V(0, 0, -0.035))


def single_leg_romanian_deadlift(k):
    pelvis = V(0, mix(0.0, 0.17, k), mix(0.93, 0.855, k))
    tilt = mix(4, 76, k)
    neck = pelvis + lean(tilt) * TRUNK
    behind = -mix(15, 78, k)

    def feet(s):
        if s > 0:
            return flat_foot(0.09, 0)
        front = limb_front(behind)
        return hip(pelvis, s) + sagittal(behind) * 0.842, front, front, sagittal(behind)

    y = mix(-0.17, neck.y - 0.02, k)
    height = hanging(neck, 0.22, y, 0.55)
    pose = body(pelvis, neck, lean(tilt * 0.75), feet, lambda s: (V(0.22 * s, y, height), V(0.3 * s, 1, 0)))
    return with_dumbbells(pose, below=V(0, 0, -0.035))


def reclined(tilt=-50):
    pelvis = V(0, 0, 0.42)
    up = lean(tilt)
    return pelvis, up, forward(up), pelvis + up * TRUNK


PRESS_AWAY = V(0, -0.8, 0.6)
PRESS_TOES = V(0, 0.6, 0.8)


def press_machine(pose, pelvis, up, front, plate_low, plate_high):
    pose.props = gear.back_rest(pelvis, up, front, 0.82) + gear.seat(pelvis, 0.3)
    pose.props.append(('slab', plate_low, plate_high, PRESS_AWAY * -1, 0.6, 0.05, 'frame'))
    for s in (-1, 1):
        rail = pelvis + (0.36 * s, 0, 0) - PRESS_TOES * 0.1
        low, high = rail + PRESS_AWAY * 0.25, rail + PRESS_AWAY * 1.15
        pose.props += [('rod', low, high, 0.025, 'frame'), ('rod', high, V(high.x, high.y, 0.03), 0.025, 'frame'),
                       ('rod', low, V(low.x, low.y, 0.03), 0.025, 'frame'),
                       ('plate', mix(plate_low, plate_high, 0.5) + PRESS_AWAY * 0.1 + (0.4 * s, 0, 0), RIGHT)]
        pose.props += gear.handle(pose.sides[s].wrist, V(0, 1, 0))
    return pose


def on_press_handles(pelvis):
    return lambda s: (pelvis + (0.27 * s, 0.0, -0.04), V(s, 0.5, 0))


def leg_press(k):
    pelvis, up, front, neck = reclined()
    away = mix(0.828, 0.43, k)
    pose = body(pelvis, neck, lean(-28),
                lambda s: (hip(pelvis, s) + PRESS_AWAY * away + (0.07 * s, 0, 0), V(0.3 * s, 0.4, 1), PRESS_TOES,
                           PRESS_AWAY),
                on_press_handles(pelvis))
    centre = pelvis + PRESS_AWAY * (away + 0.11)
    return press_machine(pose, pelvis, up, front, centre - PRESS_TOES * 0.17, centre + PRESS_TOES * 0.33)


def leg_press_calf_raise(k):
    pelvis, up, front, neck = reclined()
    away = mix(0.78, 0.826, k)
    angle = math.radians(mix(-16, 24, k))
    toe = PRESS_TOES * math.cos(angle) + PRESS_AWAY * math.sin(angle)
    sole = PRESS_AWAY * math.cos(angle) - PRESS_TOES * math.sin(angle)
    pose = body(pelvis, neck, lean(-28), lambda s: (hip(pelvis, s) + PRESS_AWAY * away, V(0, 0.6, 1), toe, sole),
                on_press_handles(pelvis))
    ball = pelvis + PRESS_AWAY * away + toe * 0.15 + sole * 0.11
    return press_machine(pose, pelvis, up, front, ball - PRESS_TOES * 0.05, ball + PRESS_TOES * 0.4)


def seated_machine(k, shin_from, shin_to, roller):
    """Sitting, the lower leg turning round the knee; `roller` is 1 in front of the ankle and -1 behind it."""
    pelvis = V(0, 0.05, 0.64)
    up = lean(-7)
    neck = pelvis + up * TRUNK
    thigh = sagittal(89)
    bend = mix(shin_from, shin_to, k)

    def feet(s):
        ankle, pole = leg(hip(pelvis, s), thigh, sagittal(bend), UP)
        return ankle, pole, limb_front(bend), sagittal(bend)

    pose = body(pelvis, neck, lean(-3), feet, lambda s: (pelvis + (0.27 * s, 0, -0.03), V(s, 0.7, 0)))
    pose.props = gear.seat(pelvis, 0.46) + gear.back_rest(pelvis, up, forward(up), 0.56)
    knee = pelvis + thigh * 0.43
    ankle = knee + sagittal(bend) * 0.38
    rolled = ankle + limb_front(bend) * (0.105 * roller)
    pose.props += gear.pad(rolled, 0.22)
    pose.props += [('rod', knee + (0.27, 0, 0), rolled + (0.27, 0, 0), 0.022, 'frame'),
                   ('rod', rolled + (0.2, 0, 0), rolled + (0.27, 0, 0), 0.018, 'frame'),
                   ('rod', knee + (0.27, 0, 0), V(0.27, knee.y + 0.2, 0.03), 0.025, 'frame')]
    for s in (-1, 1):
        pose.props += gear.handle(pose.sides[s].wrist, V(0, 1, 0))
    return pose, knee


def leg_extension(k):
    return seated_machine(k, -6, 80, 1)[0]


def seated_leg_curl(k):
    pose, knee = seated_machine(k, 72, -32, -1)
    pose.props += gear.pad(knee + (0, 0.09, 0.14), 0.22)
    return pose


def leg_curl(k):
    pelvis = V(0, 0, 0.68)
    neck = pelvis + lean(90) * TRUNK
    thigh = V(0, 1, -0.03)
    bend = mix(-96, -204, k)

    def feet(s):
        ankle, pole = leg(hip(pelvis, s), thigh, sagittal(bend), V(0, 0, -1))
        return ankle, pole, limb_front(bend), sagittal(bend)

    pose = body(pelvis, neck, lean(82), feet, lambda s: (V(0.25 * s, -0.62, 0.33), V(s, 0.6, 0)))
    pose.props = gear.bench(V(0, -0.24, 0.545), V(0.34, 1.2, 0))
    knee = pelvis + thigh.unit() * 0.43
    rolled = knee + sagittal(bend) * 0.37 - limb_front(bend) * 0.1
    pose.props += gear.pad(rolled, 0.22)
    pose.props += [('rod', knee + (0.27, 0, 0), rolled + (0.27, 0, 0), 0.022, 'frame'),
                   ('rod', rolled + (0.2, 0, 0), rolled + (0.27, 0, 0), 0.018, 'frame'),
                   ('rod', knee + (0.27, 0, 0), V(0.27, knee.y, 0.03), 0.025, 'frame')]
    return pose


def bridge_up(k):
    neck = V(0, TRUNK, 0.135)
    rise = math.radians(27 * k)
    up = V(0, math.cos(rise), -math.sin(rise))
    return neck - up * TRUNK, neck


def on_floor(pelvis, neck):
    return lambda s: (V(0.31 * s, neck.y - 0.45, 0.065), V(s, 0, 0.1))


def glute_bridge(k):
    pelvis, neck = bridge_up(k)
    return body(pelvis, neck, lean(-82), lambda s: (V(0.17 * s, -0.39, ANKLE), V(0, -0.2, 1), V(0, -1, 0),
                                                    V(0, 0, -1)), on_floor(pelvis, neck))


def single_leg_glute_bridge(k):
    pelvis, neck = bridge_up(k)

    def feet(s):
        if s < 0:
            return V(-0.11, -0.39, ANKLE), V(0, -0.2, 1), V(0, -1, 0), V(0, 0, -1)
        rise = math.radians(mix(27, 21, k))
        along = V(0, -math.cos(rise), math.sin(rise))
        front = V(0, math.sin(rise), math.cos(rise))
        return hip(pelvis, s) + along * 0.843, front, front, along

    return body(pelvis, neck, lean(-82), feet, on_floor(pelvis, neck))


def cable_kickback(k):
    pelvis = V(0, 0.02, 0.928)
    neck = pelvis + lean(22) * TRUNK
    back = mix(15, -42, k)

    def feet(s):
        if s < 0:
            return flat_foot(-0.11, 0)
        front = limb_front(back)
        return hip(pelvis, s) + sagittal(back) * 0.84, front, front, sagittal(back)

    pose = body(pelvis, neck, lean(14), feet, lambda s: (V(0.2 * s, -0.63, 1.27), V(0.5 * s, 0, -1)))
    pose.props = gear.stack(-0.74, 0.28 * k) + gear.cable(V(0.11, -0.62, 0.15), pose.sides[1].ankle + (0, 0, 0.04))
    ankle = pose.sides[1].ankle
    pose.props += [('rod', ankle + (-0.056, 0, 0.04), ankle + (0.056, 0, 0.04), 0.03, 'cloth')]
    pose.props += [('rod', V(-0.26, -0.67, 1.27), V(0.26, -0.67, 1.27), 0.022, 'steel')]
    return pose


def cable_pull_through(k):
    pelvis = mix(V(0, 0.27, 0.8), V(0, 0.008, 0.922), k)
    neck = pelvis + lean(62 * (1 - k)) * TRUNK
    arms = sagittal(mix(-36, 13, k))
    held = neck + arms * 0.526
    pose = body(pelvis, neck, lean(44 * (1 - k)), standing(0.27, 22), lambda s: (held + (0.04 * s, 0, 0), V(s, 0, 0)))
    pulley = V(0, 0.74, 0.17)
    knot = held + (pulley - held).unit() * 0.17
    pose.props = gear.stack(0.9, 0.26 * k) + gear.cable(pulley, knot)
    pose.props += gear.rope(knot, [pose.sides[s].wrist for s in (-1, 1)])
    return pose


def all_fours():
    pelvis = V(0, 0, 0.507)
    return pelvis, pelvis + lean(78) * TRUNK


def donkey_kick(k):
    pelvis, neck = all_fours()

    def feet(s):
        if s < 0:
            return kneeling(0.11)(s)
        thigh = mix(0, -102, k)
        shin = mix(-90, -192, k)
        ankle, pole = leg(hip(pelvis, s), sagittal(thigh), sagittal(shin))
        if k < 0.5:
            toe = mix(LACES_DOWN[0], sagittal(shin), k * 2).unit()
        else:
            toe = mix(sagittal(shin), limb_front(shin), k * 2 - 1).unit()
        return ankle, pole, toe, forward(toe)

    return body(pelvis, neck, lean(84), feet, lambda s: (V(0.185 * s, -0.46, 0.066), V(0.2 * s, 1, 0)))


def side_lying_leg_raise(k):
    up = V(0, 0.995, 0.1).unit()
    across = V(0, -up.z, up.y)
    front = V(-1, 0, 0)
    pelvis = V(0, 0, 0.205)
    neck = pelvis + up * TRUNK

    def feet(s):
        if s < 0:
            return V(0, -0.834, 0.085), front, front, V(0, -1, 0)
        rise = math.radians(mix(-9, 38, k))
        along = V(0, -math.cos(rise), math.sin(rise))
        return hip(pelvis, s, across) + along * 0.842, front, front, along

    def hands(s):
        if s < 0:
            return V(-0.28, 0.9, 0.078), V(-1, 0, 0)
        return V(-0.27, 0.28, 0.078), V(-0.3, 0, 1)

    return body(pelvis, neck, V(0, 1, -0.14).unit(), feet, hands, hip_across=across, shoulder_across=across)


def hip_abduction(k):
    pelvis = V(0, 0, 0.6)
    up = lean(-9)
    neck = pelvis + up * TRUNK
    out = mix(0.13, 0.44, k)
    pose = body(pelvis, neck, lean(-4),
                lambda s: (V(out * s, -0.45, 0.2), V((out - 0.1) * 2 * s, -1, 0.5), V(0, -1, 0), V(0, 0, -1)),
                lambda s: (pelvis + (0.27 * s, 0.02, -0.02), V(s, 0.7, 0)))
    pose.props = gear.seat(pelvis) + gear.back_rest(pelvis, up, forward(up), 0.56)
    for s in (-1, 1):
        knee, ankle = pose.sides[s].knee, pose.sides[s].ankle
        outside = knee + (0.1 * s, 0.03, 0)
        pose.props += [('rod', outside - (0, 0.08, 0), outside + (0, 0.08, 0), 0.05, 'cloth'),
                       ('rod', outside + (0.05 * s, 0, 0), V(0.22 * s, 0.02, 0.2), 0.02, 'frame'),
                       ('box', ankle - (0, 0.06, 0.11), V(0.15, 0.22, 0.04), 'frame'),
                       ('rod', ankle - (0, 0.03, 0.12), V(0.15 * s, 0.02, 0.12), 0.02, 'frame')]
        pose.props += gear.handle(pose.sides[s].wrist, V(0, 1, 0))
    return pose


def raised(k, lift_from, lift_to, floor, hands, feet=None, x=0.11):
    """Straight legs rising over the balls of the feet."""
    ankle, pole, toe, sole = on_the_ball(x, 0, mix(lift_from, lift_to, k), floor)
    pelvis = V(0, ankle.y - 0.005, ankle.z + 0.837)
    neck = pelvis + UP * TRUNK
    return body(pelvis, neck, UP, feet(pelvis) if feet else lambda s: (V(x * s, ankle.y, ankle.z), pole, toe, sole),
                hands(pelvis, neck))


def calf_raise(k):
    pose = raised(k, -15, 32, 0.12, lambda pelvis, neck: lambda s: (neck + (0.25 * s, -0.22, 0.02), V(0.3 * s, 0, -1)))
    pose.props = gear.step(-0.15, 0.12)
    for s in (-1, 1):
        shoulder_pad = pose.sides[s].shoulder + (0, 0, 0.1)
        arm_end = V(0.18 * s, 0.4, shoulder_pad.z + 0.05)
        pose.props += [('cushion', shoulder_pad, V(0.12, 0.26, 0.07), 'cloth'),
                       ('rod', shoulder_pad + (0, 0, 0.04), arm_end, 0.022, 'frame'),
                       ('rod', shoulder_pad + (0, 0, 0.04), pose.sides[s].wrist, 0.02, 'frame')]
        pose.props += gear.floor_frame(0.18 * s, 0.4, 1.8)
    return pose


def dumbbell_calf_raise(k):
    pose = raised(k, 0, 36, 0, lambda pelvis, neck: at_sides(neck))
    return with_dumbbells(pose, lambda s: V(0, 1, 0), V(0, 0, -0.035))


def bodyweight_calf_raise(k):
    pose = raised(k, 0, 38, 0, lambda pelvis, neck: lambda s: (V(0.22 * s, -0.53, 1.43), V(0.5 * s, 0, -1)))
    pose.props = gear.wall(-0.63)
    return pose


def single_leg_calf_raise(k):
    def feet(pelvis):
        def foot(s):
            if s > 0:
                return on_the_ball(0.1, 0, mix(-15, 34, k), 0.12)
            ankle, pole = leg(hip(pelvis, s), sagittal(-4), sagittal(-78))
            return ankle, pole, V(0, -0.2, -0.98), V(0, 0.98, -0.2)
        return foot

    def hands(pelvis, neck):
        return lambda s: (V(-0.3, -0.4, 1.3), V(-1, 0, -1)) if s < 0 else on_hips(pelvis)(s)

    pose = raised(k, -15, 34, 0.12, hands, feet)
    pose.props = gear.step(-0.15, 0.12, 0.42) + gear.post(-0.3, -0.42, 1.28)
    return pose


def seated_calf_raise(k):
    pelvis = V(0, 0.02, 0.6)
    neck = pelvis + lean(16) * TRUNK
    foot = on_the_ball(0.13, -0.4, mix(-15, 32, k), 0.1)
    ankle, _, toe, sole = foot
    feet = {s: (V(0.13 * s, ankle.y, ankle.z), V(0, -0.5, 1), toe, sole) for s in (-1, 1)}
    over_knees = body(pelvis, neck, UP, feet.get, lambda s: (neck + (0.2 * s, -0.3, -0.3), RIGHT * s)).sides[1].knee
    held = V(0, over_knees.y + 0.08, over_knees.z + 0.16)
    pose = body(pelvis, neck, lean(8), feet.get, lambda s: (held + (0.17 * s, 0, 0.05), V(s, 0.5, -0.4)))
    pose.props = gear.seat(pelvis) + gear.step(-0.56, 0.1) + gear.pad(held, 0.23)
    pivot = V(0.32, -0.82, 0.56)
    pose.props += [('rod', held + (0.22, 0, 0), V(0.32, held.y, held.z), 0.02, 'frame'),
                   ('rod', V(0.32, held.y, held.z), pivot, 0.022, 'frame'),
                   ('plate', mix(held, pivot, 0.6) + (0.2, 0, 0), RIGHT)]
    pose.props += gear.floor_frame(0.32, -0.82, 0.58)
    return pose

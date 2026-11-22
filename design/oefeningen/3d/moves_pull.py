"""Roeien, optrekken, pulldowns en de rug."""
import math

import gear
from moves_press import seated_feet, with_barbell, with_dumbbells
from rig import (ARM, LEG, RIGHT, SHOULDER_HALF, TRUNK, UP, V, body, forward, hanging, lean, leg, limb_front, mix,
                 sagittal, shoulder, standing)


def hinged_row(tilt, grip, end):
    """Bent over, the weight from hanging to `end` (along the trunk, off it)."""
    def at(k):
        pelvis = V(0, 0.17, 0.85)
        up = lean(tilt)
        front = forward(up)
        neck = pelvis + up * TRUNK
        low = V(0, neck.y - 0.01, hanging(neck, grip, neck.y - 0.01, 0.549))
        held = mix(low, pelvis + up * end[0] + front * end[1], k)
        return body(pelvis, neck, lean(tilt - 14), standing(0.19, 12),
                    lambda s: (held + (grip * s, 0, 0), V(0.5 * s, 1, 0.6)))
    return at


def barbell_row(k):
    return with_barbell(hinged_row(58, 0.3, (0.15, 0.2))(k), V(0, 0, -0.02))


def bent_over_dumbbell_row(k):
    pose = hinged_row(66, 0.27, (0.12, 0.07))(k)
    return with_dumbbells(pose, lambda s: V(0, 1, 0), V(0, 0, -0.035))


def t_bar_row(k):
    pose = hinged_row(52, 0.08, (0.21, 0.23))(k)
    held = mix(pose.sides[-1].wrist, pose.sides[1].wrist, 0.5) + (0, 0, -0.02)
    pivot = V(0, 1.05, 0.05)
    along = (held - pivot).unit()
    plates = held + along * 0.17
    pose.loads = [('plates', plates, 0.15)]
    pose.props = [('rod', pivot, held + along * 0.3, 0.022, 'steel'), ('box', pivot, V(0.22, 0.22, 0.06), 'frame'),
                  ('plate', plates, along)]
    pose.props += gear.handle(held, RIGHT, 0.14)
    return pose


def chest_supported_row(k):
    pelvis = V(0, 0.25, 0.73)
    up = lean(55)
    front = forward(up)
    neck = pelvis + up * TRUNK
    low = V(0.27, neck.y - 0.03, hanging(neck, 0.27, neck.y - 0.03, 0.545))
    top = pelvis + up * 0.22 + (0.3, 0, 0)
    held = mix(low, top, k)
    toe = V(0, -0.75, -0.66)
    pose = body(pelvis, neck, lean(48), lambda s: (V(0.19 * s, 0.78, 0.17), V(0, -1, -0.2), toe, V(0, 0.66, -0.75)),
                lambda s: (V(held.x * s, held.y, held.z), V(0.5 * s, 1, 0.7)))
    low_end, high_end = pelvis + front * 0.17 - up * 0.06, pelvis + front * 0.17 + up * 0.42
    middle = mix(low_end, high_end, 0.5)
    pose.props = [('slab', low_end, high_end, front, 0.27, 0.07, 'cloth'),
                  ('rod', middle, V(0, middle.y, 0.03), 0.035, 'frame'),
                  ('box', V(0, middle.y + 0.14, 0.025), V(0.16, 0.8, 0.05), 'frame')]
    return with_dumbbells(pose, lambda s: V(0, 1, 0), V(0, 0, -0.035))


def machine_row(k):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + lean(6) * TRUNK
    held = mix(V(0.2, -0.515, -0.15), V(0.24, -0.02, -0.28), k)
    pose = body(pelvis, neck, UP, seated_feet(pelvis, 0.24),
                lambda s: (neck + (held.x * s, held.y, held.z), V(0.4 * s, 1, -0.4)))
    pose.props = gear.seat(pelvis) + gear.floor_frame(0, -0.5, 1.5)
    pose.props += [('slab', V(0, -0.22, 0.72), V(0, -0.23, 1.0), V(0, 1, 0), 0.24, 0.07, 'cloth'),
                   ('rod', V(0, -0.25, 0.86), V(0, -0.5, 0.86), 0.03, 'frame'),
                   ('rod', V(-0.3, -0.5, 1.48), V(0.3, -0.5, 1.48), 0.03, 'frame')]
    for s in (-1, 1):
        wrist = pose.sides[s].wrist
        pose.props += gear.handle(wrist, UP, 0.06) + [('rod', V(0.28 * s, -0.5, 1.48), wrist + (0.04 * s, 0, 0), 0.02,
                                                       'frame')]
    return pose


def seated_cable_row(k):
    pelvis = V(0, 0, 0.56)
    neck = pelvis + lean(12 - 18 * k) * TRUNK
    held = mix(V(0, neck.y - 0.5, neck.z - 0.16), V(0, neck.y - 0.17, neck.z - 0.22), k)
    toe, sole = V(0, -0.25, 0.97), V(0, -0.97, -0.25)
    pose = body(pelvis, neck, lean(4), lambda s: (V(0.15 * s, -0.71, 0.32), V(0.1 * s, 0, 1), toe, sole),
                lambda s: (held + (0.06 * s, 0, 0), V(0.6 * s, 1, -0.5)))
    pose.props = gear.bench(V(0, 0.04, 0.43), V(0.3, 0.5, 0)) + gear.stack(-1.22, 0.3 * k)
    pose.props += gear.cable(V(0, -1.08, 0.6), held) + gear.handle(held, RIGHT, 0.09)
    pose.props += [('box', V(0.17 * s, -0.84, 0.36), V(0.15, 0.04, 0.3), 'frame') for s in (-1, 1)]
    return pose


def pulldown(k, grip, start, end, pole):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + lean(-3 - 10 * k) * TRUNK
    held = neck + mix(start, end, k)
    pose = body(pelvis, neck, lean(-4), seated_feet(pelvis, 0.2, 0.4), lambda s: (held + (grip * s, 0, 0), pole(s)))
    pulley = V(0, -0.22, 1.99)
    pose.props = gear.seat(pelvis) + gear.stack(-0.86, 0.32 * k) + gear.cable(pulley, held)
    pose.props += [('rod', V(0, -0.86, 2.02), V(0, -0.2, 2.02), 0.035, 'frame'),
                   ('rod', V(0, -0.36, 0.03), V(0, -0.36, 0.78), 0.03, 'frame')]
    pose.props += gear.pad(V(0, -0.33, 0.79), 0.26)
    return pose, held


def lat_pulldown(k):
    pose, held = pulldown(k, 0.36, V(0, -0.22, 0.47), V(0, -0.18, -0.02), lambda s: V(0.4 * s, 0.1, -1))
    pose.props += [('rod', held - (0.42, 0, 0), held + (0.42, 0, 0), 0.02, 'steel')]
    return pose


def close_grip_pulldown(k):
    pose, held = pulldown(k, 0.075, V(0, -0.22, 0.465), V(0, -0.21, -0.04), lambda s: V(0.3 * s, -0.3, -1))
    pose.props += gear.handle(held, RIGHT, 0.12)
    return pose


def to_the_bar(k, grip, pole):
    # The head keeps clear of the bar on the way up.
    back = 0.04 + 0.16 * math.sin(math.pi / 2 * min(k / 0.3, 1))
    neck = V(0, back, mix(1.64, 2.04, k))
    pelvis = neck - lean(-5) * TRUNK

    def feet(s):
        ankle, knee_pole = leg(pelvis + (0.11 * s, 0, 0), sagittal(-4), sagittal(-62))
        return ankle, knee_pole, V(0, -0.2, -0.98), V(0, 0.98, -0.2)

    pose = body(pelvis, neck, lean(-6), feet, lambda s: (V(grip * s, 0, 2.15), pole(s)))
    pose.props = gear.high_bar(2.17)
    return pose


def pull_up(k):
    return to_the_bar(k, 0.36, lambda s: V(0.7 * s, 0, -1))


def chin_up(k):
    return to_the_bar(k, 0.15, lambda s: V(0.1 * s, -1, -0.5))


def inverted_row(k):
    height = mix(0.34, 0.63, k)
    pivot = LEG + TRUNK
    rise = math.asin((height - 0.075) / pivot)
    along = V(0, math.cos(rise), math.sin(rise))
    neck = V(0, 0, 0.075) + along * pivot
    front = forward(along)
    pose = body(neck - along * TRUNK, neck, (along + front * 0.12).unit(),
                lambda s: (V(0.11 * s, 0, 0.075), front, front, along * -1),
                lambda s: (V(0.3 * s, 1.02, 0.8), V(s, 0.2, -0.7)))
    pose.props = gear.high_bar(0.82, 0.6, 1.02)
    return pose


def straight_arm_pulldown(k):
    pelvis = V(0, 0.07, 0.92)
    neck = pelvis + lean(20) * TRUNK
    angle = mix(124, 8, k)
    held = neck + sagittal(angle) * 0.542
    pose = body(pelvis, neck, lean(10), standing(0.17, 10), lambda s: (held + (0.16 * s, 0, 0), V(s, 0.15, 0)))
    pose.props = gear.stack(-0.92, 0.3 * k) + gear.cable(V(0, -0.8, 1.92), held)
    pose.props += [('rod', held - (0.23, 0, 0), held + (0.23, 0, 0), 0.02, 'steel')]
    return pose


def back_extension(k):
    pelvis = V(0, 0, 0.77)
    legs_up = lean(45)
    front_of_legs = forward(legs_up)
    up = lean(136 - 91 * k)
    front = forward(up)
    neck = pelvis + up * TRUNK
    pose = body(
        pelvis, neck, up,
        lambda s: (pelvis + (0.11 * s, 0, 0) - legs_up * 0.845, front_of_legs, front_of_legs, legs_up * -1),
        lambda s: (neck - up * 0.13 + front * 0.2 + (-0.06 * s, 0, 0), RIGHT * (0.7 * s) - up + front * 0.2),
    )
    top, low = pelvis + front_of_legs * 0.17 - legs_up * 0.06, pelvis + front_of_legs * 0.17 - legs_up * 0.34
    heel = pelvis - legs_up * 0.74 - front_of_legs * 0.1
    pose.props = [('slab', low, top, front_of_legs, 0.36, 0.07, 'cloth'),
                  ('rod', mix(low, top, 0.5), V(0, mix(low, top, 0.5).y, 0.03), 0.035, 'frame'),
                  ('box', V(0, 0.32, 0.025), V(0.14, 0.95, 0.05), 'frame')]
    plate = pelvis - legs_up * 0.94
    pose.props += gear.pad(heel, 0.22) + [('rod', heel, V(0, heel.y, 0.03), 0.025, 'frame'),
                                          ('box', V(0, plate.y, 0.04), V(0.4, 0.2, 0.04), 'frame')]
    return pose


def superman(k):
    pelvis = V(0, 0, 0.135)
    up = lean(90 - 19 * k)
    neck = pelvis + up * TRUNK
    reaching = lean(95 - 27 * k)
    behind = -88.5 - 22 * k
    return body(
        pelvis, neck, lean(86 - 17 * k),
        lambda s: (pelvis + (0.11 * s, 0, 0) + sagittal(behind) * 0.845, limb_front(behind), sagittal(behind),
                   limb_front(behind) * -1),
        lambda s: (shoulder(neck, s) + (reaching + (0.12 * s, 0, 0)).unit() * 0.55, V(0.2 * s, 0, 1)),
    )


def barbell_shrug(k):
    pelvis = V(0, 0, 0.932)
    neck = pelvis + UP * TRUNK
    rise = 0.08 * k
    drop = math.sqrt(ARM ** 2 - (0.3 - SHOULDER_HALF) ** 2 - 0.17 ** 2) - 0.002
    pose = body(pelvis, neck, UP, standing(0.17, 12),
                lambda s: (neck + (0.3 * s, -0.17, rise - drop), V(0.2 * s, 1, 0)), shrug=rise)
    pose.trapezius = True
    return with_barbell(pose, V(0, 0, -0.02))

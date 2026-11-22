"""Buik en romp."""
import math

import gear
from moves_legs import all_fours
from rig import (ANKLE, LACES_DOWN, RIGHT, TOES_DOWN, TRUNK, UP, V, body, flat_foot, forward, hip, kneeling, lean,
                 leg, limb_front, mix, sagittal, shoulder, standing, turned)

LYING = V(0, 0, 0.135)


def rolled(lower, upper):
    """Lying, the spine rolled up by `lower` degrees at the hips and `upper` at the chest."""
    low = lean(-90 + lower)
    high = lean(-90 + upper)
    waist = LYING + low * 0.22
    return waist, waist + high * (TRUNK - 0.22), high


def knees_bent(s):
    return V(0.15 * s, -0.43, ANKLE), V(0, -0.2, 1), V(0, -1, 0), V(0, 0, -1)


def crossed(neck, up, front):
    return lambda s: (neck - up * 0.14 + front * 0.2 + (-0.06 * s, 0, 0), RIGHT * (0.7 * s) - up + front * 0.2)


def flat_hands(s):
    return V(0.31 * s, 0.01, 0.066), V(s, 0, 0.1)


def by_the_head(head, across, front):
    return lambda s: (head + across * (0.17 * s) + front * 0.02, across * s + front * 0.4)


def crunch(k):
    waist, neck, up = rolled(8 * k, 36 * k)
    head_up = lean(-83 + 40 * k)
    return body(LYING, neck, head_up, knees_bent, by_the_head(neck + head_up * 0.275, RIGHT, forward(head_up)),
                waist=waist)


def sit_up(k):
    waist, neck, up = rolled(68 * k, 76 * k)
    return body(LYING, neck, lean(-83 + 78 * k), knees_bent, crossed(neck, up, forward(up)), waist=waist)


def reverse_crunch(k):
    waist, neck = V(0, 0.22, 0.135), V(0, TRUNK, 0.135)
    lifted = math.radians(40 * k)
    pelvis = waist + V(0, -math.cos(lifted), math.sin(lifted)) * 0.22
    tucked = math.radians(50 * k)
    thigh = V(0, math.sin(tucked), math.cos(tucked))
    shin = V(0, -math.cos(tucked), math.sin(tucked))

    def feet(s):
        ankle, pole = leg(hip(pelvis, s), thigh, shin)
        return ankle, pole, thigh, shin

    return body(pelvis, neck, lean(-83), feet, flat_hands, waist=waist)


def lying_leg_raise(k):
    rise = math.radians(mix(8, 84, k))
    along = V(0, -math.cos(rise), math.sin(rise))
    front = V(0, math.sin(rise), math.cos(rise))
    return body(LYING, LYING + (0, TRUNK, 0), lean(-83), lambda s: (hip(LYING, s) + along * 0.843, front, front, along),
                flat_hands)


def raised_direction(degrees):
    angle = math.radians(degrees)
    return V(0, -math.cos(angle), math.sin(angle))


def lifted_leg(s, pelvis, tucked):
    """From stretched out just over the floor (0) to the knee drawn in (1)."""
    thigh, shin = raised_direction(mix(16, 108, tucked)), raised_direction(mix(13, 14, tucked))
    ankle, pole = leg(hip(pelvis, s), thigh, shin, UP)
    return ankle, pole, V(0, shin.z, -shin.y), shin


def bicycle_crunch(k):
    waist, neck, up = rolled(6, 36)
    across, front = turned(up, mix(-26, 26, k))
    head_up = lean(-42)
    return body(LYING, neck, head_up, lambda s: lifted_leg(s, LYING, 1 - k if s > 0 else k),
                by_the_head(neck + head_up * 0.275, across, front), waist=waist, shoulder_across=across)


def russian_twist(k):
    up = lean(-32)
    neck = LYING + up * TRUNK
    across, front = turned(up, mix(-38, 38, k))
    held = neck - up * 0.2 + front * 0.32
    return body(LYING, neck, lean(-12), lambda s: (V(0.13 * s, -0.53, 0.1), V(0, -0.2, 1), V(0, -1, 0), V(0, 0, -1)),
                lambda s: (held + across * (0.045 * s), across * s - up), shoulder_across=across)


def one_then_the_other(k, s):
    """0 until halfway and then to 1, the other side the other way round."""
    share = k if s > 0 else 1 - k
    t = max(0.0, 2 * share - 1)
    return t * t * (3 - 2 * t)


def dead_bug(k):
    neck = LYING + (0, TRUNK, 0)

    def feet(s):
        out = one_then_the_other(k, -s)
        thigh = raised_direction(mix(92, 15, out))
        shin = raised_direction(mix(4, 13, out))
        ankle, pole = leg(hip(LYING, s), thigh, shin, UP)
        return ankle, pole, V(0, shin.z, -shin.y), shin

    def hands(s):
        out = math.radians(78 * one_then_the_other(k, s))
        direction = V(0.22 * s * math.sin(out), math.sin(out), math.cos(out)).unit()
        return shoulder(neck, s) + direction * 0.549, V(s, 0, 0.1)

    return body(LYING, neck, lean(-83), feet, hands)


def bird_dog(k):
    pelvis, neck = all_fours()

    def feet(s):
        out = one_then_the_other(k, -s)
        shin = mix(-89.6, -91, out)
        ankle, pole = leg(hip(pelvis, s), sagittal(mix(0, -90, out)), sagittal(shin))
        return ankle, pole, LACES_DOWN[0], LACES_DOWN[1]

    def hands(s):
        out = one_then_the_other(k, s)
        down = V(0.185 * s, -0.46, 0.066)
        pointing = shoulder(neck, s) + sagittal(98) * 0.549
        # Through a low arc, so the hand clears the floor straight away.
        middle = shoulder(neck, s) + sagittal(48) * 0.537
        wrist = mix(mix(down, middle, out), mix(middle, pointing, out), out)
        return wrist, V(0.2 * s, 1, 0.3)

    return body(pelvis, neck, lean(84), feet, hands)


def mountain_climber(k):
    rise = math.asin((0.6 - 0.19) / (0.846 + TRUNK))
    along = V(0, -math.cos(rise), math.sin(rise))
    neck = V(0, 0, 0.19) + along * (0.846 + TRUNK)
    # The hips a little up, or the knee cannot swing through under them.
    hips_up = 0.53
    pelvis = V(0, neck.y + math.sqrt(TRUNK ** 2 - (neck.z - hips_up) ** 2), hips_up)

    def feet(s):
        drawn = k if s > 0 else 1 - k
        ankle = mix(V(0.11 * s, -0.025, 0.19), V(0.11 * s, pelvis.y + 0.05, 0.2), drawn)
        ankle += (0, 0, 0.075 * math.sin(math.pi * drawn))
        turning = min(2.5 * drawn, 1)
        return ankle, V(0, -turning - 0.001, -1 + 0.95 * turning), *TOES_DOWN

    return body(pelvis, neck, lean(80), feet, lambda s: (V(0.22 * s, neck.y - 0.02, 0.066), V(s, 0.6, 0.2)))


def ab_wheel(k):
    tipped = math.radians(mix(13, 50, k))
    pelvis = V(0, -math.sin(tipped) * 0.43, 0.075 + math.cos(tipped) * 0.43)
    neck = pelvis + lean(mix(67, 86, k)) * TRUNK
    across = 0.15 - 0.185
    ahead = math.sqrt(max(0.549 ** 2 - across ** 2 - (neck.z - 0.15) ** 2, 0.0004))
    held = V(0, neck.y - ahead, 0.15)
    pose = body(pelvis, neck, lean(mix(76, 84, k)), kneeling(0.13),
                lambda s: (held + (0.15 * s, 0, 0), V(0.5 * s, 0.4, 1)))
    pose.props = [('rod', held - (0.2, 0, 0.005), held + (0.2, 0, -0.005), 0.02, 'steel'),
                  ('rod', held - (0.045, 0, 0.005), held + (0.045, 0, -0.005), 0.142, 'iron')]
    return pose


def pallof_press(k):
    pelvis = V(0, 0.02, 0.91)
    neck = pelvis + lean(4) * TRUNK
    held = V(0, neck.y + mix(-0.2, -0.5, k), neck.z - 0.15)
    pose = body(pelvis, neck, UP, standing(0.24, 14), lambda s: (held + (0.04 * s, 0, 0), V(s, 0.2, -1)))
    pose.props = gear.stack(-0.1, 0.08 * k, -0.92, True) + gear.cable(V(-0.78, -0.1, held.z), held, V(0, 1, 0))
    pose.props += gear.handle(held, UP, 0.06)
    return pose


def woodchop(k):
    pelvis = V(0, 0.03, mix(0.91, 0.86, k))
    up = lean(mix(2, 14, k))
    neck = pelvis + up * TRUNK
    across, front = turned(up, mix(48, -44, k))
    hip_across, _ = turned(UP, mix(14, -14, k))
    climb = math.radians(mix(34, -50, k))
    held = neck + (front * math.cos(climb) + up * math.sin(climb)) * 0.515
    pose = body(pelvis, neck, up, lambda s: flat_foot(0.25 * s, 0, knee_pole=V(0.2 * s, -1, 0)),
                lambda s: (held + across * (0.025 * s), across * s - up * 0.2), hip_across=hip_across,
                shoulder_across=across)
    pose.props = gear.stack(-0.12, 0.3 * k, -0.92, True) + gear.cable(V(-0.78, -0.12, 1.9), held, V(0, 1, 0))
    pose.props += gear.handle(held, across, 0.07)
    return pose


def hanging_knee_raise(k):
    neck = V(0, 0.02, 1.602)
    pelvis = neck - V(0, 0, TRUNK)

    def feet(s):
        shin = mix(-16, 6, k)
        ankle, pole = leg(hip(pelvis, s), sagittal(mix(8, 112, k)), sagittal(shin))
        return ankle, pole, limb_front(shin), sagittal(shin)

    pose = body(pelvis, neck, lean(4), feet, lambda s: (V(0.22 * s, 0, 2.128), V(s, -0.2, 0)))
    pose.props = gear.high_bar(2.15)
    return pose

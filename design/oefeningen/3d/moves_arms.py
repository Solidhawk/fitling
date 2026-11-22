"""Armen en schouders: curls, strekken, heffen."""
import math

import gear
from moves_press import seated_feet, with_barbell, with_dumbbells
from rig import RIGHT, TRUNK, UP, V, arm, body, flat_foot, kneeling, lean, limb_front, mix, sagittal, shoulder, standing


def standing_still(hands, tilt=0.0):
    pelvis = V(0, 0.02 if tilt else 0, 0.932)
    neck = pelvis + lean(tilt) * TRUNK
    return body(pelvis, neck, lean(tilt * 0.6), standing(0.17, 12), hands(neck))


def curled(bend, out, inward=0.0, hang=8):
    """Upper arm still, the forearm `bend` degrees up from hanging."""
    def hands(neck):
        return lambda s: arm(shoulder(neck, s), sagittal(hang) + (out * s, 0, 0),
                             sagittal(bend) + (inward * s, 0, 0))
    return hands


def barbell_curl(k):
    return with_barbell(standing_still(curled(mix(28, 142, k), 0.18, 0.04)), V(0, -0.01, 0))


def reverse_curl(k):
    return with_barbell(standing_still(curled(mix(28, 124, k), 0.1, -0.02, 11)), V(0, -0.01, 0))


def dumbbell_curl(k):
    return with_dumbbells(standing_still(curled(mix(16, 144, k), 0.26, 0.24)))


def hammer_curl(k):
    bend = mix(8, 136, k)
    return with_dumbbells(standing_still(curled(bend, 0.2, 0.1)), lambda s: limb_front(bend))


def cable_curl(k):
    pose = standing_still(curled(mix(38, 140, k), 0.05))
    held = mix(pose.sides[-1].wrist, pose.sides[1].wrist, 0.5)
    pose.props = gear.stack(-0.86, 0.3 * k) + gear.cable(V(0, -0.72, 0.15), held)
    pose.props += [('rod', held - (0.3, 0, 0), held + (0.3, 0, 0), 0.02, 'steel')]
    return pose


def incline_dumbbell_curl(k):
    pelvis = V(0, 0, 0.62)
    up = lean(-34)
    front = V(0, -up.z, up.y)
    neck = pelvis + up * TRUNK
    bend = mix(6, 140, k)
    pose = body(pelvis, neck, lean(-20), seated_feet(pelvis),
                lambda s: arm(shoulder(neck, s), V(0.24 * s, 0, -1), sagittal(bend) + (0.14 * s, 0, 0)))
    pose.props = gear.seat(pelvis) + gear.back_rest(pelvis, up, front, 0.84)
    return with_dumbbells(pose)


def concentration_curl(k):
    pelvis = V(0, 0.05, 0.6)
    neck = pelvis + lean(38) * TRUNK

    def feet(s):
        return flat_foot(0.37 * s, -0.38, knee_pole=V(0.4 * s, -1, 0.3))

    def hands(s):
        if s < 0:
            return V(-0.3, -0.3, 0.665), V(-0.4, 0.6, 0.2)
        bend = math.radians(mix(8, 152, k))
        fore = V(-0.17 - 0.12 * math.sin(bend), -math.sin(bend) * 0.7, -math.cos(bend))
        return arm(shoulder(neck, s), V(0, -0.3, -0.955), fore)

    pose = body(pelvis, neck, lean(30), feet, hands)
    pose.props = gear.bench(V(0, 0.08, 0.47), V(0.75, 0.3, 0))
    return with_dumbbells(pose, sides=(1,))


def preacher_curl(k):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + lean(14) * TRUNK
    upper = sagittal(49)
    bend = mix(58, 160, k)
    pose = body(pelvis, neck, lean(4), seated_feet(pelvis, 0.24, 0.4),
                lambda s: arm(shoulder(neck, s), upper, sagittal(bend)))
    under = limb_front(49) * -1
    elbow = neck + upper * 0.29
    low, high = elbow + under * 0.1 + upper * 0.07, elbow + under * 0.1 - upper * 0.16
    pose.props = gear.seat(pelvis) + [('slab', low, high, limb_front(49), 0.56, 0.07, 'cloth')]
    pose.props += gear.floor_frame(0, low.y, low.z - 0.02)
    return with_barbell(pose, V(0, 0, 0.015))


def with_grips(pose, angle):
    for s in (-1, 1):
        pose.sides[s].grip = V(0, -math.cos(math.radians(angle)), math.sin(math.radians(angle)))
    return pose


def wrist_curl(k):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + lean(40) * TRUNK
    pose = body(pelvis, neck, lean(30), seated_feet(pelvis, 0.22),
                lambda s: (V(0.2 * s, -0.44, 0.678), V(0, 1, -1)))
    pose.props = gear.seat(pelvis, 0.3, 0.5)
    with_grips(pose, mix(-38, 38, k))
    for s in (-1, 1):
        held = pose.sides[s].wrist + pose.sides[s].grip * 0.085
        pose.loads.append(('dumbbell', held, 0.084))
        pose.props.append(('dumbbell', held, RIGHT))
    return pose


def reverse_wrist_curl(k):
    pelvis = V(0, 0, 0.498)
    neck = pelvis + lean(47) * TRUNK
    pose = body(pelvis, neck, lean(40), kneeling(0.13), lambda s: (V(0.17 * s, -0.67, 0.525), V(0, 1, -1)))
    pose.props = gear.bench(V(0, -0.5, 0.465), V(0.78, 0.26, 0))
    with_grips(pose, mix(-36, 36, k))
    held = mix(pose.sides[-1].wrist, pose.sides[1].wrist, 0.5) + pose.sides[1].grip * 0.085
    pose.loads = [('barbell', held, 0.15)]
    pose.props.append(('barbell', held, 0.15))
    return pose


def triceps_pushdown(k):
    bend = mix(122, 22, k)
    pose = standing_still(curled(bend, 0.0, -0.14, 5), 6)
    hands = [pose.sides[s].wrist for s in (-1, 1)]
    middle = mix(hands[0], hands[1], 0.5)
    pulley = V(0, -0.5, 1.93)
    knot = middle + (pulley - middle).unit() * 0.2
    pose.props = gear.stack(-0.66, 0.3 * k) + gear.cable(pulley, knot) + gear.rope(knot, hands)
    return pose


def overhead_cable_extension(k):
    pelvis = V(0, 0.02, 0.88)
    neck = pelvis + lean(28) * TRUNK
    bend = mix(252, 128, k)

    def feet(s):
        return flat_foot(0.14 * s, -0.24) if s > 0 else (V(-0.14, 0.3, 0.14), V(0, -1, 0), V(0, -0.94, -0.34),
                                                        V(0, 0.34, -0.94))

    def hands(s):
        fore = sagittal(bend) + (-0.36 * s, 0, 0)
        return arm(shoulder(neck, s), sagittal(146) + (0.17 * s, 0, 0), fore, V(s, 0, 0))

    pose = body(pelvis, neck, lean(26), feet, hands)
    wrists = [pose.sides[s].wrist for s in (-1, 1)]
    middle = mix(wrists[0], wrists[1], 0.5)
    pulley = V(0, 0.78, 1.62)
    knot = middle + (pulley - middle).unit() * 0.2
    pose.props = gear.stack(0.94, 0.26 * k) + gear.cable(pulley, knot) + gear.rope(knot, wrists)
    return pose


def overhead_triceps_extension(k):
    def hands(neck):
        def hand(s):
            fore = mix(V(-0.6 * s, 0.8, -0.12), V(-0.58 * s, 0.1, 0.8), k)
            return arm(shoulder(neck, s), V(0.14 * s, 0.03, 1), fore, V(s, 0, 0))
        return hand
    pose = standing_still(hands)
    held = mix(pose.sides[-1].wrist, pose.sides[1].wrist, 0.5)
    hangs = mix(V(0, 0.5, -0.86), V(0, 0.05, 1), k).unit()
    pose.loads = [('dumbbell', held + hangs * 0.07, 0.15)]
    pose.props.append(('dumbbell', held + hangs * 0.07, hangs))
    return pose


def triceps_kickback(k):
    pelvis = V(0, 0.17, 0.85)
    neck = pelvis + lean(64) * TRUNK
    bend = mix(12, -74, k)
    pose = body(pelvis, neck, lean(52), standing(0.18, 10),
                lambda s: arm(shoulder(neck, s), sagittal(-76) + (0.17 * s, 0, 0), sagittal(bend) + (0.1 * s, 0, 0),
                              V(0, 0, 1)))
    return with_dumbbells(pose, lambda s: limb_front(bend), V(0, 0, -0.01))


def lateral_raise(k):
    out = math.radians(mix(17, 88, k))

    def hands(neck):
        return lambda s: (shoulder(neck, s) + V(s * math.sin(out), -0.12, -math.cos(out)).unit() * 0.548, V(0, 1, 0.1))
    return with_dumbbells(standing_still(hands), lambda s: V(0, 1, 0))


def front_raise(k):
    angle = mix(16, 89, k)

    def hands(neck):
        return lambda s: (shoulder(neck, s) + sagittal(angle) * 0.552, V(0.3 * s, 0, -1) + V(0, 0.6, 0))
    return with_dumbbells(standing_still(hands))


def rear_delt_fly(k):
    pelvis = V(0, 0.18, 0.84)
    neck = pelvis + lean(70) * TRUNK
    out = math.radians(mix(6, 82, k))
    pose = body(pelvis, neck, lean(56), standing(0.18, 10),
                lambda s: (shoulder(neck, s) + V(s * math.sin(out), -0.1, -math.cos(out)).unit() * 0.54,
                           V(s * math.cos(out), 0.3, math.sin(out))))
    return with_dumbbells(pose, lambda s: V(0, 1, 0))


def reverse_pec_deck(k):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + lean(6) * TRUNK
    out = math.radians(mix(-5, 92, k))

    def hands(s):
        direction = V(s * math.sin(out), -math.cos(out), -0.06).unit()
        return shoulder(neck, s) + direction * 0.532, V(s * math.cos(out), math.sin(out), -0.2)

    pose = body(pelvis, neck, UP, seated_feet(pelvis, 0.24), hands)
    pose.props = gear.seat(pelvis) + gear.floor_frame(0, -0.34, 1.6)
    pose.props += [('slab', V(0, -0.22, 0.7), V(0, -0.23, 0.98), V(0, 1, 0), 0.24, 0.07, 'cloth'),
                   ('rod', V(0, -0.25, 0.84), V(0, -0.34, 0.84), 0.03, 'frame')]
    for s in (-1, 1):
        wrist, pivot = pose.sides[s].wrist, V(0.17 * s, -0.12, 1.58)
        above = V(wrist.x, wrist.y, 1.58)
        pose.props += gear.handle(wrist, UP) + [('rod', pivot, above, 0.022, 'frame'),
                                                ('rod', above, wrist, 0.022, 'frame'),
                                                ('rod', V(0, -0.34, 1.58), pivot, 0.025, 'frame')]
    return pose


def cable_lateral_raise(k):
    out = math.radians(mix(-9, 88, k))

    def hands(neck):
        def hand(s):
            if s < 0:
                return V(-0.26, -0.03, 1.0), V(-1, 0.3, 0)
            return shoulder(neck, s) + V(math.sin(out), -0.27, -math.cos(out)).unit() * 0.547, V(0, 1, 0.1)
        return hand
    pose = standing_still(hands)
    wrist = pose.sides[1].wrist
    pose.props = gear.stack(-0.12, 0.3 * k, -0.78, True)
    pose.props += gear.cable(V(-0.64, -0.14, 0.15), wrist, V(0, 1, 0)) + gear.handle(wrist, V(0, 1, 0), 0.06)
    return pose

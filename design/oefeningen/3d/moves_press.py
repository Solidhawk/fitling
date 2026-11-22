"""Drukken, opdrukken, dippen en vliegen."""
import math

import gear
from rig import (ANKLE, LEG, RIGHT, SHOULDER_HALF, TOES_DOWN, TRUNK, UP, V, arm, body, flat_foot, forward, lean, leg,
                 mix, sagittal, shoulder, standing)

BENCH = 0.45


def seated_feet(pelvis, width=0.22, ahead=0.42):
    return lambda s: flat_foot(width * s, pelvis.y - ahead)


def on_bench(tilt, hands):
    """Lying on a bench tilted up `tilt` degrees. `hands(neck, up, front)` gives the hands."""
    angle = math.radians(tilt)
    up = V(0, math.cos(angle), math.sin(angle))
    front = forward(up)
    pelvis = V(0, 0, BENCH + (0.15 if tilt else 0.13))
    neck = pelvis + up * TRUNK
    head_up = (up * math.cos(0.12) + front * math.sin(0.12)).unit()
    pose = body(pelvis, neck, head_up, lambda s: (V(0.28 * s, -0.43, ANKLE), V(0.15 * s, -0.4, 1), V(0, -1, 0),
                                                  V(0, 0, -1)), hands(neck, up, front))
    if tilt:
        pose.props = gear.back_rest(pelvis, up, front, 0.86) + gear.seat(pelvis, 0.3)
    else:
        pose.props = gear.bench(V(0, 0.39, BENCH), V(0.3, 1.04, 0))
    return pose


def with_barbell(pose, above=V(0, 0, 0.02), radius=0.15):
    bar = mix(pose.sides[-1].wrist, pose.sides[1].wrist, 0.5) + above
    pose.loads = [('barbell', bar, radius)]
    pose.props += [('barbell', bar, radius)]
    return pose


def with_dumbbells(pose, axis=lambda s: RIGHT, below=V(0, 0, 0), sides=(-1, 1)):
    for s in sides:
        centre = pose.sides[s].wrist + below
        pose.loads.append(('dumbbell', centre, 0.084))
        pose.props.append(('dumbbell', centre, axis(s)))
    return pose


def lying_press(tilt, grip, low, tuck):
    """From straight arms down to `low` (towards the hips, off the chest)."""
    def at(k):
        def hands(neck, up, front):
            def hand(s):
                top_height = math.sqrt(0.549 ** 2 - (grip - SHOULDER_HALF) ** 2)
                top = neck + UP * top_height if not tilt else neck + (front * 0.6 + UP * 0.8).unit() * top_height
                bottom = neck - up * low[0] + front * low[1]
                wrist = mix(top, bottom, k) + (grip * s, 0, 0)
                return wrist, RIGHT * ((1 - tuck) * s) - up * (0.3 + tuck) - front * 0.7
            return hand
        return on_bench(tilt, hands)
    return at


def bench_press(k):
    return with_barbell(lying_press(0, 0.34, (0.15, 0.2), 0)(k))


def dumbbell_bench_press(k):
    return with_dumbbells(lying_press(0, 0.36 - 0.12 * math.cos(math.pi * k / 2), (0.13, 0.13), 0.1)(k))


def incline_bench_press(k):
    return with_barbell(lying_press(32, 0.34, (0.07, 0.19), 0.1)(k))


def incline_dumbbell_press(k):
    return with_dumbbells(lying_press(38, 0.38 - 0.13 * math.cos(math.pi * k / 2), (0.07, 0.12), 0.1)(k))


def close_grip_bench_press(k):
    return with_barbell(lying_press(0, 0.19, (0.22, 0.19), 0.8)(k))


def skull_crusher(k):
    def hands(neck, up, front):
        upper = V(0, 0.16, 1)
        bend = math.radians(4 + 112 * k)
        return lambda s: arm(shoulder(neck, s), upper, V(0, math.sin(bend), math.cos(bend)), V(0, -1, 0))
    return with_barbell(on_bench(0, hands))


def dumbbell_fly(k):
    def hands(neck, up, front):
        out = math.radians(-12 + 94 * k)

        def hand(s):
            direction = V(s * math.sin(out), -0.1, math.cos(out)).unit()
            return shoulder(neck, s) + direction * 0.532, V(s * math.cos(out), 0, -math.sin(out))
        return hand
    return with_dumbbells(on_bench(0, hands), lambda s: V(0, 1, 0))


def dumbbell_pullover(k):
    def hands(neck, up, front):
        back = math.radians(-6 + 78 * k)
        held = neck + V(0, math.sin(back), math.cos(back)) * 0.515
        return lambda s: (held + (0.055 * s, 0, 0), V(s, 0, 0.1))
    pose = on_bench(0, hands)
    held = mix(pose.sides[-1].wrist, pose.sides[1].wrist, 0.5)
    direction = (held - pose.neck).unit()
    pose.loads = [('dumbbell', held + direction * 0.09, 0.15)]
    pose.props.append(('dumbbell', held + direction * 0.09, direction))
    return pose


def dumbbell_floor_press(k):
    pelvis, neck = V(0, 0, 0.135), V(0, TRUNK, 0.135)

    def hands(s):
        joint = shoulder(neck, s)
        resting, pole = arm(joint, V(0.8 * s, -0.55, -0.2), UP)
        return mix(joint + (0.02 * s, -0.02, 0.548), resting, k), pole

    pose = body(pelvis, neck, lean(-83), lambda s: (V(0.17 * s, -0.4, ANKLE), V(0, -0.2, 1), V(0, -1, 0),
                                                    V(0, 0, -1)), hands)
    return with_dumbbells(pose, below=V(0, 0, 0.02))


def plank(ankle_z, high, low, hand, pole, props=(), pivot=LEG + TRUNK, feet=None):
    """A straight body turning round its toes (or knees), from shoulders `high` down to `low`."""
    def at(k):
        rise = math.asin((mix(high, low, k) - ankle_z) / pivot)
        along = V(0, -math.cos(rise), math.sin(rise))
        neck = V(0, 0, ankle_z) + along * pivot
        pelvis = neck - along * TRUNK

        def on_toes(s):
            return V(0.11 * s, 0, ankle_z), V(0, 0, -1), *TOES_DOWN
        head_up = (along - forward(along) * 0.2).unit()
        pose = body(pelvis, neck, head_up, feet or on_toes, lambda s: (V(hand.x * s, hand.y, hand.z), pole(s)))
        pose.props = list(props)
        return pose
    return at


push_up = plank(0.19, 0.605, 0.305, V(0.25, -1.25, 0.065), lambda s: V(s, 0.6, 0.3))
diamond_push_up = plank(0.19, 0.6, 0.32, V(0.075, -1.24, 0.065), lambda s: V(0.5 * s, 1, 0.4))
incline_push_up = plank(0.16, 1.01, 0.73, V(0.25, -1.07, 0.48), lambda s: V(s, 0.6, 0.3),
                        gear.bench(V(0, -1.17, 0.42), V(0.85, 0.3, 0)))
decline_push_up = plank(0.59, 0.612, 0.29, V(0.25, -1.295, 0.065), lambda s: V(s, 0.6, 0.3),
                        gear.bench(V(0, 0.02, 0.42), V(0.5, 0.36, 0)))
knee_push_up = plank(0.075, 0.6, 0.31, V(0.25, -0.79, 0.065), lambda s: V(s, 0.6, 0.3), pivot=0.43 + TRUNK,
                     feet=lambda s: (V(0.11 * s, 0.392, 0.225), V(0, 0, -1), V(0, 0.9, 0.44), V(0, -0.44, 0.9)))


def pike_push_up(k):
    swing = mix(-0.33, -0.47, k)
    pelvis = V(0, swing, 0.17 + math.sqrt(0.832 ** 2 - swing ** 2))
    up = lean(mix(140, 154, k))
    neck = pelvis + up * TRUNK
    return body(
        pelvis, neck, lean(mix(128, 118, k)),
        lambda s: (V(0.11 * s, 0, 0.17), V(0, -1, 0), *TOES_DOWN),
        lambda s: (V(0.22 * s, -0.78, 0.065), V(s, 0.5, 0.3)),
    )


def bench_dip(k):
    pelvis = V(0, -0.09 - 0.01 * k, 0.545 - 0.245 * k)
    up = lean(-9)
    pose = body(
        pelvis, pelvis + up * TRUNK, lean(-2),
        lambda s: (V(0.15 * s, -0.73, ANKLE), V(0, -0.2, 1), V(0, -1, 0), V(0, 0, -1)),
        lambda s: (V(0.22 * s, 0.12, 0.475), V(0.1 * s, 1, 0.2)),
    )
    pose.props = gear.bench(V(0, 0.27, 0.43), V(0.85, 0.32, 0))
    return pose


def dip(k):
    up = lean(10 + 18 * k)
    neck = V(0, -0.12 * k, 1.675 - 0.255 * k)
    pelvis = neck - up * TRUNK

    def feet(s):
        ankle, pole = leg(pelvis + (0.11 * s, 0, 0), sagittal(-4), sagittal(-92))
        return ankle, pole, V(0, 0.3, -0.95), V(0, 0.95, 0.3)

    pose = body(pelvis, neck, lean(8), feet, lambda s: (V(0.27 * s, 0, 1.15), V(0.25 * s, 1, 0.2)))
    for s in (-1, 1):
        pose.props += [('rod', V(0.27 * s, -0.3, 1.125), V(0.27 * s, 0.35, 1.125), 0.022, 'steel'),
                       ('rod', V(0.27 * s, 0.35, 0.03), V(0.27 * s, 0.35, 1.125), 0.03, 'frame'),
                       ('box', V(0.27 * s, 0.1, 0.025), V(0.1, 0.8, 0.05), 'frame')]
    return pose


def overhead_press(k):
    pelvis = V(0, 0, 0.932)
    neck = pelvis + UP * TRUNK
    # Round the face, then over the head.
    height = mix(0.03, 0.54, k)
    ahead = mix(-0.2, -0.01, max(0, (k - 0.5) / 0.5) ** 1.5)
    pose = body(pelvis, neck, UP, standing(0.17, 12),
                lambda s: (neck + (0.28 * s, ahead, height), V(0.5 * s, -0.2, -1)))
    return with_barbell(pose)


def sitting_press(k, start, top, pole, bulge=0.0):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + UP * TRUNK

    def hands(s):
        wrist = mix(start, top, k)
        return neck + ((wrist.x + bulge * math.sin(math.pi * k)) * s, wrist.y, wrist.z), pole(s)

    pose = body(pelvis, neck, UP, seated_feet(pelvis), hands)
    pose.props = gear.seat(pelvis) + gear.back_rest(pelvis, UP, V(0, -1, 0), 0.56)
    return pose


def dumbbell_shoulder_press(k):
    pose = sitting_press(k, V(0.41, -0.06, 0.11), V(0.23, -0.02, 0.545), lambda s: V(s, 0, -1))
    return with_dumbbells(pose)


def arnold_press(k):
    pose = sitting_press(k, V(0.17, -0.27, 0.03), V(0.22, -0.02, 0.545), lambda s: V(0.5 * s, -0.4, -1), 0.17)
    turn = math.radians(90 * math.sin(math.pi * k / 2))
    return with_dumbbells(pose, lambda s: V(math.cos(turn), 0.35 * math.sin(turn) * s, 0.12))


def machine_shoulder_press(k):
    pose = sitting_press(k, V(0.36, -0.14, 0.09), V(0.31, -0.06, 0.525), lambda s: V(s, 0, -1))
    for s in (-1, 1):
        wrist = pose.sides[s].wrist
        pivot = V(0.46 * s, 0.32, 1.12)
        elbowed = V(0.46 * s, wrist.y, wrist.z)
        pose.props += gear.handle(wrist, RIGHT) + [('rod', pivot, elbowed, 0.025, 'frame'),
                                                   ('rod', elbowed, wrist, 0.02, 'frame')]
        pose.props += gear.floor_frame(0.46 * s, 0.32, 1.14)
    return pose


def chest_press_machine(k):
    pose = sitting_press(k, V(0.32, -0.15, -0.13), V(0.24, -0.525, -0.13), lambda s: V(s, 0.3, -0.5))
    for s in (-1, 1):
        wrist = pose.sides[s].wrist
        pivot = V(0.46 * s, 0.1, 1.55)
        pose.props += gear.handle(wrist, UP) + [('rod', pivot, wrist, 0.025, 'frame')]
        pose.props += gear.floor_frame(0.46 * s, 0.1, 1.57)
    return pose


def pec_deck(k):
    pelvis = V(0, 0, 0.6)
    neck = pelvis + UP * TRUNK
    out = math.radians(84 - 96 * k)

    def hands(s):
        direction = V(s * math.sin(out), -math.cos(out), -0.15).unit()
        return shoulder(neck, s) + direction * 0.528, V(s * math.cos(out), math.sin(out), -0.3)

    pose = body(pelvis, neck, UP, seated_feet(pelvis), hands)
    pose.props = gear.seat(pelvis) + gear.back_rest(pelvis, UP, V(0, -1, 0), 0.56)
    pose.props += gear.floor_frame(0, 0.28, 1.62)
    for s in (-1, 1):
        wrist, pivot = pose.sides[s].wrist, V(0.22 * s, 0.1, 1.6)
        above = V(wrist.x, wrist.y, 1.6)
        pose.props += gear.handle(wrist, UP) + [('rod', pivot, above, 0.022, 'frame'),
                                                ('rod', above, wrist, 0.022, 'frame'),
                                                ('rod', V(0, 0.28, 1.6), pivot, 0.025, 'frame')]
    return pose


def crossover(k, pulley_z, start, end, elbows):
    pelvis = V(0, 0.03, 0.915)
    up = lean(12)
    neck = pelvis + up * TRUNK

    def feet(s):
        return flat_foot(0.15 * s, -0.17) if s > 0 else (V(-0.15, 0.22, 0.12), V(0, -1, 0), V(0, -0.97, -0.24),
                                                        V(0, 0.24, -0.97))

    def hands(s):
        direction = mix(start, end, k)
        return shoulder(neck, s) + V(direction.x * s, direction.y, direction.z).unit() * 0.532, V(elbows.x * s, elbows.y, elbows.z)

    pose = body(pelvis, neck, lean(6), feet, hands)
    for s in (-1, 1):
        wrist = pose.sides[s].wrist
        pose.props += gear.stack(0.1, 0.2 * k, 0.98 * s, True)
        pose.props += gear.cable(V(0.86 * s, 0.1, pulley_z), wrist, V(0, 1, 0)) + gear.handle(wrist, UP, 0.05)
    return pose


def cable_fly(k):
    return crossover(k, 1.86, V(0.96, 0.02, -0.12), V(-0.22, -0.72, -0.64), V(0.3, 1, 0.2))


def low_cable_fly(k):
    return crossover(k, 0.14, V(0.62, 0.06, -0.78), V(-0.24, -0.95, 0.22), V(0.8, 0.5, -0.5))

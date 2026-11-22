"""De bewegingen van alle oefeningen, als houdingen van 0 (begin) tot 1 (eind), met camera en tempo.

Zonder Blender, zodat de tests ze overal kunnen toetsen; `render.py` tekent ze. Het figuur staat in `rig.py`,
de bewegingen per soort in `moves_*.py`. Id en spieren komen uit de catalogus van de app.
"""
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import gear
import moves_arms as arms
import moves_core as core
import moves_legs as legs
import moves_press as press
import moves_pull as pull
from rig import (ANKLE, FORE, HEAD, HIP_HALF, SHIN, SHOULDER_HALF, THIGH, TRUNK, UPPER, Pose, V, body, ease, forward,
                 lean, mix, standing, swing_ease)

BENCH_THRUST, BENCH_ROW = 0.39, 0.40
FRAMES, FPS = 24, 25


def goblet_squat(k):
    pelvis = V(0, 0.012 + 0.223 * k + 0.025 * math.sin(math.pi * k), 0.936 - 0.556 * k)
    up = lean(3 + 25 * k)
    front = forward(up)
    held = pelvis + up * 0.395 + front * 0.235
    pose = body(pelvis, pelvis + up * TRUNK, lean(3 + 10 * k), standing(0.205, 30),
                lambda s: (held + up * 0.035 - front * 0.015 + (0.073 * s, 0, 0), V(0.12 * s, 0, -1)))
    pose.loads = [('dumbbell', held, 0.15)]
    pose.props = [('dumbbell', held, lean((3 + 25 * k) / 2))]
    return pose


def hip_thrust(k):
    rise = math.radians(40 * (1 - k))
    up = V(0, math.cos(rise), math.sin(rise))
    front = forward(up)
    on_bench = V(0, 0, BENCH_THRUST) + front * 0.12
    pelvis = on_bench - up * 0.36
    bar = pelvis + front * 0.165 - up * 0.01
    head_up = (up * math.cos(0.45) + front * math.sin(0.45)).unit()
    pose = body(
        pelvis, pelvis + up * TRUNK, head_up,
        lambda s: (V(0.17 * s, -0.775, ANKLE), V(0.1 * s, -0.2, 1), V(0.18 * s, -1, 0).unit(), V(0, 0, -1)),
        lambda s: (bar + (0.28 * s, 0, 0.02), V(s, 0, -0.3)),
    )
    pose.loads = [('barbell', bar, 0.15)]
    pose.props = [('barbell', bar)] + gear.bench(V(0, 0.16, BENCH_THRUST), V(0.95, 0.36, 0))
    return pose


def one_arm_row(k):
    pelvis = V(0, 0, 0.89)
    up = lean(78)
    neck = pelvis + up * TRUNK

    def feet(s):
        if s < 0:
            # The knee and shin lie on the bench, the toes point back.
            return V(-0.14, 0.41, BENCH_ROW + 0.06), V(0, -1, -1), V(0, 1, -0.15).unit(), V(0, 0, 1)
        return V(0.27, 0.06, ANKLE), V(0.2, -1, 0), V(0.2, -1, 0).unit(), V(0, 0, -1)

    def hands(s):
        if s < 0:
            return V(-0.19, neck.y - 0.02, BENCH_ROW + 0.04), V(-0.3, 1, 0)
        hanging = neck + (SHOULDER_HALF + 0.02, 0, -0.553)
        return mix(hanging, V(0.308, -0.088, 0.82), k), V(0.15, 1, 0.5)

    pose = body(pelvis, neck, lean(64), feet, hands)
    weight = pose.sides[1].wrist + (0, 0, -0.035)
    pose.loads = [('dumbbell', weight, 0.085)]
    pose.props = [('dumbbell', weight, V(0, 1, 0))] + gear.bench(V(-0.18, -0.06, BENCH_ROW), V(0.26, 1.18, 0))
    return pose


def face_pull(k):
    pelvis = V(0, 0, 0.932)
    up = lean(-4)
    neck = pelvis + up * TRUNK
    pose = body(
        pelvis, neck, up, standing(0.17, 14),
        lambda s: (mix(V(0.06 * s, -0.47, 1.56), V(0.23 * s, -0.09, 1.645), k), V(s, 0, 0.05)),
    )
    hands = [pose.sides[s].wrist for s in (-1, 1)]
    knot = mix(V(0, -0.64, 1.60), V(0, -0.36, 1.655), k)
    pulley = V(0, -1.12, 1.68)
    pose.props = gear.stack(-1.2, 0.28 * k) + [('rod', knot, pulley, 0.006, 'iron'), ('wheel', pulley)]
    pose.props += [('rod', hand, knot, 0.014, 'rope') for hand in hands]
    return pose


def cable_crunch(k):
    pelvis = V(0, 0.03, 0.496)
    waist = pelvis + lean(12 + 33 * k) * 0.22
    neck = waist + lean(20 + 72 * k) * (TRUNK - 0.22)
    head_angle = 22 + 100 * k
    head_up = lean(head_angle)
    head = neck + head_up * HEAD
    pose = body(
        pelvis, neck, head_up,
        lambda s: (V(0.13 * s, 0.42, 0.072), V(0, -1, -1), V(0, 1, -0.2).unit(), V(0, 0, 1)),
        lambda s: (head + (0.165 * s, 0, 0) + forward(head_up) * 0.11 - head_up * 0.03, V(0.5 * s, 0, 0) + forward(head_up)),
        waist=waist,
    )
    hands = [pose.sides[s].wrist for s in (-1, 1)]
    pulley = V(0, -0.92, 1.90)
    knot = head + (pulley - head).unit() * 0.27
    pose.props = gear.stack(-1.0, 0.34 * k) + [('rod', knot, pulley, 0.006, 'iron'), ('wheel', pulley)]
    pose.props += [('rod', hand, knot, 0.014, 'rope') for hand in hands]
    return pose


def hanging_leg_raise(k):
    bar = V(0, 0, 2.15)
    neck = V(0, 0.02, 1.602)
    pelvis = neck - V(0, 0, TRUNK)
    raised = math.radians(4 + 86 * k)
    legs = V(0, -math.sin(raised), -math.cos(raised))
    knees = V(0, -math.cos(raised), math.sin(raised))
    pose = body(
        pelvis, neck, lean(4),
        lambda s: (pelvis + (HIP_HALF * s, 0, 0) + legs * 0.846, knees, knees, legs),
        lambda s: (bar + (0.27 * s, 0, -0.025), V(s, -0.2, 0)),
    )
    pose.props = gear.high_bar(2.15)
    return pose


def kettlebell_swing(k):
    # The hips are nearly done when the bell is halfway: they throw it, the arms only hold on.
    hips = ease(min(k / 0.75, 1))
    pelvis = mix(V(0, 0.24, 0.76), V(0, 0.008, 0.932), hips)
    up = lean(55 * (1 - hips))
    neck = pelvis + up * TRUNK
    angle = math.radians(33 - 121 * k)
    arms = V(0, math.sin(angle), -math.cos(angle))
    inward = SHOULDER_HALF - 0.04
    held = neck + arms * math.sqrt((UPPER + FORE - 0.012) ** 2 - inward ** 2)
    pose = body(pelvis, neck, lean(42 * (1 - hips)), standing(0.23, 22),
                lambda s: (held + (0.04 * s, 0, 0), V(s, 0, 0)))
    bell = held + arms * 0.15
    pose.loads = [('kettlebell', bell, 0.105)]
    pose.props = [('kettlebell', held, arms)]
    return pose


@dataclass(frozen=True)
class Camera:
    azimuth: float
    """Degrees round the figure: 0 in front of it, 90 on its left."""
    elevation: float = 11
    """Degrees above it. How far away is worked out by render.py from the whole movement."""


@dataclass(frozen=True)
class Motion:
    id: str
    pose: Callable[[float], Pose]
    muscles: tuple
    camera: Camera
    timing: tuple
    """Frames at 25 per second: to the end, hold, back, rest."""
    curve: Callable[[float], float] = ease

    def sequence(self):
        """Which of the rendered frames is shown at each 25th of a second of one repetition."""
        out, hold, back, rest = self.timing
        last = FRAMES - 1
        shown = [self.curve(i / out) for i in range(out)] + [1.0] * hold
        shown += [1 - self.curve(i / back) for i in range(back)] + [0.0] * rest
        return [round(value * last) for value in shown]


UP_FIRST = (28, 10, 34, 11)
DOWN_FIRST = (34, 8, 27, 14)
SMALL = (26, 14, 30, 11)
SIDE_TO_SIDE = (30, 6, 30, 6)

MOVEMENTS = [
    ('hip-thrust', hip_thrust, Camera(62, 9), (26, 14, 34, 11)),
    ('dumbbell-row', one_arm_row, Camera(62, 20), (26, 10, 34, 11)),
    ('goblet-squat', goblet_squat, Camera(66), (33, 8, 27, 17)),
    ('face-pull', face_pull, Camera(118), (26, 12, 34, 11)),
    ('cable-crunch', cable_crunch, Camera(70), (28, 12, 34, 11)),
    ('hanging-leg-raise', hanging_leg_raise, Camera(56, 6), (30, 10, 38, 11)),
    ('kettlebell-swing', kettlebell_swing, Camera(66), (15, 4, 17, 4), swing_ease),
    ('back-squat', legs.back_squat, Camera(62, 10), DOWN_FIRST),
    ('bench-press', press.bench_press, Camera(56, 22), DOWN_FIRST),
    ('deadlift', legs.deadlift, Camera(104, 10), UP_FIRST),
    ('overhead-press', press.overhead_press, Camera(38, 8), UP_FIRST),
    ('barbell-row', pull.barbell_row, Camera(112, 14), UP_FIRST),
    ('romanian-deadlift', legs.romanian_deadlift, Camera(108, 10), DOWN_FIRST),
    ('incline-dumbbell-press', press.incline_dumbbell_press, Camera(50, 16), DOWN_FIRST),
    ('lateral-raise', arms.lateral_raise, Camera(24, 10), UP_FIRST),
    ('dumbbell-curl', arms.dumbbell_curl, Camera(34, 10), UP_FIRST),
    ('hammer-curl', arms.hammer_curl, Camera(58, 10), UP_FIRST),
    ('overhead-triceps-extension', arms.overhead_triceps_extension, Camera(112, 8), UP_FIRST),
    ('walking-lunge', legs.walking_lunge, Camera(68, 10), DOWN_FIRST),
    ('dumbbell-shoulder-press', press.dumbbell_shoulder_press, Camera(32, 8), UP_FIRST),
    ('rear-delt-fly', arms.rear_delt_fly, Camera(38, 20), UP_FIRST),
    ('leg-press', legs.leg_press, Camera(78, 12), DOWN_FIRST),
    ('leg-extension', legs.leg_extension, Camera(64, 12), UP_FIRST),
    ('leg-curl', legs.leg_curl, Camera(82, 18), UP_FIRST),
    ('calf-raise', legs.calf_raise, Camera(118, 10), SMALL),
    ('chest-press-machine', press.chest_press_machine, Camera(40, 12), UP_FIRST),
    ('lat-pulldown', pull.lat_pulldown, Camera(132, 8), UP_FIRST),
    ('seated-cable-row', pull.seated_cable_row, Camera(100, 14), UP_FIRST),
    ('triceps-pushdown', arms.triceps_pushdown, Camera(100, 10), UP_FIRST),
    ('cable-fly', press.cable_fly, Camera(16, 10), UP_FIRST),
    ('pull-up', pull.pull_up, Camera(148, 5), UP_FIRST),
    ('push-up', press.push_up, Camera(48, 6), DOWN_FIRST),
    ('dip', press.dip, Camera(52, 10), DOWN_FIRST),
    ('dumbbell-bench-press', press.dumbbell_bench_press, Camera(48, 26), DOWN_FIRST),
    ('incline-bench-press', press.incline_bench_press, Camera(58, 16), DOWN_FIRST),
    ('dumbbell-floor-press', press.dumbbell_floor_press, Camera(54, 28), DOWN_FIRST),
    ('dumbbell-fly', press.dumbbell_fly, Camera(28, 30), DOWN_FIRST),
    ('dumbbell-pullover', press.dumbbell_pullover, Camera(70, 18), DOWN_FIRST),
    ('incline-push-up', press.incline_push_up, Camera(52, 6), DOWN_FIRST),
    ('decline-push-up', press.decline_push_up, Camera(36, 2), DOWN_FIRST),
    ('knee-push-up', press.knee_push_up, Camera(46, 6), DOWN_FIRST),
    ('pec-deck', press.pec_deck, Camera(26, 22), UP_FIRST),
    ('low-cable-fly', press.low_cable_fly, Camera(16, 12), UP_FIRST),
    ('close-grip-bench-press', press.close_grip_bench_press, Camera(72, 20), DOWN_FIRST),
    ('skull-crusher', press.skull_crusher, Camera(78, 16), DOWN_FIRST),
    ('diamond-push-up', press.diamond_push_up, Camera(48, 22), DOWN_FIRST),
    ('bench-dip', press.bench_dip, Camera(76, 12), DOWN_FIRST),
    ('overhead-cable-extension', arms.overhead_cable_extension, Camera(78, 10), UP_FIRST),
    ('triceps-kickback', arms.triceps_kickback, Camera(100, 14), UP_FIRST),
    ('pike-push-up', press.pike_push_up, Camera(70, 14), DOWN_FIRST),
    ('machine-shoulder-press', press.machine_shoulder_press, Camera(36, 8), UP_FIRST),
    ('arnold-press', press.arnold_press, Camera(22, 8), UP_FIRST),
    ('reverse-pec-deck', arms.reverse_pec_deck, Camera(136, 24), UP_FIRST),
    ('front-raise', arms.front_raise, Camera(56, 10), UP_FIRST),
    ('cable-lateral-raise', arms.cable_lateral_raise, Camera(18, 10), UP_FIRST),
    ('barbell-curl', arms.barbell_curl, Camera(50, 10), UP_FIRST),
    ('incline-dumbbell-curl', arms.incline_dumbbell_curl, Camera(66, 12), UP_FIRST),
    ('concentration-curl', arms.concentration_curl, Camera(20, 12), UP_FIRST),
    ('cable-curl', arms.cable_curl, Camera(72, 10), UP_FIRST),
    ('preacher-curl', arms.preacher_curl, Camera(70, 16), UP_FIRST),
    ('reverse-curl', arms.reverse_curl, Camera(64, 10), UP_FIRST),
    ('wrist-curl', arms.wrist_curl, Camera(58, 20), SMALL),
    ('reverse-wrist-curl', arms.reverse_wrist_curl, Camera(62, 22), SMALL),
    ('machine-row', pull.machine_row, Camera(118, 14), UP_FIRST),
    ('chin-up', pull.chin_up, Camera(126, 5), UP_FIRST),
    ('close-grip-pulldown', pull.close_grip_pulldown, Camera(108, 8), UP_FIRST),
    ('straight-arm-pulldown', pull.straight_arm_pulldown, Camera(104, 10), UP_FIRST),
    ('t-bar-row', pull.t_bar_row, Camera(80, 16), UP_FIRST),
    ('chest-supported-row', pull.chest_supported_row, Camera(108, 16), UP_FIRST),
    ('inverted-row', pull.inverted_row, Camera(74, 12), UP_FIRST),
    ('bent-over-dumbbell-row', pull.bent_over_dumbbell_row, Camera(96, 16), UP_FIRST),
    ('back-extension', pull.back_extension, Camera(100, 14), UP_FIRST),
    ('superman', pull.superman, Camera(74, 22), SMALL),
    ('barbell-shrug', pull.barbell_shrug, Camera(160, 12), SMALL),
    ('front-squat', legs.front_squat, Camera(56, 10), DOWN_FIRST),
    ('bodyweight-squat', legs.bodyweight_squat, Camera(58, 10), DOWN_FIRST),
    ('hack-squat', legs.hack_squat, Camera(76, 12), DOWN_FIRST),
    ('sumo-squat', legs.sumo_squat, Camera(24, 10), DOWN_FIRST),
    ('bulgarian-split-squat', legs.bulgarian_split_squat, Camera(70, 10), DOWN_FIRST),
    ('split-squat', legs.split_squat, Camera(70, 10), DOWN_FIRST),
    ('reverse-lunge', legs.reverse_lunge, Camera(64, 10), DOWN_FIRST),
    ('step-up', legs.step_up, Camera(74, 12), UP_FIRST),
    ('lateral-lunge', legs.lateral_lunge, Camera(18, 10), DOWN_FIRST),
    ('sumo-deadlift', legs.sumo_deadlift, Camera(122, 10), UP_FIRST),
    ('dumbbell-romanian-deadlift', legs.dumbbell_romanian_deadlift, Camera(100, 10), DOWN_FIRST),
    ('kettlebell-deadlift', legs.kettlebell_deadlift, Camera(52, 10), UP_FIRST),
    ('single-leg-romanian-deadlift', legs.single_leg_romanian_deadlift, Camera(84, 10), DOWN_FIRST),
    ('seated-leg-curl', legs.seated_leg_curl, Camera(80, 12), UP_FIRST),
    ('glute-bridge', legs.glute_bridge, Camera(82, 16), UP_FIRST),
    ('single-leg-glute-bridge', legs.single_leg_glute_bridge, Camera(84, 16), UP_FIRST),
    ('cable-kickback', legs.cable_kickback, Camera(104, 10), UP_FIRST),
    ('cable-pull-through', legs.cable_pull_through, Camera(96, 10), UP_FIRST),
    ('donkey-kick', legs.donkey_kick, Camera(102, 14), UP_FIRST),
    ('side-lying-leg-raise', legs.side_lying_leg_raise, Camera(100, 22), UP_FIRST),
    ('hip-abduction', legs.hip_abduction, Camera(44, 18), UP_FIRST),
    ('seated-calf-raise', legs.seated_calf_raise, Camera(98, 12), SMALL),
    ('dumbbell-calf-raise', legs.dumbbell_calf_raise, Camera(120, 10), SMALL),
    ('bodyweight-calf-raise', legs.bodyweight_calf_raise, Camera(112, 10), SMALL),
    ('single-leg-calf-raise', legs.single_leg_calf_raise, Camera(116, 10), SMALL),
    ('leg-press-calf-raise', legs.leg_press_calf_raise, Camera(84, 12), SMALL),
    ('crunch', core.crunch, Camera(76, 18), UP_FIRST),
    ('sit-up', core.sit_up, Camera(76, 16), UP_FIRST),
    ('reverse-crunch', core.reverse_crunch, Camera(80, 16), UP_FIRST),
    ('lying-leg-raise', core.lying_leg_raise, Camera(78, 14), UP_FIRST),
    ('bicycle-crunch', core.bicycle_crunch, Camera(60, 30), SIDE_TO_SIDE),
    ('russian-twist', core.russian_twist, Camera(22, 22), SIDE_TO_SIDE),
    ('dead-bug', core.dead_bug, Camera(62, 26), SIDE_TO_SIDE),
    ('bird-dog', core.bird_dog, Camera(78, 14), SIDE_TO_SIDE),
    ('mountain-climber', core.mountain_climber, Camera(76, 16), SIDE_TO_SIDE),
    ('ab-wheel', core.ab_wheel, Camera(80, 14), DOWN_FIRST),
    ('pallof-press', core.pallof_press, Camera(58, 20), UP_FIRST),
    ('woodchop', core.woodchop, Camera(14, 12), UP_FIRST),
    ('hanging-knee-raise', core.hanging_knee_raise, Camera(64, 6), UP_FIRST),
]

CATALOG = Path(__file__).resolve().parents[3] / 'Fitling/Resources/SportCatalog.json'
LISTED = {entry['slug']: entry for entry in json.loads(CATALOG.read_text('utf-8'))['exercises']}
EXERCISES = {
    slug: Motion(LISTED[slug]['id'], pose, tuple(LISTED[slug]['primaryMuscles']), *how)
    for slug, pose, *how in MOVEMENTS
}

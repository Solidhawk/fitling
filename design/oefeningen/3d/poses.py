"""De bewegingen van de geanimeerde oefeningen, als houdingen van 0 (begin) tot 1 (eind).

Zonder Blender, zodat `test_poses.py` ze overal kan toetsen; `render.py` tekent ze. Maten in meters:
het figuur kijkt naar -Y, Z is omhoog en de linkerkant van het figuur is +X.
"""
import math
from dataclasses import dataclass, field
from typing import Callable, NamedTuple

THIGH, SHIN, UPPER, FORE = 0.43, 0.42, 0.29, 0.27
HIP_HALF, SHOULDER_HALF = 0.11, 0.185
TRUNK, HEAD = 0.455, 0.275
ANKLE = 0.095
BENCH_THRUST, BENCH_ROW = 0.39, 0.40
FRAMES, FPS = 40, 25


class V(NamedTuple):
    x: float
    y: float
    z: float

    def __add__(self, other):
        return V(self.x + other[0], self.y + other[1], self.z + other[2])

    def __sub__(self, other):
        return V(self.x - other[0], self.y - other[1], self.z - other[2])

    def __mul__(self, amount):
        return V(self.x * amount, self.y * amount, self.z * amount)

    def dot(self, other):
        return self.x * other[0] + self.y * other[1] + self.z * other[2]

    @property
    def length(self):
        return math.sqrt(self.dot(self))

    def unit(self):
        return self * (1 / self.length)


def mix(a, b, t):
    return a + (b - a) * t


def ease(t):
    return t * t * t * (t * (6 * t - 15) + 10)


def swing_ease(t):
    return (1 - math.cos(math.pi * t)) / 2


def lean(degrees):
    """Straight up, tipped forward by `degrees` (backward when negative)."""
    return V(0, -math.sin(math.radians(degrees)), math.cos(math.radians(degrees)))


def forward(up):
    """The way the body faces when its spine points along `up`."""
    return V(0, -up.z, up.y)


def reach(start, goal, first, second, pole):
    """Middle joint, end joint and how far the goal was out of reach, bending towards `pole`."""
    d = goal - start
    longest, shortest = first + second - 0.0005, abs(first - second) + 0.0005
    distance = min(max(d.length, shortest), longest)
    axis = d.unit()
    x = (first * first - second * second + distance * distance) / (2 * distance)
    side = (pole - axis * pole.dot(axis)).unit()
    middle = start + axis * x + side * math.sqrt(max(first * first - x * x, 0))
    return middle, start + axis * distance, abs(d.length - distance)


@dataclass
class Side:
    hip: V
    knee: V
    ankle: V
    toe: V
    """Where the toes point."""
    sole: V
    """Where the sole faces."""
    shoulder: V
    elbow: V
    wrist: V


@dataclass
class Pose:
    pelvis: V
    waist: V
    neck: V
    head: V
    head_up: V
    sides: dict
    out_of_reach: float
    loads: list = field(default_factory=list)
    """(name, centre, radius) of what must stay above the floor."""
    props: list = field(default_factory=list)
    """What render.py draws besides the figure."""


def body(pelvis, neck, head_up, feet, hands, waist=None):
    """The whole figure. `feet(s)` gives ankle, knee pole, toes and sole, `hands(s)` gives wrist and elbow pole."""
    sides, missed = {}, 0.0
    for s in (-1, 1):
        hip, shoulder = pelvis + (HIP_HALF * s, 0, 0), neck + (SHOULDER_HALF * s, 0, 0)
        ankle, knee_pole, toe, sole = feet(s)
        knee, ankle, foot_miss = reach(hip, ankle, THIGH, SHIN, knee_pole)
        wrist, elbow_pole = hands(s)
        elbow, wrist, hand_miss = reach(shoulder, wrist, UPPER, FORE, elbow_pole)
        sides[s] = Side(hip, knee, ankle, toe, sole, shoulder, elbow, wrist)
        missed = max(missed, foot_miss, hand_miss)
    middle = waist or mix(pelvis, neck, 0.5)
    return Pose(pelvis, middle, neck, neck + head_up * HEAD, head_up, sides, missed)


def standing(width, turn):
    def feet(s):
        toes = V(s * math.sin(math.radians(turn)), -math.cos(math.radians(turn)), 0)
        return V(width * s, 0, ANKLE), toes, toes, V(0, 0, -1)
    return feet


def stack(y, lifted):
    """A cable column with its weights: part of the stack rises as the cable is pulled."""
    parts = [('box', V(0.2 * s, y, 0.98), V(0.055, 0.07, 1.96), 'frame') for s in (-1, 1)]
    parts += [('box', V(0, y, 0.03), V(0.55, 0.3, 0.06), 'frame'), ('box', V(0, y, 1.96), V(0.46, 0.09, 0.07), 'frame')]
    for i in range(9):
        rise = lifted if i >= 4 else 0
        parts.append(('box', V(0, y, 0.11 + 0.06 * i + rise), V(0.31, 0.15, 0.05), 'iron'))
    parts.append(('rod', V(0, y, 0.62 + lifted), V(0, y, 1.93), 0.006, 'iron'))
    return parts


def bench(centre, size):
    parts = [('cushion', centre - (0, 0, 0.035), V(size.x, size.y, 0.07), 'cloth')]
    for a in (-1, 1):
        for b in (-1, 1):
            foot = V(centre.x + a * (size.x / 2 - 0.06), centre.y + b * (size.y / 2 - 0.06), 0.02)
            parts.append(('rod', foot, V(foot.x, foot.y, centre.z - 0.06), 0.025, 'frame'))
    return parts


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
    pose.props = [('barbell', bar)] + bench(V(0, 0.16, BENCH_THRUST), V(0.95, 0.36, 0))
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
    pose.props = [('dumbbell', weight, V(0, 1, 0))] + bench(V(-0.18, -0.06, BENCH_ROW), V(0.26, 1.18, 0))
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
    pose.props = stack(-1.2, 0.28 * k) + [('rod', knot, pulley, 0.006, 'iron'), ('wheel', pulley)]
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
    pose.props = stack(-1.0, 0.34 * k) + [('rod', knot, pulley, 0.006, 'iron'), ('wheel', pulley)]
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
    pose.props = [('rod', bar - (0.62, 0, 0), bar + (0.62, 0, 0), 0.024, 'steel')]
    for s in (-1, 1):
        pose.props += [('rod', V(0.62 * s, 0, 0.03), V(0.62 * s, 0, 2.15), 0.035, 'frame'),
                       ('cushion', V(0.62 * s, 0, 0.03), V(0.12, 0.6, 0.06), 'frame')]
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
    timing: tuple = (30, 10, 34, 11)
    """Frames at 25 per second: to the end, hold, back, rest."""
    curve: Callable[[float], float] = ease

    def sequence(self):
        """Which of the rendered frames is shown at each 25th of a second of one repetition."""
        out, hold, back, rest = self.timing
        last = FRAMES - 1
        shown = [self.curve(i / out) for i in range(out)] + [1.0] * hold
        shown += [1 - self.curve(i / back) for i in range(back)] + [0.0] * rest
        return [round(value * last) for value in shown]


EXERCISES = {
    'hip-thrust': Motion('b8aab0e1-ee00-5090-a682-c687de98b7dd', hip_thrust, ('glutes',),
                         Camera(62, 9), (26, 14, 34, 11)),
    'dumbbell-row': Motion('9a053b3c-5162-57d0-b52c-7381c0f09127', one_arm_row, ('back',),
                                   Camera(62, 20), (26, 10, 34, 11)),
    'goblet-squat': Motion('3b70d0ec-e441-5831-808c-0c025c473ebf', goblet_squat, ('quads', 'glutes'),
                           Camera(66), (33, 8, 27, 17)),
    'face-pull': Motion('35a39c5f-d6d0-55a0-8107-6a62eecab0c8', face_pull, ('shoulders',),
                        Camera(118), (26, 12, 34, 11)),
    'cable-crunch': Motion('1eba5fd1-f1c8-5159-9897-460d3f7a108c', cable_crunch, ('core',),
                           Camera(70), (28, 12, 34, 11)),
    'hanging-leg-raise': Motion('96db441e-09eb-5089-b615-0cefc1a34bb0', hanging_leg_raise, ('core',),
                                Camera(56, 6), (30, 10, 38, 11)),
    'kettlebell-swing': Motion('31fb6913-0785-59a7-83d4-3e50fdf13097', kettlebell_swing, ('glutes', 'hamstrings'),
                               Camera(66), (15, 4, 17, 4), swing_ease),
}

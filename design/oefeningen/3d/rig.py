"""Het figuur en zijn gewrichten, zonder Blender.

Maten in meters: het figuur kijkt naar -Y, Z is omhoog en de linkerkant van het figuur is +X (kant s = 1).
"""
import math
from dataclasses import dataclass, field
from typing import NamedTuple, Optional

THIGH, SHIN, UPPER, FORE = 0.43, 0.42, 0.29, 0.27
HIP_HALF, SHOULDER_HALF = 0.11, 0.185
TRUNK, HEAD = 0.455, 0.275
ANKLE = 0.095
LEG, ARM = 0.846, 0.553
"""Hip to ankle and shoulder to wrist when straight, a hair inside what `reach` allows."""


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


RIGHT = V(1, 0, 0)
DOWN = V(0, 0, -1)
UP = V(0, 0, 1)


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


def sagittal(degrees):
    """A limb's direction in the plane of walking: 0 hangs down, 90 points ahead, 180 up, below 0 behind."""
    return V(0, -math.sin(math.radians(degrees)), -math.cos(math.radians(degrees)))


def limb_front(degrees):
    """The front of a limb that points along `sagittal(degrees)`."""
    return V(0, -math.cos(math.radians(degrees)), math.sin(math.radians(degrees)))


def turned(up, degrees):
    """Across and front of a body twisted round `up` by `degrees`; positive brings the left shoulder forward."""
    angle, front = math.radians(degrees), forward(up)
    return RIGHT * math.cos(angle) + front * math.sin(angle), front * math.cos(angle) - RIGHT * math.sin(angle)


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


def jointed(start, first_direction, second_direction, first, second, straight_pole):
    """The end of a limb given by the directions of its two bones, with the pole that puts its joint there."""
    first_direction, second_direction = first_direction.unit(), second_direction.unit()
    middle = start + first_direction * first
    end = middle + second_direction * second
    axis = (end - start).unit()
    bend = (middle - start) - axis * (middle - start).dot(axis)
    return end, bend if bend.length > 0.004 else straight_pole


def arm(shoulder, upper, fore, straight_pole=V(0, 1, 0)):
    """Wrist and elbow pole, from where the upper arm and the forearm point."""
    return jointed(shoulder, upper, fore, UPPER, FORE, straight_pole)


def leg(hip, thigh, shin, straight_pole=V(0, -1, 0)):
    """Ankle and knee pole, from where the thigh and the shin point."""
    return jointed(hip, thigh, shin, THIGH, SHIN, straight_pole)


def shoulder(neck, s, across=RIGHT):
    return neck + across * (SHOULDER_HALF * s)


def hip(pelvis, s, across=RIGHT):
    return pelvis + across * (HIP_HALF * s)


def hanging(neck, x, y, length=ARM):
    """The height of a weight at arm's length under the shoulder, at `x` and `y`."""
    return neck.z - math.sqrt(max(length ** 2 - (x - SHOULDER_HALF) ** 2 - (y - neck.y) ** 2, 0))


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
    grip: Optional[V] = None
    """Where the hand points, when that is not along the forearm."""


@dataclass
class Pose:
    pelvis: V
    waist: V
    neck: V
    head: V
    head_up: V
    sides: dict
    out_of_reach: float
    hip_across: V = RIGHT
    shoulder_across: V = RIGHT
    """From the figure's right to its left, at the hips and at the shoulders: they differ in a twist."""
    loads: list = field(default_factory=list)
    """(name, centre, radius) of what must stay above the floor."""
    trapezius: bool = False
    """Whether the work of the back is done between neck and shoulders, as in a shrug."""
    props: list = field(default_factory=list)
    """What render.py draws besides the figure."""


def body(pelvis, neck, head_up, feet, hands, waist=None, hip_across=RIGHT, shoulder_across=RIGHT, shrug=0.0):
    """The whole figure. `feet(s)` gives ankle, knee pole, toes and sole, `hands(s)` gives wrist and elbow pole."""
    sides, missed = {}, 0.0
    for s in (-1, 1):
        hip_joint = hip(pelvis, s, hip_across)
        shoulder_joint = shoulder(neck, s, shoulder_across) + (0, 0, shrug)
        ankle, knee_pole, toe, sole = feet(s)
        knee, ankle, foot_miss = reach(hip_joint, ankle, THIGH, SHIN, knee_pole)
        wrist, elbow_pole = hands(s)
        elbow, wrist, hand_miss = reach(shoulder_joint, wrist, UPPER, FORE, elbow_pole)
        sides[s] = Side(hip_joint, knee, ankle, toe, sole, shoulder_joint, elbow, wrist)
        missed = max(missed, foot_miss, hand_miss)
    middle = waist or mix(pelvis, neck, 0.5)
    return Pose(pelvis, middle, neck, neck + head_up * HEAD, head_up, sides, missed, hip_across, shoulder_across)


# Feet

TOES_DOWN = V(0, -0.35, -0.937), V(0, 0.937, -0.35)
"""Toes and sole of a foot standing on its toes behind a body that faces the floor."""
LACES_DOWN = V(0, 1, -0.15).unit(), UP
"""Toes and sole of a foot lying on its laces, as when kneeling."""


def standing(width, turn):
    def feet(s):
        toes = V(s * math.sin(math.radians(turn)), -math.cos(math.radians(turn)), 0)
        return V(width * s, 0, ANKLE), toes, toes, DOWN
    return feet


def flat_foot(x, y, z=ANKLE, knee_pole=V(0, -1, 0)):
    return V(x, y, z), knee_pole, V(0, -1, 0), DOWN


def on_the_ball(x, y, lift, floor=0.0):
    """A foot rolled `lift` degrees up over its ball, which stands at `floor`; `y` is the flat foot's ankle."""
    angle = math.radians(lift)
    toe = V(0, -math.cos(angle), -math.sin(angle))
    sole = V(0, math.sin(angle), -math.cos(angle))
    ball = V(x, y - 0.135, floor + ANKLE - 0.06)
    return ball - toe * 0.135 - sole * 0.06, V(0, -1, 0), toe, sole


def kneeling(width, knee_y=0.0):
    def feet(s):
        return V(width * s, knee_y + 0.42, 0.072), V(0, -1, -1), *LACES_DOWN
    return feet

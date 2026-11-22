"""De houdingen tegen de uitleg in SportCatalog.json.

python -m unittest discover -s design/oefeningen/3d
"""
import json
import math
import unittest
from pathlib import Path

import poses

ROOT = Path(__file__).resolve().parents[3]
CATALOG = {e['id']: e for e in json.loads((ROOT / 'Fitling/Resources/SportCatalog.json').read_text('utf-8'))['exercises']}
STEPS = [i / 100 for i in range(101)]


def distance(a, b):
    return math.dist(tuple(a), tuple(b))


def angle(a, b, c):
    """The angle at b, in degrees."""
    u, v = [p - q for p, q in zip(a, b)], [p - q for p, q in zip(c, b)]
    cosine = sum(p * q for p, q in zip(u, v)) / (math.hypot(*u) * math.hypot(*v))
    return math.degrees(math.acos(max(-1, min(1, cosine))))


def track(slug):
    return [poses.EXERCISES[slug].pose(k) for k in STEPS]


def ends(slug):
    motion = poses.EXERCISES[slug]
    return motion.pose(0), motion.pose(1)


class EveryMotion(unittest.TestCase):
    def test_every_animation_has_its_own_exercise_and_muscles(self):
        for slug, motion in poses.EXERCISES.items():
            self.assertEqual(CATALOG[motion.id]['slug'], slug)
            self.assertEqual(set(motion.muscles), set(CATALOG[motion.id]['primaryMuscles']), slug)

    def test_limbs_keep_their_length(self):
        for slug in poses.EXERCISES:
            for pose in track(slug):
                for s in (-1, 1):
                    limb = pose.sides[s]
                    for a, b, length in ((limb.hip, limb.knee, poses.THIGH), (limb.knee, limb.ankle, poses.SHIN),
                                         (limb.shoulder, limb.elbow, poses.UPPER), (limb.elbow, limb.wrist, poses.FORE)):
                        self.assertAlmostEqual(distance(a, b), length, delta=0.002, msg=slug)

    def test_hands_and_feet_reach_where_they_are_meant_to_be(self):
        for slug in poses.EXERCISES:
            for pose in track(slug):
                self.assertLess(pose.out_of_reach, 0.004, slug)

    def test_nothing_goes_through_the_floor(self):
        for slug in poses.EXERCISES:
            for pose in track(slug):
                self.assertGreater(pose.pelvis[2], 0.12, slug)
                self.assertGreater(pose.head[2], 0.15, slug)
                for s in (-1, 1):
                    for point in (pose.sides[s].knee, pose.sides[s].ankle, pose.sides[s].wrist):
                        self.assertGreater(point[2], 0.055, slug)
                for name, point, radius in pose.loads:
                    self.assertGreaterEqual(point[2] - radius, 0, f'{slug}: {name}')

    def test_the_movement_has_no_jumps(self):
        for slug in poses.EXERCISES:
            frames = track(slug)
            for before, after in zip(frames, frames[1:]):
                for s in (-1, 1):
                    for part in ('knee', 'ankle', 'elbow', 'wrist'):
                        step = distance(getattr(before.sides[s], part), getattr(after.sides[s], part))
                        self.assertLess(step, 0.05, f'{slug}: {part}')

    def test_the_loop_shows_both_ends_and_closes(self):
        for slug, motion in poses.EXERCISES.items():
            sequence = motion.sequence()
            self.assertEqual((min(sequence), max(sequence)), (0, poses.FRAMES - 1), slug)
            for before, after in zip(sequence, sequence[1:] + sequence[:1]):
                self.assertLessEqual(abs(after - before), 6, slug)


class GobletSquat(unittest.TestCase):
    def test_deep_with_the_elbows_between_the_knees(self):
        _, deep = ends('goblet-squat')
        for s in (-1, 1):
            self.assertLess(deep.sides[s].hip[2], deep.sides[s].knee[2])
            self.assertLess(abs(deep.sides[s].elbow[0]), abs(deep.sides[s].knee[0]))

    def test_back_up_straight(self):
        up, _ = ends('goblet-squat')
        self.assertGreater(angle(up.sides[1].hip, up.sides[1].knee, up.sides[1].ankle), 165)

    def test_feet_stay_put(self):
        frames = track('goblet-squat')
        for pose in frames:
            self.assertLess(distance(pose.sides[1].ankle, frames[0].sides[1].ankle), 0.002)


class HipThrust(unittest.TestCase):
    def test_a_straight_line_from_shoulders_to_knees_at_the_top(self):
        _, top = ends('hip-thrust')
        knee = [(p + q) / 2 for p, q in zip(top.sides[-1].knee, top.sides[1].knee)]
        self.assertGreater(angle(top.neck, top.pelvis, knee), 172)

    def test_shins_upright_at_the_top(self):
        _, top = ends('hip-thrust')
        self.assertLess(abs(top.sides[1].knee[1] - top.sides[1].ankle[1]), 0.06)

    def test_the_hips_do_the_lifting(self):
        low, top = ends('hip-thrust')
        self.assertGreater(top.pelvis[2] - low.pelvis[2], 0.2)

    def test_hands_stay_on_the_bar(self):
        for pose in track('hip-thrust'):
            bar = next(point for name, point, _ in pose.loads if name == 'barbell')
            for s in (-1, 1):
                self.assertLess(distance(pose.sides[s].wrist[1:], bar[1:]), 0.05)


class OneArmRow(unittest.TestCase):
    def test_hand_and_knee_rest_on_the_bench(self):
        for pose in track('dumbbell-row'):
            self.assertAlmostEqual(pose.sides[-1].knee[2], poses.BENCH_ROW + 0.06, delta=0.03)
            self.assertAlmostEqual(pose.sides[-1].wrist[2], poses.BENCH_ROW + 0.04, delta=0.01)

    def test_from_a_straight_arm_to_the_hip(self):
        low, top = ends('dumbbell-row')
        self.assertGreater(angle(low.sides[1].shoulder, low.sides[1].elbow, low.sides[1].wrist), 160)
        self.assertLess(distance(top.sides[1].wrist, top.sides[1].hip), 0.23)

    def test_the_back_stays_still_and_flat(self):
        low, top = ends('dumbbell-row')
        self.assertLess(distance(low.neck, top.neck), 0.002)
        self.assertLess(abs(low.neck[2] - low.pelvis[2]), 0.15)


class FacePull(unittest.TestCase):
    def test_to_the_face_with_high_elbows(self):
        _, pulled = ends('face-pull')
        for s in (-1, 1):
            self.assertLess(abs(pulled.sides[s].wrist[2] - pulled.head[2]), 0.08)
            self.assertGreaterEqual(pulled.sides[s].elbow[2], pulled.sides[s].shoulder[2])
            self.assertGreater(abs(pulled.sides[s].elbow[0]), 0.36)

    def test_the_arms_reach_forward_first(self):
        away, _ = ends('face-pull')
        self.assertGreater(angle(away.sides[1].shoulder, away.sides[1].elbow, away.sides[1].wrist), 150)


class CableCrunch(unittest.TestCase):
    def test_kneeling_with_the_hips_still(self):
        frames = track('cable-crunch')
        for pose in frames:
            self.assertLess(pose.sides[1].knee[2], 0.1)
            self.assertLess(distance(pose.pelvis, frames[0].pelvis), 0.002)

    def test_the_back_rolls_down(self):
        up, down = ends('cable-crunch')
        self.assertGreater(up.head[2] - down.head[2], 0.45)
        self.assertLess(angle(down.pelvis, down.waist, down.neck), 150)

    def test_the_rope_stays_by_the_head(self):
        for pose in track('cable-crunch'):
            for s in (-1, 1):
                self.assertLess(distance(pose.sides[s].wrist, pose.head), 0.24)


class HangingLegRaise(unittest.TestCase):
    def test_legs_to_hip_height(self):
        _, up = ends('hanging-leg-raise')
        self.assertLess(abs(up.sides[1].ankle[2] - up.sides[1].hip[2]), 0.1)

    def test_no_swinging(self):
        frames = track('hanging-leg-raise')
        for pose in frames:
            self.assertLess(distance(pose.neck, frames[0].neck), 0.002)
            self.assertLess(distance(pose.sides[1].wrist, frames[0].sides[1].wrist), 0.002)
            self.assertGreater(angle(pose.sides[1].hip, pose.sides[1].knee, pose.sides[1].ankle), 160)

    def test_the_feet_are_off_the_floor(self):
        self.assertGreater(ends('hanging-leg-raise')[0].sides[1].ankle[2], 0.2)


class KettlebellSwing(unittest.TestCase):
    def test_starts_between_the_legs_with_the_hips_back(self):
        low, _ = ends('kettlebell-swing')
        self.assertGreater(low.sides[1].wrist[1], low.sides[1].knee[1])
        self.assertLess(abs(low.sides[1].wrist[0]), abs(low.sides[1].knee[0]) - 0.07)
        self.assertGreater(low.pelvis[1], low.sides[1].ankle[1] + 0.15)

    def test_to_chest_height_standing_straight(self):
        _, top = ends('kettlebell-swing')
        self.assertTrue(top.pelvis[2] + 0.25 < top.sides[1].wrist[2] < top.neck[2] + 0.05)
        self.assertGreater(angle(top.sides[1].hip, top.sides[1].knee, top.sides[1].ankle), 160)

    def test_the_arms_stay_straight(self):
        for pose in track('kettlebell-swing'):
            self.assertGreater(angle(pose.sides[1].shoulder, pose.sides[1].elbow, pose.sides[1].wrist), 150)

    def test_the_hips_lead_the_bell(self):
        low, top = ends('kettlebell-swing')
        middle = poses.EXERCISES['kettlebell-swing'].pose(0.5)

        def done(value):
            return (value(middle) - value(low)) / (value(top) - value(low))
        self.assertGreater(done(lambda pose: pose.pelvis[2]), done(lambda pose: pose.sides[1].wrist[2]))


if __name__ == '__main__':
    unittest.main()

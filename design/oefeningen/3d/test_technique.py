"""Elke oefening uit de catalogus: het juiste gewricht beweegt, wat stil hoort blijft stil, niets loopt door het lijf.

python -m unittest discover -s design/oefeningen/3d
"""
import json
import math
import unittest
from itertools import combinations
from pathlib import Path

import poses

ROOT = Path(__file__).resolve().parents[3]
CATALOG = {e['slug']: e for e in
           json.loads((ROOT / 'Fitling/Resources/SportCatalog.json').read_text('utf-8'))['exercises']}
STEPS = [i / 40 for i in range(41)]


def words(text):
    return tuple(text.split())


# The joint that does the work, with how far it moves at least.
WORKS = {
    ('elbow', 55): words('''
        bench-press dumbbell-bench-press incline-bench-press incline-dumbbell-press dumbbell-floor-press
        close-grip-bench-press skull-crusher chest-press-machine push-up incline-push-up decline-push-up
        knee-push-up diamond-push-up pike-push-up bench-dip dip overhead-press dumbbell-shoulder-press
        machine-shoulder-press arnold-press barbell-row bent-over-dumbbell-row dumbbell-row t-bar-row
        chest-supported-row seated-cable-row machine-row inverted-row lat-pulldown close-grip-pulldown pull-up
        chin-up barbell-curl dumbbell-curl hammer-curl reverse-curl incline-dumbbell-curl concentration-curl
        cable-curl preacher-curl triceps-pushdown overhead-cable-extension overhead-triceps-extension
        triceps-kickback face-pull pallof-press'''),
    ('shoulder', 30): words('''
        dumbbell-fly pec-deck reverse-pec-deck cable-fly low-cable-fly dumbbell-pullover rear-delt-fly lateral-raise
        cable-lateral-raise front-raise straight-arm-pulldown woodchop ab-wheel'''),
    ('knee', 45): words('''
        back-squat front-squat goblet-squat bodyweight-squat hack-squat sumo-squat bulgarian-split-squat split-squat
        walking-lunge reverse-lunge step-up lateral-lunge leg-press leg-extension leg-curl seated-leg-curl deadlift
        sumo-deadlift kettlebell-deadlift'''),
    ('hip', 18): words('''
        hip-thrust glute-bridge single-leg-glute-bridge cable-pull-through kettlebell-swing romanian-deadlift
        dumbbell-romanian-deadlift single-leg-romanian-deadlift back-extension cable-kickback donkey-kick crunch
        sit-up reverse-crunch lying-leg-raise hanging-leg-raise hanging-knee-raise bicycle-crunch dead-bug bird-dog
        mountain-climber cable-crunch superman'''),
    ('apart', 0.15): words('hip-abduction side-lying-leg-raise'),
    ('foot', 14): words('calf-raise seated-calf-raise dumbbell-calf-raise bodyweight-calf-raise '
                        'single-leg-calf-raise leg-press-calf-raise'),
    ('grip', 40): words('wrist-curl reverse-wrist-curl'),
    ('shrug', 0.035): words('barbell-shrug'),
    ('twist', 45): words('russian-twist'),
}
# What may not move, with the most it may.
STILL = {
    ('elbow', 16): words('''
        dumbbell-fly lateral-raise cable-lateral-raise rear-delt-fly front-raise straight-arm-pulldown
        kettlebell-swing deadlift sumo-deadlift romanian-deadlift dumbbell-romanian-deadlift barbell-shrug'''),
    ('shoulder', 16): words('''
        barbell-curl dumbbell-curl hammer-curl reverse-curl preacher-curl cable-curl concentration-curl
        incline-dumbbell-curl triceps-pushdown triceps-kickback overhead-triceps-extension'''),
    ('trunk', 4): words('''
        bench-press dumbbell-bench-press incline-bench-press overhead-press barbell-row bent-over-dumbbell-row
        t-bar-row chest-supported-row barbell-curl dumbbell-curl hammer-curl lateral-raise front-raise
        triceps-pushdown leg-extension leg-curl seated-leg-curl'''),
    ('knee', 12): words('lying-leg-raise straight-arm-pulldown barbell-row hanging-leg-raise donkey-kick'),
}
PLANTED = words('''back-squat front-squat goblet-squat bodyweight-squat sumo-squat deadlift sumo-deadlift
    kettlebell-deadlift romanian-deadlift dumbbell-romanian-deadlift barbell-row barbell-curl lateral-raise''')
HANDS_FIXED = words('''pull-up chin-up dip bench-dip push-up incline-push-up decline-push-up knee-push-up
    diamond-push-up pike-push-up inverted-row hanging-leg-raise hanging-knee-raise mountain-climber''')
STRAIGHT_BODY = words('push-up incline-push-up decline-push-up diamond-push-up inverted-row')
TO_KNEE_HEIGHT = words('back-squat front-squat goblet-squat bodyweight-squat')


def distance(a, b):
    return math.dist(tuple(a), tuple(b))


def between(u, v):
    cosine = sum(p * q for p, q in zip(u, v)) / (math.hypot(*u) * math.hypot(*v))
    return math.degrees(math.acos(max(-1, min(1, cosine))))


def minus(a, b):
    return tuple(p - q for p, q in zip(a, b))


def angle(a, b, c):
    return between(minus(a, b), minus(c, b))


def measured(pose, what, s):
    side = pose.sides[s]
    if what == 'elbow':
        return angle(side.shoulder, side.elbow, side.wrist)
    if what == 'knee':
        return angle(side.hip, side.knee, side.ankle)
    if what == 'hip':
        return angle(pose.neck, pose.pelvis, side.knee)
    if what == 'apart':
        return distance(pose.sides[-1].ankle, pose.sides[1].ankle)
    if what == 'foot':
        return between(minus(side.knee, side.ankle), side.toe)
    if what == 'shrug':
        return side.shoulder[2] - pose.neck[2]
    raise ValueError(what)


def travel(start, end, what):
    """How much `what` changes from start to end, on the side where it changes most."""
    if what == 'trunk':
        return between(minus(start.neck, start.pelvis), minus(end.neck, end.pelvis))
    if what == 'twist':
        return between(minus(start.sides[1].shoulder, start.sides[-1].shoulder),
                       minus(end.sides[1].shoulder, end.sides[-1].shoulder))
    if what == 'shoulder':
        # The upper arm's own turn: an angle with the trunk does not see a fly open and close.
        return max(between(minus(start.sides[s].elbow, start.sides[s].shoulder),
                           minus(end.sides[s].elbow, end.sides[s].shoulder)) for s in (-1, 1))
    if what == 'grip':
        return max(between(start.sides[s].grip, end.sides[s].grip) for s in (-1, 1))
    return max(abs(measured(end, what, s) - measured(start, what, s)) for s in (-1, 1))


def to_segment(point, a, b):
    along = minus(b, a)
    t = sum(p * q for p, q in zip(minus(point, a), along)) / sum(q * q for q in along)
    nearest = [p + q * max(0, min(1, t)) for p, q in zip(a, along)]
    return distance(point, nearest)


class TheCatalogue(unittest.TestCase):
    def test_eighty_new_exercises_on_top_of_the_thirty_three(self):
        self.assertEqual(len(CATALOG), 113)

    def test_every_exercise_has_an_animation_and_every_animation_an_exercise(self):
        self.assertEqual(sorted(poses.EXERCISES), sorted(CATALOG))
        for slug, motion in poses.EXERCISES.items():
            self.assertEqual(motion.id, CATALOG[slug]['id'], slug)
            self.assertEqual(set(motion.muscles), set(CATALOG[slug]['primaryMuscles']), slug)

    def test_every_exercise_says_here_what_moves(self):
        said = [slug for slugs in WORKS.values() for slug in slugs]
        self.assertEqual(len(said), len(set(said)))
        self.assertEqual(sorted(said), sorted(CATALOG))

    def test_no_two_exercises_show_the_same_movement(self):
        shown = {}
        for slug, motion in poses.EXERCISES.items():
            ends = []
            for k in (0, 1):
                pose = motion.pose(k)
                ends += [(tuple(round(c, 2) for c in point)) for s in (-1, 1) for point in
                         (pose.sides[s].knee, pose.sides[s].ankle, pose.sides[s].elbow, pose.sides[s].wrist)]
                ends += [str(prop[0]) for prop in pose.props]
            shown[slug] = ends
        for one, other in combinations(shown, 2):
            self.assertNotEqual(shown[one], shown[other], f'{one} = {other}')


class Technique(unittest.TestCase):
    def ends(self, slug):
        self.assertIn(slug, poses.EXERCISES)
        motion = poses.EXERCISES[slug]
        return motion.pose(0), motion.pose(1)

    def track(self, slug):
        self.assertIn(slug, poses.EXERCISES)
        return [poses.EXERCISES[slug].pose(k) for k in STEPS]

    def test_the_working_joint_moves(self):
        for (what, least), slugs in WORKS.items():
            for slug in slugs:
                with self.subTest(slug, what=what):
                    self.assertGreaterEqual(travel(*self.ends(slug), what), least)

    def test_what_should_be_still_is_still(self):
        for (what, most), slugs in STILL.items():
            for slug in slugs:
                with self.subTest(slug, what=what):
                    self.assertLessEqual(travel(*self.ends(slug), what), most)

    def test_planted_feet_stay_put(self):
        for slug in PLANTED:
            with self.subTest(slug):
                frames = self.track(slug)
                for pose in frames:
                    for s in (-1, 1):
                        self.assertLess(distance(pose.sides[s].ankle, frames[0].sides[s].ankle), 0.003)

    def test_hands_on_a_bar_bench_or_floor_stay_put(self):
        for slug in HANDS_FIXED:
            with self.subTest(slug):
                frames = self.track(slug)
                for pose in frames:
                    for s in (-1, 1):
                        self.assertLess(distance(pose.sides[s].wrist, frames[0].sides[s].wrist), 0.005)

    def test_the_body_is_one_line(self):
        for slug in STRAIGHT_BODY:
            with self.subTest(slug):
                for pose in self.track(slug):
                    ankles = [(p + q) / 2 for p, q in zip(pose.sides[-1].ankle, pose.sides[1].ankle)]
                    self.assertGreater(angle(pose.neck, pose.pelvis, ankles), 165)

    def test_squats_reach_knee_height(self):
        for slug in TO_KNEE_HEIGHT:
            with self.subTest(slug):
                low = self.ends(slug)[1].sides[1]
                self.assertLessEqual(low.hip[2], low.knee[2] + 0.05)

    def test_a_barbell_stays_level(self):
        for slug, exercise in CATALOG.items():
            if exercise['equipment'] != 'barbell' or slug not in poses.EXERCISES:
                continue
            with self.subTest(slug):
                for pose in self.track(slug):
                    self.assertAlmostEqual(pose.sides[-1].wrist[2], pose.sides[1].wrist[2], delta=0.005)

    def test_the_equipment_of_the_exercise_is_in_the_picture(self):
        needed = {'barbell': {'barbell', 'plate'}, 'dumbbell': {'dumbbell'}, 'kettlebell': {'kettlebell'},
                  'cable': {'wheel'}}
        for slug, exercise in CATALOG.items():
            if exercise['equipment'] in needed:
                with self.subTest(slug):
                    kinds = {prop[0] for prop in self.ends(slug)[0].props}
                    self.assertTrue(kinds & needed[exercise['equipment']], kinds)

    def test_no_hand_elbow_or_knee_inside_the_head_or_the_trunk(self):
        for slug in poses.EXERCISES:
            with self.subTest(slug):
                for pose in self.track(slug):
                    low, high = pose.pelvis, [p + (q - p) * 0.85 for p, q in zip(pose.pelvis, pose.neck)]
                    for s in (-1, 1):
                        side = pose.sides[s]
                        for part in ('wrist', 'elbow', 'knee'):
                            self.assertGreater(distance(getattr(side, part), pose.head), 0.13, part)
                        for part in ('wrist', 'elbow'):
                            self.assertGreater(to_segment(getattr(side, part), low, high), 0.095, part)


if __name__ == '__main__':
    unittest.main()

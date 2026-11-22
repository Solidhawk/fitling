"""De bestanden in de app tegen poses.py: `python build.py` is gedraaid na een wijziging in de timing."""
import json
import unittest
from pathlib import Path

import poses

FOLDER = Path(__file__).resolve().parents[3] / 'Fitling/Resources/ExerciseAnimations'


class Bundle(unittest.TestCase):
    def test_the_timing_in_the_app_is_the_timing_of_the_poses(self):
        manifest = json.loads((FOLDER / 'ExerciseAnimations.json').read_text('utf-8'))
        self.assertEqual(manifest['fps'], poses.FPS)
        self.assertEqual(manifest['frames'], poses.FRAMES)
        self.assertEqual(manifest['animations'], {m.id: m.sequence() for m in poses.EXERCISES.values()})

    def test_every_animation_has_its_picture_and_stays_small(self):
        for slug, motion in poses.EXERCISES.items():
            size = (FOLDER / f'{motion.id}.webp').stat().st_size
            self.assertLess(size, 450_000, slug)


if __name__ == '__main__':
    unittest.main()

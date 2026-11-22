"""De schaduw uit build.py loopt zonder zichtbare ringen uit (Pillow nodig, anders overgeslagen)."""
import unittest

try:
    from PIL import Image

    import build
except ImportError:
    Image = None


@unittest.skipIf(Image is None, 'Pillow ontbreekt')
class Shadow(unittest.TestCase):
    def test_a_soft_shadow_has_no_rings(self):
        # Black with an alpha that runs out from 150 to 0: what the shadow catcher renders.
        frame = Image.new('RGBA', (440, 330))
        frame.putdata([(0, 0, 0, round(150 * max(0, 1 - abs(x - 220) / 180))) for _ in range(330) for x in range(440)])
        alpha = build.clean(frame, build.edge_fade(440, 330)).getchannel('A')
        levels = sorted({alpha.getpixel((x, 165)) for x in range(440)})
        self.assertGreater(len(levels), 12)
        for lower, higher in zip(levels, levels[1:]):
            self.assertLessEqual(higher - lower, 5, 'a step this big shows as a ring on white')


if __name__ == '__main__':
    unittest.main()

"""Banken, kabels en toestellen als onderdelen voor render.py."""
from rig import RIGHT, UP, V, mix


def bench(centre, size):
    """A padded bench; `centre` is the middle of its top."""
    parts = [('cushion', centre - (0, 0, 0.035), V(size.x, size.y, 0.07), 'cloth')]
    for a in (-1, 1):
        for b in (-1, 1):
            foot = V(centre.x + a * (size.x / 2 - 0.06), centre.y + b * (size.y / 2 - 0.06), 0.02)
            parts.append(('rod', foot, V(foot.x, foot.y, centre.z - 0.06), 0.025, 'frame'))
    return parts


def stack(y, lifted, x=0.0, sideways=False):
    """A cable column with its weights: part of the stack rises as the cable is pulled."""
    def size(wide, deep, high):
        return V(deep, wide, high) if sideways else V(wide, deep, high)

    along = V(0, 1, 0) if sideways else RIGHT
    middle = V(x, y, 0)
    parts = [('box', middle + along * (0.2 * s) + (0, 0, 0.98), size(0.055, 0.07, 1.96), 'frame') for s in (-1, 1)]
    parts += [('box', middle + (0, 0, 0.03), size(0.55, 0.3, 0.06), 'frame'),
              ('box', middle + (0, 0, 1.96), size(0.46, 0.09, 0.07), 'frame')]
    for i in range(9):
        rise = lifted if i >= 4 else 0
        parts.append(('box', middle + (0, 0, 0.11 + 0.06 * i + rise), size(0.31, 0.15, 0.05), 'iron'))
    parts.append(('rod', middle + (0, 0, 0.62 + lifted), middle + (0, 0, 1.93), 0.006, 'iron'))
    return parts


def cable(pulley, end, axle=RIGHT):
    return [('wheel', pulley, axle), ('rod', pulley, end, 0.006, 'iron')]


def rope(knot, hands):
    return [('rod', hand, knot, 0.014, 'rope') for hand in hands]


def handle(centre, axis, half=0.07):
    return [('rod', centre - axis * half, centre + axis * half, 0.02, 'steel')]


def back_rest(pelvis, up, front, top=0.72, bottom=0.02, width=0.3):
    """A pad against the back of a body that sits or lies along `up`."""
    low, high = pelvis - front * 0.17 + up * bottom, pelvis - front * 0.17 + up * top
    prop_up = mix(low, high, 0.45) - front * 0.04
    foot = V(0, prop_up.y + 0.1, 0.03)
    return [('slab', low, high, front, width, 0.07, 'cloth'), ('rod', prop_up, foot, 0.03, 'frame'),
            ('box', V(0, foot.y, 0.025), V(0.46, 0.09, 0.05), 'frame')]


def seat(pelvis, deep=0.36, wide=0.36):
    """What someone with their hips at `pelvis` sits on."""
    top = pelvis.z - 0.13
    return [('cushion', V(pelvis.x, pelvis.y - 0.03, top - 0.035), V(wide, deep, 0.07), 'cloth'),
            ('rod', V(pelvis.x, pelvis.y, 0.03), V(pelvis.x, pelvis.y, top - 0.05), 0.04, 'frame'),
            ('box', V(pelvis.x, pelvis.y, 0.025), V(0.44, 0.42, 0.05), 'frame')]


def high_bar(height, half=0.62, y=0.0):
    parts = [('rod', V(-half, y, height), V(half, y, height), 0.024, 'steel')]
    for s in (-1, 1):
        parts += [('rod', V(half * s, y, 0.03), V(half * s, y, height), 0.035, 'frame'),
                  ('cushion', V(half * s, y, 0.03), V(0.12, 0.6, 0.06), 'frame')]
    return parts


def step(y, height, wide=0.5):
    """A low block to stand on with the ball of the foot."""
    return [('cushion', V(0, y, height / 2), V(wide, 0.16, height), 'frame')]


def post(x, y, height):
    return [('rod', V(x, y, 0.03), V(x, y, height), 0.032, 'frame'),
            ('box', V(x, y, 0.025), V(0.2, 0.2, 0.05), 'frame'),
            ('ball', V(x, y, height), 0.05, 'iron')]


def wall(y, height=1.75):
    return [('box', V(0, y, height / 2), V(0.85, 0.06, height), 'frame')]


def pad(centre, half=0.11, axis=RIGHT, radius=0.055):
    """A roller."""
    return [('rod', centre - axis * half, centre + axis * half, radius, 'cloth')]


def floor_frame(x, y, top):
    """An upright on a foot, for what hangs from a machine."""
    low = V(x, y, 0.03)
    return [('rod', low, low + UP * (top - 0.03), 0.035, 'frame'), ('box', V(x, y, 0.025), V(0.14, 0.4, 0.05), 'frame')]

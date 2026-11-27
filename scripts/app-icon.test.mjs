import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

// The app icon (UNFORGET S37): option 10 "Collectie", drawn by design/icoon/maak_icoon.py in light, dark and tinted.
const root = new URL('../', import.meta.url);
const set = new URL('Fitling/Resources/Assets.xcassets/AppIcon.appiconset/', root);

/** Width, height and colour type from a PNG's IHDR chunk; fails for anything that is no PNG. */
async function png(url) {
  const bytes = await readFile(url);
  assert.deepEqual([...bytes.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20), colourType: bytes[25] };
}

test('theAppIconHasALightADarkAndATintedVersion', async () => {
  const contents = JSON.parse(await readFile(new URL('Contents.json', set), 'utf8'));
  assert.deepEqual(contents.images, [
    { filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    {
      appearances: [{ appearance: 'luminosity', value: 'dark' }],
      filename: 'AppIcon-dark.png',
      idiom: 'universal',
      platform: 'ios',
      size: '1024x1024',
    },
    {
      appearances: [{ appearance: 'luminosity', value: 'tinted' }],
      filename: 'AppIcon-tinted.png',
      idiom: 'universal',
      platform: 'ios',
      size: '1024x1024',
    },
  ]);
  for (const image of contents.images) {
    // Colour type 2 is RGB without alpha: the App Store refuses an icon with an alpha channel.
    assert.deepEqual(await png(new URL(image.filename, set)), { width: 1024, height: 1024, colourType: 2 });
  }
});

test('theAppNamesItsIcon', async () => {
  const project = await readFile(new URL('project.yml', root), 'utf8');
  assert.match(project, /^\s+ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon$/m);
});

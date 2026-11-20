import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validate, seedSQL } from './sport-seed.mjs';

const catalog = JSON.parse(readFileSync(new URL('../Fitling/Resources/SportCatalog.json', import.meta.url), 'utf8'));
const copy = () => structuredClone(catalog);

test('de catalogus klopt', () => {
  assert.deepEqual(validate(catalog), []);
});

test('de drie schema\'s uit PROMPT.md staan erin', () => {
  assert.deepEqual(catalog.programs.map((p) => p.daysPerWeek), [3, 4, 6]);
});

test('een verwijzing naar een onbekende oefening valt op', () => {
  const broken = copy();
  broken.programs[0].days[0].exercises[0].exerciseID = '00000000-0000-0000-0000-000000000000';
  assert.match(validate(broken).join('\n'), /onbekende oefening/);
});

test('een stap die niet bij het materiaal past valt op', () => {
  const broken = copy();
  broken.exercises.find((e) => e.equipment === 'dumbbell').defaultStepKg = 2.5;
  assert.match(validate(broken).join('\n'), /past niet bij dumbbell/);
});

test('een ontbrekende vertaling valt op', () => {
  const broken = copy();
  broken.exercises[0].instructions.de = '';
  assert.match(validate(broken).join('\n'), /geen tekst in de/);
});

test('een dubbel id valt op', () => {
  const broken = copy();
  broken.programs[1].id = broken.programs[0].id;
  assert.match(validate(broken).join('\n'), /komt twee keer voor/);
});

test('aanhalingstekens in teksten worden ontsnapt', () => {
  const quoted = copy();
  quoted.exercises[0].name.en = "Lifter's squat";
  assert.match(seedSQL(quoted), /Lifter''s squat/);
});

test('elke regel van de seed heeft een even aantal aanhalingstekens', () => {
  for (const line of seedSQL(catalog).split('\n').filter((l) => !l.startsWith('--'))) {
    assert.equal((line.match(/'/g) ?? []).length % 2, 0, line.slice(0, 80));
  }
});

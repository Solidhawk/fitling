#!/usr/bin/env node
// Schrijft supabase/seed/sport.sql uit Fitling/Resources/SportCatalog.json: de gedeelde oefeningen en
// de kant-en-klare schema's (TASKS 4.1). De app leest hetzelfde bestand, zodat de rijen op de server
// en op het toestel dezelfde id's hebben. Met --check faalt het script als sport.sql verouderd is.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const LANGUAGES = ['nl', 'en', 'de'];
export const STEP_BY_EQUIPMENT = { barbell: 2.5, dumbbell: 2, machine: 5, cable: 5, kettlebell: 4, bodyweight: 2.5 };
export const MUSCLES = ['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms', 'core', 'glutes', 'quads', 'hamstrings', 'calves'];
// Eén vaste tijd per versie van de catalogus: een nieuwe versie overschrijft de rijen op de server.
const UPDATED_AT = (version) => `2026-11-19T00:00:00Z'::timestamptz + interval '${version - 1} seconds`;

const literal = (text) => `'${String(text).replaceAll("'", "''")}'`;
const json = (value) => `${literal(JSON.stringify(value))}::jsonb`;
const textArray = (items) => `array[${items.map(literal).join(', ')}]::text[]`;

/** Problems with the catalogue, empty when it is consistent. */
export function validate(catalog) {
  const problems = [];
  const ids = new Set();
  const unique = (id, what) => {
    if (ids.has(id)) problems.push(`${what}: id ${id} komt twee keer voor`);
    ids.add(id);
  };
  const translated = (texts, what) => {
    for (const language of LANGUAGES) {
      if (typeof texts?.[language] !== 'string' || texts[language].trim() === '') problems.push(`${what}: geen tekst in ${language}`);
    }
  };
  const exercises = new Map();
  for (const exercise of catalog.exercises) {
    const what = `oefening ${exercise.slug}`;
    unique(exercise.id, what);
    exercises.set(exercise.id, exercise);
    translated(exercise.name, `${what} (naam)`);
    translated(exercise.instructions, `${what} (instructies)`);
    if (!['compound', 'isolation'].includes(exercise.kind)) problems.push(`${what}: onbekend soort ${exercise.kind}`);
    if (!['external', 'bodyweight'].includes(exercise.loadType)) problems.push(`${what}: onbekende belasting ${exercise.loadType}`);
    if (STEP_BY_EQUIPMENT[exercise.equipment] === undefined) problems.push(`${what}: onbekend materiaal ${exercise.equipment}`);
    else if (exercise.defaultStepKg !== STEP_BY_EQUIPMENT[exercise.equipment]) {
      problems.push(`${what}: stap ${exercise.defaultStepKg} kg past niet bij ${exercise.equipment}`);
    }
    if (exercise.primaryMuscles.length === 0) problems.push(`${what}: geen spiergroep`);
    for (const muscle of [...exercise.primaryMuscles, ...exercise.secondaryMuscles]) {
      if (!MUSCLES.includes(muscle)) problems.push(`${what}: onbekende spiergroep ${muscle}`);
    }
  }
  for (const program of catalog.programs) {
    const what = `schema ${program.slug}`;
    unique(program.id, what);
    translated(program.name, what);
    if (program.days.length !== program.daysPerWeek) problems.push(`${what}: ${program.days.length} dagen voor ${program.daysPerWeek} per week`);
    for (const day of program.days) {
      unique(day.id, `${what}, dag ${day.position}`);
      translated(day.name, `${what}, dag ${day.position}`);
      if (day.exercises.length === 0) problems.push(`${what}, dag ${day.position}: geen oefeningen`);
      for (const item of day.exercises) {
        const where = `${what}, dag ${day.position}, oefening ${item.position}`;
        unique(item.id, where);
        if (!exercises.has(item.exerciseID)) problems.push(`${where}: onbekende oefening ${item.exerciseID}`);
        if (!(item.targetSets >= 1 && item.targetSets <= 10)) problems.push(`${where}: ${item.targetSets} sets`);
        if (!(item.repMin >= 1 && item.repMin <= item.repMax && item.repMax <= 100)) problems.push(`${where}: herhalingen ${item.repMin}-${item.repMax}`);
        if (!(item.restSeconds >= 0 && item.restSeconds <= 900)) problems.push(`${where}: rust ${item.restSeconds} s`);
      }
    }
  }
  return problems;
}

export function seedSQL(catalog) {
  const updatedAt = `'${UPDATED_AT(catalog.version)}`;
  const lines = [
    '-- Gemaakt door scripts/sport-seed.mjs uit Fitling/Resources/SportCatalog.json. Niet met de hand aanpassen.',
    '-- Zet de gedeelde oefeningen en de kant-en-klare schema\'s neer; een tweede keer werkt ze bij.',
    'begin;',
    '',
  ];
  for (const e of catalog.exercises) {
    lines.push(
      'insert into public.exercises (id, owner_id, name, instructions, kind, load_type, equipment, primary_muscles, secondary_muscles, default_step_kg, updated_at)',
      `values (${literal(e.id)}, null, ${json(e.name)}, ${json(e.instructions)}, ${literal(e.kind)}, ${literal(e.loadType)}, ${literal(e.equipment)}, ` +
        `${textArray(e.primaryMuscles)}, ${textArray(e.secondaryMuscles)}, ${e.defaultStepKg}, ${updatedAt})`,
      'on conflict (id) do update set name = excluded.name, instructions = excluded.instructions, kind = excluded.kind, ' +
        'load_type = excluded.load_type, equipment = excluded.equipment, primary_muscles = excluded.primary_muscles, ' +
        'secondary_muscles = excluded.secondary_muscles, default_step_kg = excluded.default_step_kg, updated_at = excluded.updated_at;',
    );
  }
  for (const program of catalog.programs) {
    lines.push(
      '',
      'insert into public.programs (id, owner_id, name, days_per_week, updated_at)',
      `values (${literal(program.id)}, null, ${json(program.name)}, ${program.daysPerWeek}, ${updatedAt})`,
      'on conflict (id) do update set name = excluded.name, days_per_week = excluded.days_per_week, updated_at = excluded.updated_at;',
    );
    for (const day of program.days) {
      lines.push(
        'insert into public.program_days (id, program_id, owner_id, name, position, updated_at)',
        `values (${literal(day.id)}, ${literal(program.id)}, null, ${json(day.name)}, ${day.position}, ${updatedAt})`,
        'on conflict (id) do update set name = excluded.name, position = excluded.position, updated_at = excluded.updated_at;',
      );
      for (const item of day.exercises) {
        lines.push(
          'insert into public.program_exercises (id, program_day_id, owner_id, exercise_id, position, target_sets, rep_min, rep_max, rest_seconds, updated_at)',
          `values (${literal(item.id)}, ${literal(day.id)}, null, ${literal(item.exerciseID)}, ${item.position}, ${item.targetSets}, ` +
            `${item.repMin}, ${item.repMax}, ${item.restSeconds}, ${updatedAt})`,
          'on conflict (id) do update set exercise_id = excluded.exercise_id, position = excluded.position, target_sets = excluded.target_sets, ' +
            'rep_min = excluded.rep_min, rep_max = excluded.rep_max, rest_seconds = excluded.rest_seconds, updated_at = excluded.updated_at;',
        );
      }
    }
  }
  lines.push('', 'commit;', '');
  return lines.join('\n');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const catalog = JSON.parse(readFileSync(join(root, 'Fitling', 'Resources', 'SportCatalog.json'), 'utf8'));
  const problems = validate(catalog);
  for (const problem of problems) console.error(`error: ${problem}`);
  if (problems.length > 0) process.exit(1);
  const target = join(root, 'supabase', 'seed', 'sport.sql');
  const sql = seedSQL(catalog);
  if (process.argv.includes('--check')) {
    let current = '';
    try { current = readFileSync(target, 'utf8').replaceAll('\r\n', '\n'); } catch { /* ontbreekt */ }
    if (current !== sql) {
      console.error('error: supabase/seed/sport.sql is verouderd; draai node scripts/sport-seed.mjs');
      process.exit(1);
    }
    console.log(`sport-seed: up to date (${catalog.exercises.length} exercises, ${catalog.programs.length} programmes)`);
  } else {
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, sql);
    console.log(`sport-seed: wrote ${target}`);
  }
}

#!/usr/bin/env node
// Controleert dat elk SwiftData-model dezelfde kolommen heeft als zijn tabel in supabase/schema.sql:
// zelfde namen, zelfde soort waarde, en optioneel waar de kolom leeg mag zijn.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const TABLES = {
  UserProfile: 'profiles',
  TargetPeriod: 'target_history',
  Product: 'products',
  FoodEntry: 'food_entries',
  WaterEntry: 'water_entries',
  FavoriteProduct: 'favorite_products',
  Creature: 'creatures',
  Exercise: 'exercises',
  Program: 'programs',
  ProgramDay: 'program_days',
  ProgramExercise: 'program_exercises',
  ExerciseSetting: 'exercise_settings',
  WorkoutSession: 'workout_sessions',
  WorkoutSet: 'workout_sets',
  BodyMeasurement: 'body_measurements',
  Recipe: 'recipes',
  RecipeIngredient: 'recipe_ingredients',
  MenuPreferences: 'menu_preferences',
  ExcludedIngredient: 'excluded_ingredients',
  MealPlanEntry: 'meal_plan_entries',
  ShoppingList: 'shopping_lists',
  ShoppingListMember: 'shopping_list_members',
  ShoppingItem: 'shopping_items',
  Supermarket: 'supermarkets',
  Offer: 'offers',
  FavoriteSupermarket: 'favorite_supermarkets',
};
// Bestaan alleen op het toestel.
export const LOCAL_ONLY_MODELS = ['ProgressPhoto', 'DayActivity', 'SyncCursor'];
// Hier komt de app nooit rechtstreeks bij.
export const SERVER_ONLY_TABLES = ['product_submissions', 'shopping_list_invites'];
// synced_at is de pull-cursor per tabel (SyncCursor), niet per rij.
const SERVER_ONLY_COLUMNS = ['synced_at'];
const LOCAL_ONLY_PROPERTIES = ['needsPush', 'key'];

const SWIFT_TYPE = {
  uuid: 'UUID',
  text: 'String',
  integer: 'Int',
  numeric: 'Double',
  boolean: 'Bool',
  timestamptz: 'Date',
  date: 'String',
  jsonb: 'Data',
  'text[]': '[String]',
};

export function parseTables(sql) {
  const tables = {};
  const pattern = /create table public\.(\w+) \(\n([\s\S]*?)\n\);/g;
  for (const [, table, body] of sql.replace(/\r\n/g, '\n').matchAll(pattern)) {
    const columns = {};
    for (const line of body.split('\n')) {
      const match = line.match(/^ {2}([a-z_0-9]+)\s+(uuid|text\[\]|text|integer|numeric|boolean|timestamptz|date|jsonb)(?=[\s(,]|$)(.*)$/);
      if (!match) continue;
      const [, name, type, rest] = match;
      columns[name] = { type, nullable: !/not null|primary key/.test(rest) };
    }
    tables[table] = columns;
  }
  return tables;
}

export function parseModels(swift) {
  const models = {};
  let current = null;
  for (const line of swift.replace(/\r\n/g, '\n').split('\n')) {
    const start = line.match(/^\s*final class (\w+)/);
    if (start) {
      current = {};
      models[start[1]] = current;
      continue;
    }
    // De opgeslagen eigenschappen staan vóór de init; daarna volgt alleen code.
    if (/^\s*init\(/.test(line)) current = null;
    if (!current) continue;
    const property = line.match(/^\s*(?:@Attribute\(\.unique\) )?var (\w+): ([\w[\]]+)(\?)?\s*$/);
    if (property) current[property[1]] = { type: property[2], optional: property[3] === '?' };
  }
  return models;
}

export function columnName(property) {
  return property
    .replace(/JSON$/, '')
    .replace(/ID$/, 'Id')
    .replace(/URL$/, 'Url')
    .replace(/([A-Z])([A-Z][a-z])/g, '$1_$2')
    .replace(/([a-z])([A-Z0-9])/g, '$1_$2')
    .toLowerCase();
}

export function checkModels({ sql, swift }) {
  const errors = [];
  const tables = parseTables(sql);
  const models = parseModels(swift);

  for (const model of Object.keys(models)) {
    if (!TABLES[model] && !LOCAL_ONLY_MODELS.includes(model)) errors.push(`${model}: model zonder tabel`);
  }
  for (const table of Object.keys(tables)) {
    if (!Object.values(TABLES).includes(table) && !SERVER_ONLY_TABLES.includes(table)) {
      errors.push(`${table}: tabel zonder model`);
    }
  }

  for (const [model, table] of Object.entries(TABLES)) {
    const properties = models[model];
    const columns = tables[table];
    if (!properties) { errors.push(`${model}: model ontbreekt`); continue; }
    if (!columns) { errors.push(`${table}: tabel ontbreekt`); continue; }

    const seen = new Set();
    for (const [property, { type, optional }] of Object.entries(properties)) {
      if (LOCAL_ONLY_PROPERTIES.includes(property)) continue;
      const name = columnName(property);
      const column = columns[name];
      if (!column) { errors.push(`${model}.${property}: geen kolom ${table}.${name}`); continue; }
      seen.add(name);
      if (SWIFT_TYPE[column.type] !== type) {
        errors.push(`${model}.${property}: ${type} past niet bij ${table}.${name} (${column.type})`);
      }
      if (column.nullable !== optional) {
        errors.push(`${model}.${property}: ${optional ? 'optioneel' : 'verplicht'}, maar ${table}.${name} is ${column.nullable ? 'leeg toegestaan' : 'not null'}`);
      }
    }
    for (const name of Object.keys(columns)) {
      if (!seen.has(name) && !SERVER_ONLY_COLUMNS.includes(name)) errors.push(`${table}.${name}: geen eigenschap in ${model}`);
    }
  }
  return errors;
}

export function readProject(root) {
  const modelsDir = join(root, 'Fitling', 'Core', 'Models');
  const swift = readdirSync(modelsDir)
    .filter((name) => name.endsWith('.swift'))
    .map((name) => readFileSync(join(modelsDir, name), 'utf8'))
    .join('\n');
  return { sql: readFileSync(join(root, 'supabase', 'schema.sql'), 'utf8'), swift };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const errors = checkModels(readProject(process.cwd()));
  for (const error of errors) console.error(`error: ${error}`);
  console.log(`check-models: ${errors.length} error(s)`);
  process.exit(errors.length > 0 ? 1 : 0);
}

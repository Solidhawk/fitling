import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkModels, columnName, parseModels, parseTables, TABLES } from './check-models.mjs';

const sql = `
create table public.water_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  consumed_on date not null,
  amount_ml   integer not null check (amount_ml between 1 and 5000),
  note        text check (
                char_length(note) < 10
              ),
  updated_at  timestamptz not null,
  synced_at   timestamptz not null default now(),
  deleted_at  timestamptz,
  check (amount_ml > 0)
);
`;

const swift = `
    @Model
    final class WaterEntry {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var consumedOn: String
        var amountMl: Int
        var note: String?
        var updatedAt: Date
        var deletedAt: Date?
        var needsPush: Bool

        init(id: UUID) {
            self.id = id
        }
    }

extension WaterEntry {
    var litres: Double { Double(amountMl) / 1000 }
}
`;

function only(model) {
  for (const key of Object.keys(TABLES)) if (key !== model) delete TABLES[key];
}

test('column names follow the Swift names', () => {
  assert.equal(columnName('userID'), 'user_id');
  assert.equal(columnName('imageURL'), 'image_url');
  assert.equal(columnName('nameJSON'), 'name');
  assert.equal(columnName('kcal100'), 'kcal_100');
  assert.equal(columnName('saturatedFat100'), 'saturated_fat_100');
  assert.equal(columnName('proteinGPerServing'), 'protein_g_per_serving');
  assert.equal(columnName('isWarmup'), 'is_warmup');
  assert.equal(columnName('xp'), 'xp');
});

test('reads columns and skips constraints and continuation lines', () => {
  const columns = parseTables(sql).water_entries;
  assert.deepEqual(Object.keys(columns), ['id', 'user_id', 'consumed_on', 'amount_ml', 'note', 'updated_at', 'synced_at', 'deleted_at']);
  assert.equal(columns.id.nullable, false);
  assert.equal(columns.note.nullable, true);
  assert.equal(columns.deleted_at.nullable, true);
});

test('reads stored properties and skips computed ones', () => {
  const properties = parseModels(swift).WaterEntry;
  assert.deepEqual(Object.keys(properties), ['id', 'userID', 'consumedOn', 'amountMl', 'note', 'updatedAt', 'deletedAt', 'needsPush']);
  assert.equal(properties.note.optional, true);
});

test('a model that matches its table passes', () => {
  only('WaterEntry');
  assert.deepEqual(checkModels({ sql, swift }), []);
});

test('a missing property, a wrong type and wrong optionality are reported', () => {
  only('WaterEntry');
  const broken = swift
    .replace('        var consumedOn: String\n', '')
    .replace('var amountMl: Int', 'var amountMl: Double')
    .replace('var note: String?', 'var note: String');
  assert.deepEqual(checkModels({ sql, swift: broken }), [
    'WaterEntry.amountMl: Double past niet bij water_entries.amount_ml (integer)',
    'WaterEntry.note: verplicht, maar water_entries.note is leeg toegestaan',
    'water_entries.consumed_on: geen eigenschap in WaterEntry',
  ]);
});

test('a property without a column is reported', () => {
  only('WaterEntry');
  const extra = swift.replace('var needsPush: Bool', 'var needsPush: Bool\n        var colour: String');
  assert.deepEqual(checkModels({ sql, swift: extra }), ['WaterEntry.colour: geen kolom water_entries.colour']);
});

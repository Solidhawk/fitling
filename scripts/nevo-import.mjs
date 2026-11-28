#!/usr/bin/env node
// Maakt uit de tabel van NEVO-online (NEVO2025_v9.0.csv uit de download van het RIVM) de SQL die de onverpakte
// producten als gedeelde rijen in public.products zet (UNFORGET S15, docs/nevo.md).
// Gebruik: node scripts/nevo-import.mjs <NEVO2025_v9.0.csv> [uit.sql]   (standaard supabase/seed/nevo.sql)
// De tabel en de SQL komen niet in git: NEVO mag alleen onveranderd en met bronvermelding gebruikt worden, en de
// repository is openbaar. Waarden gaan onveranderd mee; alleen zout wordt uit natrium berekend.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** De versie waar de bronvermelding (account.about.nevo) bij hoort; een nieuwe versie vraagt een nieuwe tekst. */
export const VERSION = 'NEVO-Online 2025 9.0';
/** De bronvermelding die de voorwaarden van NEVO voorschrijven. */
export const REFERENCE = 'NEVO-online versie 2025/9.0, RIVM, Bilthoven';

// Vaste naamruimte voor de id's: dezelfde NEVO-code krijgt altijd dezelfde id, ook in een volgende versie, zodat
// favorieten en gelogde producten blijven kloppen.
const NAMESPACE = Buffer.from('8f3c2a61d94b4e0f9a7d5c1b3e2f6a90', 'hex');
const UNITS = { 'per 100g': 'g', 'per 100ml': 'ml' };

/** De rijen van de tabel, elk als object op kolomnaam. De kolommen staan tussen "|", waarden soms tussen aanhalingstekens. */
export function parseNevo(text) {
  const [head, ...lines] = text.replace(/^﻿/, '').split(/\r?\n/).filter((line) => line.trim() !== '');
  const unquote = (cell) => cell.replace(/^"(.*)"$/s, '$1');
  const columns = head.split('|').map(unquote);
  return lines.map((line, index) => {
    const cells = line.split('|').map(unquote);
    if (cells.length !== columns.length) {
      throw new Error(`regel ${index + 2}: ${cells.length} kolommen in plaats van ${columns.length}`);
    }
    return Object.fromEntries(columns.map((column, at) => [column, cells[at]]));
  });
}

/** Een UUID versie 5 uit de NEVO-code. */
export function nevoID(code) {
  const hash = createHash('sha1').update(NAMESPACE).update(`nevo:${code}`).digest();
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = hash.subarray(0, 16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** Een getal met decimale komma; leeg is onbekend. */
function number(value) {
  if (value === undefined || value.trim() === '') return null;
  const parsed = Number(value.replace(',', '.'));
  if (!Number.isFinite(parsed)) throw new Error(`geen getal: ${value}`);
  return parsed;
}

/** Kleine letters zonder accenten, zoals FoodLog.searchKey; zo vindt zoeken de namen. */
function fold(text) {
  return text.normalize('NFD').replace(/\p{Mn}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim();
}

/** Een product uit NEVO als rij voor public.products. */
export function productRow(food) {
  const version = food['NEVO-versie/NEVO-version'];
  if (version !== VERSION) {
    throw new Error(`${version}: dit script hoort bij ${VERSION}. Pas VERSION, REFERENCE en account.about.nevo aan.`);
  }
  const code = food['NEVO-code'];
  const nl = food['Voedingsmiddelnaam/Dutch food name'];
  const en = food['Engelse naam/Food name'];
  const unit = UNITS[food['Hoeveelheid/Quantity']];
  if (!code || !nl || !en || !unit) throw new Error(`NEVO-code ${code}: naam, Engelse naam of hoeveelheid ontbreekt`);
  const sodium = number(food['NA (mg)']);
  return {
    id: nevoID(code),
    source: 'nevo',
    source_id: code,
    name: { nl, en },
    search_name: fold([nl, en, food['Synoniem']].filter(Boolean).join(' ')),
    quantity_unit: unit,
    kcal_100: number(food['ENERCC (kcal)']),
    protein_100: number(food['PROT (g)']),
    carbs_100: number(food['CHO (g)']),
    sugars_100: number(food['SUGAR (g)']),
    fat_100: number(food['FAT (g)']),
    saturated_fat_100: number(food['FASAT (g)']),
    fiber_100: number(food['FIBT (g)']),
    // Zout = natrium × 2,5 (EU-verordening 1169/2011). In g op de twee decimalen van de kolom: mg × 2,5 / 1000.
    salt_100: sodium === null ? null : Math.round(sodium * 0.25) / 100,
    is_verified: true,
  };
}

const literal = (text) => `'${String(text).replaceAll("'", "''")}'`;
const value = (field) => (field === null ? 'null' : typeof field === 'number' ? String(field) : literal(field));

const COLUMNS = [
  'id', 'source', 'source_id', 'name', 'search_name', 'quantity_unit', 'kcal_100', 'protein_100', 'carbs_100',
  'sugars_100', 'fat_100', 'saturated_fat_100', 'fiber_100', 'salt_100', 'is_verified',
];

/** Eén transactie: elk product erin of bijgewerkt, en wat niet meer in NEVO staat, weggehaald. */
export function toSql(products) {
  // Een lege tabel zou alle NEVO-producten weghalen.
  if (products.length === 0) throw new Error('geen producten');
  const rows = products.map((product) => {
    const fields = COLUMNS.map((column) =>
      column === 'name' ? `${literal(JSON.stringify(product.name))}::jsonb` : column === 'is_verified' ? 'true' : value(product[column]),
    );
    return `  (${fields.join(', ')}, now(), now())`;
  });
  const updates = COLUMNS.filter((column) => !['id', 'source', 'source_id'].includes(column))
    .map((column) => `${column} = excluded.${column}`)
    .concat(['fetched_at = excluded.fetched_at', 'updated_at = excluded.updated_at', 'deleted_at = null']);
  const codes = products.map((product) => literal(product.source_id)).join(', ');
  return [
    `-- Gemaakt door scripts/nevo-import.mjs uit ${REFERENCE}. Niet in git (voorwaarden van NEVO).`,
    'begin;',
    `insert into public.products (${COLUMNS.join(', ')}, fetched_at, updated_at) values`,
    `${rows.join(',\n')}`,
    `on conflict (id) do update set ${updates.join(', ')};`,
    "update public.products set deleted_at = now(), updated_at = now()",
    `  where source = 'nevo' and owner_id is null and deleted_at is null and source_id <> all (array[${codes}]);`,
    'commit;',
    '',
  ].join('\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const [input, output = join(root, 'supabase/seed/nevo.sql')] = process.argv.slice(2);
  if (!input) {
    console.error('Gebruik: node scripts/nevo-import.mjs <NEVO2025_v9.0.csv> [uit.sql]');
    process.exit(2);
  }
  const products = parseNevo(readFileSync(input, 'utf8')).map(productRow);
  writeFileSync(output, toSql(products));
  console.log(`${products.length} producten uit ${REFERENCE} -> ${output}`);
}

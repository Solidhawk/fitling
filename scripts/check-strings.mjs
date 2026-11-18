#!/usr/bin/env node
// Controleert dat elke UI-tekst in Fitling via Localizable.xcstrings loopt en in nl, en en de vertaald is.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const LANGUAGES = ['nl', 'en', 'de'];
const PREFIXES = ['common', 'welcome', 'auth', 'consent', 'onboarding', 'profile', 'targets', 'account', 'error'];
const KEY_PATTERN = new RegExp(`^(?:${PREFIXES.join('|')})\\.[A-Za-z0-9.]+(?: .*)?$`, 's');
const UI_CALLS = [
  'Text(', 'Button(', 'Label(', 'Toggle(', 'TextField(', 'SecureField(', 'Picker(', 'Section(',
  '.navigationTitle(', '.accessibilityLabel(', '.accessibilityHint(', '.alert(', '.confirmationDialog(',
  'String(localized:', 'LocalizedStringKey(', 'LocalizedStringResource(',
];
const FORMAT_SPECIFIER = '%(?:\\d+\\$)?(?:@|lld|ld|d|lu|u|lf|f|\\.\\d+f)';

function swiftFiles(dir) {
  const files = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) files.push(...swiftFiles(full));
    else if (name.endsWith('.swift')) files.push(full);
  }
  return files;
}

// Leest string literals uit Swift-broncode en slaat commentaar en multiline strings over.
// Een literal met interpolatie wordt teruggegeven met `\(` … `)` intact.
function stringLiterals(source) {
  const literals = [];
  let i = 0;
  let line = 1;

  function readString() {
    const startLine = line;
    let value = '';
    i += 1;
    while (i < source.length) {
      const ch = source[i];
      if (ch === '\n') return null;
      if (ch === '\\' && source[i + 1] === '(') {
        let depth = 1;
        value += '\\(';
        i += 2;
        while (i < source.length && depth > 0) {
          const c = source[i];
          if (c === '"') {
            const nested = readString();
            if (nested === null) return null;
            value += `"${nested.value}"`;
            continue;
          }
          if (c === '(') depth += 1;
          if (c === ')') depth -= 1;
          value += c;
          i += 1;
        }
        continue;
      }
      if (ch === '\\') {
        value += source.slice(i, i + 2);
        i += 2;
        continue;
      }
      if (ch === '"') {
        i += 1;
        return { value, line: startLine };
      }
      value += ch;
      i += 1;
    }
    return null;
  }

  while (i < source.length) {
    const ch = source[i];
    if (ch === '\n') { line += 1; i += 1; continue; }
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] !== '\n') i += 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      const end = source.indexOf('*/', i + 2);
      const stop = end === -1 ? source.length : end + 2;
      line += (source.slice(i, stop).match(/\n/g) ?? []).length;
      i = stop;
      continue;
    }
    if (source.startsWith('"""', i)) {
      const end = source.indexOf('"""', i + 3);
      const stop = end === -1 ? source.length : end + 3;
      line += (source.slice(i, stop).match(/\n/g) ?? []).length;
      i = stop;
      continue;
    }
    if (ch === '"') {
      const start = i;
      const literal = readString();
      if (literal === null) { i = start + 1; continue; }
      const lineStart = source.lastIndexOf('\n', start) + 1;
      literals.push({ ...literal, before: source.slice(lineStart, start).trimEnd() });
      continue;
    }
    i += 1;
  }
  return literals;
}

function catalogMatcher(literal) {
  if (!literal.includes('\\(')) return (key) => key === literal;
  const parts = [];
  let rest = literal;
  while (rest.length > 0) {
    const start = rest.indexOf('\\(');
    if (start === -1) { parts.push(escapeRegex(rest)); break; }
    parts.push(escapeRegex(rest.slice(0, start)));
    let depth = 1;
    let j = start + 2;
    while (j < rest.length && depth > 0) {
      if (rest[j] === '(') depth += 1;
      if (rest[j] === ')') depth -= 1;
      j += 1;
    }
    parts.push(FORMAT_SPECIFIER);
    rest = rest.slice(j);
  }
  const pattern = new RegExp(`^${parts.join('')}$`);
  return (key) => pattern.test(key);
}

function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function missingLanguages(entry) {
  return LANGUAGES.filter((language) => !isTranslated(entry?.localizations?.[language]));
}

function isTranslated(localization) {
  if (!localization) return false;
  if (localization.stringUnit) {
    return localization.stringUnit.state === 'translated' && localization.stringUnit.value !== '';
  }
  if (localization.variations) {
    const leaves = Object.values(localization.variations).flatMap((group) => Object.values(group));
    return leaves.length > 0 && leaves.every(isTranslated);
  }
  return false;
}

export function checkStrings({ root }) {
  const errors = [];
  const warnings = [];
  const appDir = join(root, 'Fitling');
  const catalogPath = join(appDir, 'Resources', 'Localizable.xcstrings');

  let catalog;
  try {
    catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
  } catch (error) {
    return { errors: [`catalog unreadable: ${relative(root, catalogPath)} (${error.message})`], warnings };
  }
  if (catalog.sourceLanguage !== 'nl') {
    errors.push(`sourceLanguage must be "nl", found "${catalog.sourceLanguage}"`);
  }

  const catalogKeys = Object.keys(catalog.strings ?? {});
  const usedKeys = new Set();
  const uiTestingDir = join(appDir, 'UITesting') + sep;

  for (const file of swiftFiles(appDir)) {
    if (file.startsWith(uiTestingDir)) continue;
    const location = relative(root, file).split(sep).join('/');
    for (const literal of stringLiterals(readFileSync(file, 'utf8'))) {
      if (KEY_PATTERN.test(literal.value)) {
        const matches = catalogKeys.filter(catalogMatcher(literal.value));
        if (matches.length === 0) {
          errors.push(`unknown key: "${literal.value}" (${location}:${literal.line})`);
          continue;
        }
        for (const key of matches) {
          usedKeys.add(key);
          const missing = missingLanguages(catalog.strings[key]);
          if (missing.length > 0) {
            errors.push(`missing translation: "${key}" [${missing.join(', ')}] (${location}:${literal.line})`);
          }
        }
      } else if (UI_CALLS.some((call) => literal.before.endsWith(call))) {
        errors.push(`hardcoded text: "${literal.value}" (${location}:${literal.line})`);
      }
    }
  }

  for (const key of catalogKeys) {
    if (!usedKeys.has(key)) warnings.push(`unused key: "${key}"`);
  }
  return { errors: [...new Set(errors)], warnings };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const { errors, warnings } = checkStrings({ root: process.cwd() });
  for (const warning of warnings) console.warn(`warning: ${warning}`);
  for (const error of errors) console.error(`error: ${error}`);
  console.log(`check-strings: ${errors.length} error(s), ${warnings.length} warning(s)`);
  process.exit(errors.length > 0 ? 1 : 0);
}

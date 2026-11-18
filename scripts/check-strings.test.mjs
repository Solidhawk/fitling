import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { checkStrings } from './check-strings.mjs';

function translated(value) {
  return { stringUnit: { state: 'translated', value } };
}

function entry(nl, en, de) {
  const localizations = {};
  if (nl !== undefined) localizations.nl = translated(nl);
  if (en !== undefined) localizations.en = translated(en);
  if (de !== undefined) localizations.de = translated(de);
  return { localizations };
}

function makeProject({ swift, strings, sourceLanguage = 'nl' }) {
  const root = mkdtempSync(join(tmpdir(), 'check-strings-'));
  for (const [path, content] of Object.entries(swift)) {
    const full = join(root, 'Fitling', path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, content);
  }
  const catalog = join(root, 'Fitling', 'Resources', 'Localizable.xcstrings');
  mkdirSync(dirname(catalog), { recursive: true });
  writeFileSync(catalog, JSON.stringify({ sourceLanguage, strings, version: '1.0' }));
  return root;
}

test('reports a key that misses a language', () => {
  const root = makeProject({
    swift: { 'Features/Auth/SignInView.swift': 'Text("auth.signIn.title")' },
    strings: { 'auth.signIn.title': entry('Inloggen', 'Sign in', undefined) },
  });
  const { errors } = checkStrings({ root });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /auth\.signIn\.title/);
  assert.match(errors[0], /\bde\b/);
});

test('reports a translation that is not in state translated', () => {
  const strings = { 'auth.signIn.title': entry('Inloggen', 'Sign in', 'Anmelden') };
  strings['auth.signIn.title'].localizations.de.stringUnit.state = 'new';
  const root = makeProject({
    swift: { 'Features/Auth/SignInView.swift': 'Text("auth.signIn.title")' },
    strings,
  });
  const { errors } = checkStrings({ root });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /\bde\b/);
});

test('reports a hardcoded sentence in Text', () => {
  const root = makeProject({
    swift: { 'Features/Auth/SignInView.swift': 'Text("Hallo wereld")' },
    strings: {},
  });
  const { errors } = checkStrings({ root });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /hardcoded/);
  assert.match(errors[0], /SignInView\.swift:1/);
});

test('reports a key that is not in the catalog', () => {
  const root = makeProject({
    swift: { 'Features/Auth/SignInView.swift': 'Text("auth.signIn.missing")' },
    strings: {},
  });
  const { errors } = checkStrings({ root });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /auth\.signIn\.missing/);
});

test('accepts a key with all three languages', () => {
  const root = makeProject({
    swift: { 'Features/Auth/SignInView.swift': 'Button("auth.signIn.title") { }' },
    strings: { 'auth.signIn.title': entry('Inloggen', 'Sign in', 'Anmelden') },
  });
  const { errors, warnings } = checkStrings({ root });
  assert.deepEqual(errors, []);
  assert.deepEqual(warnings, []);
});

test('matches an interpolated literal against a format key', () => {
  const root = makeProject({
    swift: { 'Features/Profile/ProfileView.swift': 'Text("targets.kcal \\(calculation.targets.kcal)")' },
    strings: { 'targets.kcal %lld': entry('%lld kcal', '%lld kcal', '%lld kcal') },
  });
  const { errors, warnings } = checkStrings({ root });
  assert.deepEqual(errors, []);
  assert.deepEqual(warnings, []);
});

test('warns about an unused key without failing', () => {
  const root = makeProject({
    swift: { 'Features/Auth/SignInView.swift': 'Text("auth.signIn.title")' },
    strings: {
      'auth.signIn.title': entry('Inloggen', 'Sign in', 'Anmelden'),
      'auth.signIn.unused': entry('Ongebruikt', 'Unused', 'Unbenutzt'),
    },
  });
  const { errors, warnings } = checkStrings({ root });
  assert.deepEqual(errors, []);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /auth\.signIn\.unused/);
});

test('skips the UITesting folder', () => {
  const root = makeProject({
    swift: { 'UITesting/FakeAuthProvider.swift': 'Text("Alleen voor tests")' },
    strings: {},
  });
  const { errors } = checkStrings({ root });
  assert.deepEqual(errors, []);
});

test('ignores literals in comments', () => {
  const root = makeProject({
    swift: { 'App/RootView.swift': '// Text("Hallo wereld")\n/* Button("Nog een") */\nlet x = 1' },
    strings: {},
  });
  const { errors } = checkStrings({ root });
  assert.deepEqual(errors, []);
});

test('ignores non-UI literals such as date formats and URLs', () => {
  const root = makeProject({
    swift: { 'Data/BirthDateCalendar.swift': 'let f = "yyyy-MM-dd"\nlet u = URL(string: "fitling://auth-callback")' },
    strings: {},
  });
  const { errors } = checkStrings({ root });
  assert.deepEqual(errors, []);
});

test('requires nl as source language', () => {
  const root = makeProject({
    swift: { 'App/RootView.swift': 'let x = 1' },
    strings: {},
    sourceLanguage: 'en',
  });
  const { errors } = checkStrings({ root });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /sourceLanguage/);
});

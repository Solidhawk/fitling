# Fitling – projectregels
- iOS 17+, Swift 6, SwiftUI, SwiftData, Supabase
- Volledige productspecificatie: zie PROMPT.md
- Architectuur en datamodel (goedgekeurd): docs/superpowers/specs/2026-11-18-fitling-architectuur-design.md
- Geen hardcoded strings: altijd Localizable.xcstrings
- Geen API-keys in de app (de publishable key van Supabase is openbaar bedoeld; geheime sleutels alleen in Edge Functions)
- Elke nieuwe feature: unit tests in FitlingTests (app) of FitlingCoreTests (rekenregels)
- Bouwen en testen gebeurt in GitHub Actions (geen Mac): `xcodebuild test -scheme Fitling -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`. Klaar = alle CI-jobs groen op main.
- Testgereedschap voor de UI-test mag in `Fitling/UITesting/`, alleen in DEBUG-builds.
- Werk per fase; vraag akkoord vóór grote refactors
- GEEN AI slop: geen placeholders/TODO's, geen verzonnen API's, geen overbodige abstracties, geen generieke AI-look (gradients, emoji-iconen), geen AI-gegenereerde voedselfoto's, geen wollige teksten. Alleen 'klaar' melden als het bouwt en de tests slagen.

## Skills
De project-skills in `.claude/skills/` worden bij al het werk aan de app gebruikt, ook als de gebruiker ze niet noemt:
- `unforget`: uitgesteld werk, restpunten en bevindingen die nu niet worden opgelost, en vragen als "wat ligt er nog?"
- `bug-echo`: direct na elke bugfix, om andere plekken met hetzelfde defect te vinden
- `prompter`: bij een korte of onduidelijke opdracht; toon de herschreven versie en wacht op akkoord
- `skill-reviewer`: als een skill in dit project wordt toegevoegd of gewijzigd

Gebruik daarnaast de andere geïnstalleerde skills waar ze passen (bijv. `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `impeccable` voor schermen). De Python-helpers van `unforget` noemen `python3`; op deze machine heet dat `python`, en zet `PYTHONIOENCODING=utf-8` (anders crasht de uitvoer op Windows).

<!-- unforget:begin — maintained by the unforget skill; do not hand-edit inside these markers -->
## Deferred Work Index

**Ledger home:** `docs/`  (git posture: split — contents ignored, README/index tracked)

- `UNFORGET.md` — UNFORGET.md (main · standard-10col).

Read the ledgers when the user asks "what's deferred?" / "backlog?" / "prioritize," and before suggesting a release (check 🔴 THIS rows). Log new deferrals via the deferral gate — an item lives in exactly ONE ledger; siblings get a pointer row, not a copy.

Surface, don't start: report rows freely, but start work on one only when the user names it, it blocks the current release, or it sits directly in the path of the task in progress; mention every other row in one line.
<!-- unforget:end -->

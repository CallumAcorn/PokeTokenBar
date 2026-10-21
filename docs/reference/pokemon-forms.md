---
summary: "Collectible alternate forms (Unown letters, Rotom, Arceus...): catalogue, draw, Pokédex, save keys, sprite names and form names in the fork."
read_when:
  - adding or removing a species' forms, or touching form sprites and their cache keys
  - changing how an individual's form is drawn, saved, imported, traded or displayed
---

# Pokémon forms

Ported from upstream 10d1a07c (#288, Unown), 04b12da9 (#376, all gen 1 to 5 forms),
4bfae978 (#345, appearances chosen separately) and the form parts of dc6de418, as one
fork-native implementation rather than a replay of the Unown-only intermediate.

## Catalogue

`PokemonForm.catalog`, default form first. A form is listed only when PokeAPI has an
animated Black/White GIF for it, the same source that bounds hatchable species:
Unown (A to Z, ! and ?), Castform, Deoxys, Burmy and Wormadam, Cherrim, Shellos and
Gastrodon, Rotom, Giratina, Shaymin, Arceus (18 types), Basculin, Darmanitan, Deerling
and Sawsbuck, the three forces of nature, Kyurem, Keldeo, Meloetta and Genesect.
Gender differences and Mothim's cloaks are not forms.

## Draw

The form belongs to the individual (`MonState.form`) and is drawn once for the whole
line, at the egg pre-roll (`pendingForm`, so prefetch warms the exact sprite) or at hatch
when there was no pre-roll. Each stage resolves it (`PokemonForm.resolved`): a Sandy
Burmy becomes a Sandy Wormadam, and Mothim shows its single look.

- The draw is the **last** RNG draw of the hatch and happens **only for lines with forms**,
  so seeded sequences for every other roll and every other species are unchanged.
- Weights: uncollected forms 2, collected forms 1 (`CollectionWeight`). A form counts as
  collected for a line once every species of the line that shows it has it.
- `resolved` maps nil to the default form. Never pass a nil pre-roll through it: a save
  without a stored form keeps nil so the hatch rolls (see the defect log, 2026-10-21).
- A revealed Ditto drops the disguise's form.

## Fork differences from upstream

- **Collection** is derived from the catch log (`dex`, with `DexEntry.form`) plus party
  members that reached the species. `dexUnlocked` stays species-level.
- **Pokédex**: one cell per species with a `n/total` badge and the pinned or first
  collected look. The detail page has a picker of collected appearances only; the choice
  drives the sprites, the shiny slot (shine is per appearance), the evolution line and the
  menu-bar pin. A "Data uses the default form" note shows for non-default looks.
- **Pin**: `setRepresentative(_:form:)` accepts only a collected appearance; without one
  named it takes the first collected. `reconcileRepresentativeSelection` re-checks on load.
- **Names**: `FormNameStore` fetches `pokemon-form/{id}` form names on demand; the
  identifier ("Blue Striped") shows until then. Unown shows its letter. Castform, Rotom,
  Kyurem and Genesect name their usual look "Normal Form". Upstream's general name
  localisation layer (`2fab082c`) is not ported.
- **Recap and backups** show the form sprite; recap chips name only Unown's letter.

## Save keys and trust boundary

`form`, `pendingForm`, `representativeForm`; upstream's `unownForm`, `pendingUnownForm`
and `representativeUnownForm` are still read. Decoding and `SaveTransfer.sanitized` both
resolve each stored form against its line, so a form from another line falls back to the
default and lines without forms store none. `restoredPartyFromCatchLog` carries the row's form.

## Sprites

Animated GIFs and cache files use `<id>-<form>` (`492-sky.gif`); static PNGs of separate
varieties use the variety id (`10006.png`). The default form keeps the plain `<id>` names,
so caches written before forms existed stay valid. A missing form sprite falls back to the
default look. `SpriteView`, the menu-bar key and the floating pet all include the form.
`PTB_PARITY=1 swift test --filter PokemonFormTests` checks every catalogued sprite exists.

// Generates Sources/PokeTokenBar/Resources/competitive-gen5.json — the dex's competitive tier and
// suggested build for every species #1–649.
//
// Why bundled when the rest of the Pokémon data is fetched from PokéAPI at runtime: PokéAPI has no
// competitive data at all, and fetching it live would add two new third-party hosts for the app to
// contact. The output is a static snapshot; rerun this script to refresh it.
//
//   cd scripts/competitive-data && npm ci && node generate.mjs
//
// Sources:
//   - Tiers, learnsets, move/ability ids: Pokémon Showdown's Gen 5 data via @pkmn/dex (MIT).
//   - Suggested sets: Smogon's Black/White analyses as published by data.pkmn.cc.
//   - Names, capture rates, evolution roots: PokéAPI's CSV dump.
//
// App rules applied (battles run on the Gen 5 sim with BW level-up/TM learnsets and no held items):
//   - Every suggested move must be learnable in-app (Gen 5 level-up, TM, egg or tutor move).
//     Event-only and Dream World moves are dropped and the slot refilled.
//   - Sets built around an item (Choice, Eviolite, ...) are avoided where another set exists.
//   - A species whose Smogon set lost a move, or still depends on a key item, is lowered one tier
//     per reason (max two), and the reason is recorded so the app can explain it.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {Dex} from '@pkmn/dex';
import {Generations} from '@pkmn/data';

const OUT = fileURLToPath(new URL('../../Sources/PokeTokenBar/Resources/competitive-gen5.json', import.meta.url));
const CSV = 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv';
const SETS_URL = 'https://data.pkmn.cc/sets/gen5.json';
const MAX_ID = 649;

const gen = new Generations(Dex).get(5);
const dex = Dex.forGen(5);
const TIERS = ['S', 'A', 'B', 'C', 'D', 'E', 'F'];
const TIER = {Uber: 'S', OU: 'A', UUBL: 'A', '(OU)': 'B', UU: 'B', RUBL: 'B', RU: 'C', NUBL: 'C',
  NU: 'D', PUBL: 'D', PU: 'E', NFE: 'F', LC: 'F'};
// Formats to try for a species' set: its own tier's format first, then the rest.
const OWN_FORMATS = {S: ['ubers'], A: ['ou'], B: ['uu', 'ou'], C: ['ru', 'uu'], D: ['nu', 'ru'], E: ['pu', 'nu'], F: ['lc', 'nfe']};
const FORMAT_ORDER = ['ou', 'ubers', 'uu', 'ru', 'nu', 'pu', 'lc', 'nfe', 'doublesou', 'monotype', '1v1'];
// Items a set is built around — without them the set doesn't work as rated.
const KEY_ITEMS = /^(Choice Band|Choice Specs|Choice Scarf|Eviolite|Light Ball|Thick Club|White Herb)$/;
const SETUP = new Set(['swordsdance', 'dragondance', 'nastyplot', 'calmmind', 'quiverdance', 'shellsmash', 'bulkup',
  'agility', 'rockpolish', 'coil', 'shiftgear', 'curse', 'bellydrum', 'tailglow', 'growth', 'honeclaws', 'workup']);
const UTILITY = ['stealthrock', 'spikes', 'toxic', 'willowisp', 'thunderwave', 'recover', 'roost', 'softboiled',
  'slackoff', 'synthesis', 'moonlight', 'rest', 'wish', 'protect', 'substitute', 'leechseed', 'uturn',
  'voltswitch', 'rapidspin', 'haze'];
// Left out of the automatic picker only: they need judgement (recoil, lock-in, charge turns, stat drops).
const AUTO_SKIP = new Set(['explosion', 'selfdestruct', 'hyperbeam', 'gigaimpact', 'solarbeam', 'skyattack',
  'focuspunch', 'lastresort', 'dreameater', 'futuresight', 'doomdesire', 'razorwind', 'skullbash',
  'synchronoise', 'snore', 'frustration', 'return', 'naturalgift', 'fling', 'blastburn', 'frenzyplant',
  'hydrocannon', 'roaroftime', 'rockwrecker', 'headsmash', 'dig', 'dive', 'fly', 'bounce', 'shadowforce',
  'overheat', 'dracometeor', 'leafstorm', 'psychoboost', 'thrash', 'outrage', 'petaldance', 'superpower',
  'closecombat', 'hammerarm', 'vcreate', 'boltstrike', 'blueflare']);
const ITEM_MOVES = new Set(['trick', 'switcheroo']);

const EV_KEYS = {hp: 'hp', atk: 'attack', def: 'defense', spa: 'specialAttack', spd: 'specialDefense', spe: 'speed'};
const toID = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');
const list = v => (Array.isArray(v) ? v : v == null ? [] : [v]);

async function csv(name) {
  const res = await fetch(`${CSV}/${name}.csv`);
  if (!res.ok) throw new Error(`${name}.csv: HTTP ${res.status}`);
  const [header, ...rows] = (await res.text()).trim().split('\n');
  const keys = header.split(',');
  // ponytail: split on commas is safe for these three files (no quoted fields in the columns we read).
  return rows.map(r => Object.fromEntries(r.split(',').map((v, i) => [keys[i], v])));
}

// Moves this species can learn in the app — exactly what the dex's move lists and the learn-a-move
// flow offer (CompanionStore.learnableMoves(speciesID:pathIDs:)): its own BW TMs, plus the Gen 5
// level-up, egg and tutor moves of every stage of its line up to it. Egg and tutor moves are free in
// the app (LearnMethod.isFree); earlier stages count because Showdown lists egg moves on the stage that
// breeds them, and a move learned before evolving is kept. `learnsets.all` walks the prevos.
async function learnable(species) {
  const ok = new Set();
  const own = await gen.learnsets.get(species.id);
  for (const [move, sources] of Object.entries(own?.learnset ?? {}))
    if (sources.some(s => s.startsWith('5M'))) ok.add(move);
  for await (const ls of gen.learnsets.all(species))
    for (const [move, sources] of Object.entries(ls.learnset ?? {}))
      if (sources.some(s => /^5[LET]/.test(s))) ok.add(move);
  return ok;
}

// Walls with weak attacks (Chansey, Shuckle, ...) get a support build: recovery and status first,
// one attack, bulk-boosting nature.
const RECOVERY = ['softboiled', 'recover', 'roost', 'slackoff', 'milkdrink', 'moonlight', 'morningsun', 'synthesis', 'wish', 'rest'];
const STATUS = ['toxic', 'thunderwave', 'willowisp', 'stealthrock', 'spikes', 'toxicspikes', 'leechseed', 'protect', 'healbell', 'aromatherapy', 'lightscreen', 'reflect'];

function supportBuild(species, ok) {
  const b = species.baseStats, physical = b.atk >= b.spa;
  const moves = [RECOVERY.find(m => ok.has(m)), ...STATUS.filter(m => ok.has(m))].filter(Boolean).slice(0, 3);
  const attack = [...ok].map(m => dex.moves.get(m))
    .filter(m => m.exists && m.category !== 'Status' && (m.basePower >= 40 || m.damage) && !AUTO_SKIP.has(m.id))
    .map(m => ({m, score: (m.category === (physical ? 'Physical' : 'Special') ? 2 : 0) + (species.types.includes(m.type) ? 1 : 0)}))
    .sort((x, y) => y.score - x.score || (y.m.damage ? 100 : y.m.basePower) - (x.m.damage ? 100 : x.m.basePower))[0]?.m;
  if (attack) moves.push(attack.id);
  for (const m of [...ok].sort()) { if (moves.length >= 4) break; if (!moves.includes(m)) moves.push(m); }
  const physBulk = b.def >= b.spd;
  return {
    ability: species.abilities[0],
    nature: physBulk ? (physical ? 'Impish' : 'Bold') : (physical ? 'Careful' : 'Calm'),
    evs: {hp: 252, [physBulk ? 'def' : 'spd']: 252, [physBulk ? 'spd' : 'def']: 4},
    moves: moves.slice(0, 4),
  };
}

function autoBuild(species, ok) {
  const b = species.baseStats, physical = b.atk >= b.spa, fast = b.spe >= 80;
  if (Math.max(b.atk, b.spa) < 80 && b.hp + b.def + b.spd >= 250) return supportBuild(species, ok);
  const category = physical ? 'Physical' : 'Special';
  const attacks = [...ok].map(m => dex.moves.get(m))
    .filter(m => m.exists && m.category === category && m.basePower >= 50 && !AUTO_SKIP.has(m.id))
    .map(m => ({m, score: m.basePower * (m.accuracy === true ? 100 : m.accuracy) / 100 * (species.types.includes(m.type) ? 1.5 : 1)}))
    .sort((x, y) => y.score - x.score);
  const moves = [], types = new Set();
  for (const {m} of attacks) {
    if (moves.length >= 3) break;
    if (!types.has(m.type)) { moves.push(m.id); types.add(m.type); }
  }
  const wrongSide = physical ? ['nastyplot', 'calmmind', 'quiverdance', 'tailglow'] : ['swordsdance', 'dragondance', 'bulkup', 'curse', 'coil', 'honeclaws'];
  const extra = [...SETUP].find(x => ok.has(x) && !wrongSide.includes(x)) ?? UTILITY.find(x => ok.has(x));
  if (extra) moves.push(extra);
  for (const {m} of attacks) { if (moves.length >= 4) break; if (!moves.includes(m.id)) moves.push(m.id); }
  for (const m of [...ok].sort()) { if (moves.length >= 4) break; if (!moves.includes(m)) moves.push(m); }
  const bulky = b.hp + b.def + b.spd >= 240 && !fast;
  return {
    ability: species.abilities[0],
    nature: physical ? (fast ? 'Jolly' : 'Adamant') : (fast ? 'Timid' : 'Modest'),
    evs: bulky ? {hp: 252, [physical ? 'atk' : 'spa']: 252, def: 4} : {[physical ? 'atk' : 'spa']: 252, spe: 252, hp: 4},
    moves,
  };
}

// A Smogon set's moves as the app can field them: per slot, the first option this species can learn.
// `lost` = options of slots where none could be learned.
function fit(set, ok) {
  const moves = [], lost = [];
  for (const slot of set.moves) {
    const options = list(slot).map(toID).map(id => (id.startsWith('hiddenpower') ? 'hiddenpower' : id));
    const pick = options.find(id => ok.has(id) && !ITEM_MOVES.has(id) && !moves.includes(id));
    if (pick) moves.push(pick);
    else lost.push(...options.filter(id => !ok.has(id)));
  }
  return {moves, lost: [...new Set(lost)], lostSlots: set.moves.length - moves.length};
}

// How far the sets Smogon actually rated this species with (its own tier's format) fall short in-app:
// the fewest slots any of them loses, and which moves. Null when that format has no sets.
function ratedShortfall(sets, ok) {
  let best = null;
  for (const set of Object.values(sets)) {
    const f = fit(set, ok);
    if (!best || f.lostSlots < best.lostSlots) best = f;
  }
  return best;
}

// Best Smogon set for the app: most moves still learnable, own format preferred, no Choice/doubles.
function bestSet(sets, formats, ok) {
  let best = null;
  formats.forEach((format, rank) => {
    for (const [name, set] of Object.entries(sets[format] ?? {})) {
      const {moves, lost} = fit(set, ok);
      const items = list(set.item);
      const score = moves.length * 10 - rank - (items.some(i => /Choice/.test(i)) ? 15 : 0) - (/vgc|doubles|2v2/.test(format) ? 8 : 0);
      if (!best || score > best.score) best = {format, name, set, moves, lost, items, score};
    }
  });
  return best && best.moves.length >= 3 ? best : null;
}

function role(moveIDs) {
  const moves = moveIDs.map(id => dex.moves.get(id));
  const status = moves.filter(m => m.category === 'Status').length;
  const physical = moves.filter(m => m.category === 'Physical').length;
  const special = moves.filter(m => m.category === 'Special').length;
  return {
    role: moves.some(m => SETUP.has(m.id)) ? 'setup' : status >= 2 ? 'support' : 'attacker',
    category: physical && special ? 'mixed' : special ? 'special' : physical ? 'physical' : 'status',
  };
}

const [speciesRows, nameRows, abilityRows] = await Promise.all(
  ['pokemon_species', 'pokemon_species_names', 'abilities'].map(csv));
const setsRes = await fetch(SETS_URL);
if (!setsRes.ok) throw new Error(`sets: HTTP ${setsRes.status}`);
const SETS = await setsRes.json();

// PokéAPI language ids → the codes AppLanguage.apiCodes uses.
const LANG = {1: 'ja-Hrkt', 3: 'ko', 5: 'fr', 7: 'es', 9: 'en', 11: 'ja'};
const names = {};
for (const r of nameRows) {
  const code = LANG[r.local_language_id];
  if (code && +r.pokemon_species_id <= MAX_ID) (names[r.pokemon_species_id] ??= {})[code] = r.name;
}
const speciesByID = Object.fromEntries(speciesRows.map(r => [r.id, r]));
const abilitySlug = Object.fromEntries(abilityRows.map(r => [r.id, r.identifier]));
const rootOf = id => { let r = speciesByID[id]; while (r.evolves_from_species_id) r = speciesByID[r.evolves_from_species_id]; return +r.id; };

const out = [];
for (let id = 1; id <= MAX_ID; id++) {
  const species = dex.species.all().find(s => s.num === id && !s.forme);
  const row = speciesByID[id];
  const ok = await learnable(species);
  const smogonTier = species.tier;
  const baseTier = TIER[smogonTier] ?? 'F';
  const formats = [...new Set([...(OWN_FORMATS[baseTier] ?? []), ...FORMAT_ORDER, ...Object.keys(SETS[species.name] ?? {})])];
  const set = bestSet(SETS[species.name] ?? {}, formats, ok);

  let build, source, lostMoves = [], lostSlots = 0, keyItem = false;
  if (set) {
    const auto = autoBuild(species, ok);
    const moves = [...set.moves];
    for (const m of auto.moves) if (moves.length < 4 && !moves.includes(m)) moves.push(m);
    build = {
      ability: list(set.set.ability)[0] ?? species.abilities[0],
      nature: list(set.set.nature)[0] ?? auto.nature,
      evs: list(set.set.evs)[0] ?? auto.evs,
      moves,
    };
    source = {kind: 'smogon', format: set.format, set: set.name};
    lostMoves = set.lost;
    lostSlots = set.set.moves.length - set.moves.length;
    keyItem = set.items.length > 0 && set.items.every(i => KEY_ITEMS.test(i));
  } else {
    build = autoBuild(species, ok);
    source = {kind: 'auto'};
  }
  // Judge the tier by the sets it was rated with (its own tier's format), not by whichever set happened
  // to survive best — and also when none survived and the build is automatic (Blissey, Chansey).
  const rated = ratedShortfall(SETS[species.name]?.[OWN_FORMATS[baseTier]?.[0]] ?? {}, ok);
  if (rated) { lostMoves = rated.lost; lostSlots = rated.lostSlots; }

  // Lower the tier where the app can't reproduce the rated sets: one step if they lose a move, two if
  // even the closest one loses two or more, one more for a key item — max two in all, never past E
  // (F already means "not fully evolved").
  let tier = baseTier;
  let reasons = [];
  let steps = 0;
  if (lostSlots > 0) { reasons.push('moves'); steps += lostSlots >= 2 ? 2 : 1; }
  if (keyItem) { reasons.push('item'); steps += 1; }
  if (tier !== 'F') tier = TIERS[Math.min(TIERS.indexOf(tier) + Math.min(steps, 2), TIERS.indexOf('E'))];
  // Only an actual drop is an adjustment — an E or F species can't go lower, so don't claim it did.
  if (tier === baseTier) reasons = [];

  const abilityID = dex.abilities.get(build.ability).num;
  const lostMoveIDs = lostMoves.map(m => dex.moves.get(m)).filter(m => m.exists).map(m => m.num);
  out.push({
    id,
    names: names[id],
    captureRate: +row.capture_rate,
    legendary: row.is_legendary === '1',
    mythical: row.is_mythical === '1',
    baseID: rootOf(id),
    types: species.types.map(t => t.toLowerCase()),
    smogonTier,
    tier,
    ...(reasons.length && {adjusted: {from: baseTier, reasons, ...(lostMoveIDs.length && {lostMoves: lostMoveIDs})}}),
    ...role(build.moves),
    build: {
      ability: abilitySlug[abilityID],
      nature: toID(build.nature),
      // StatSpread's own keys, all six present, so the app decodes it directly.
      evs: Object.fromEntries(Object.entries(EV_KEYS).map(([from, to]) => [to, build.evs[from] ?? 0])),
      moves: build.moves.map(m => dex.moves.get(m).num),
    },
    source,
  });
}

const counts = {};
for (const s of out) counts[s.tier] = (counts[s.tier] ?? 0) + 1;
fs.writeFileSync(OUT, JSON.stringify({generated: new Date().toISOString().slice(0, 10), species: out}) + '\n');
console.log(`${out.length} species →`, OUT, counts,
  'adjusted:', out.filter(s => s.adjusted).length, 'auto:', out.filter(s => s.source.kind === 'auto').length);

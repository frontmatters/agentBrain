# Design: `/architect` skill

**Datum:** 2026-08-07
**Status:** goedgekeurd door user (sessie 2026-08-07)
**Aanleiding:** een recente klant-architectuur-analyse (bouwstenen → constraints
→ hosting-ontwerp → open vragen; dossier in de vault) bleek een herhaalbare werkwijze.
Deze skill legt die werkwijze vast zodat een goedkoper model (Haiku/Sonnet) haar
kan uitvoeren zonder duur model + verse context.

## Doel

Eén skill die de volledige architect-cyclus afdekt voor een bestaand systeem:

1. bouwstenen identificeren,
2. constraints/hosting-eisen in kaart brengen,
3. ontwerpbeslissingen nemen met aanbevelingen,
4. open vragen expliciet maken.

Uitvoerbaar door een goedkoper model dankzij rigide scaffolding: vaste
templates, harde bewijsregels en een deterministisch validatiescript.
Kwaliteitsborging van het ontwerp-deel optioneel via de bestaande
`/peer-review`-skill (vlag, default uit).

## Niet-doelen

- Greenfield-architectuur zonder bestaand systeem (daarvoor: brainstorming +
  writing-plans).
- Repo-distillatie/herontwerp van code zelf (daarvoor: `/scanman`).
- Automatische implementatie van de gekozen architectuur.

## Plek & vorm

`~/agentBrain/local/skills/architect/` — experimenteel eerst; promoten naar
`system/skills/` via `/promote` zodra 2× bewezen (2×-regel).

```
local/skills/architect/
  SKILL.md              # workflow + gates + output-contract
  templates/
    00-recon.md         # structuur-/touchpoint-tabel
    01-bouwstenen.md    # component / waar / rol / trust-niveau
    02-constraints.md   # zes vaste lenzen
    03-decision.md      # decision-record (één per beslissing)
    04-open-vragen.md   # ⚠ Open-ledger
  scripts/
    validate.sh         # deterministische vorm-check
```

Frontmatter van SKILL.md volgt het scanman-voorbeeld: `name`, `description`
(met triggers: "architectuur-analyse", "bouwstenen identificeren", "wat is er
nodig om X op Y te runnen", "decision record"), `argument-hint:
<repo-pad of project-slug> [ontwerpvraag] [--peer-review] [--lang en|nl] [--html]`,
`user-invocable: true`, `resources:` (templates + validate.sh).

## Taal

- Default-output is **Engels** (dossiers zijn hand-over-materiaal); met
  `--lang` of op verzoek schrijft de skill in de voertaal van de sessie.
- Veld-markers zijn taal-onafhankelijke vaste tokens (`evidence:`, `⚠ Open`,
  sectie-anchors uit de templates), zodat `validate.sh` deterministisch blijft
  ongeacht de proza-taal.

## Flowcharts & HTML-render

- Het dossier-template verplicht minimaal twee mermaid-diagrammen in de
  markdown zelf: (1) het mentale model — componenten + dataflow, (2) het
  egress-/zone-diagram. `validate.sh` checkt op aanwezigheid van ≥2
  ` ```mermaid `-blokken.
- Met `--html` (of op verzoek) rendert de skill het dossier naar een
  self-contained HTML-pagina met de flowcharts, door te delegeren naar de
  bestaande `brain-explain`-skill (die vault-notes al themed naar HTML rendert,
  incl. mermaid). Geen eigen renderer; het markdown-dossier blijft de bron.

## Workflow — vijf fasen, harde volgorde

### Fase 0 — Recon [blokkeert alle volgende fasen]

- Eerst `brain_search` op het onderwerp: bestaat er al een dossier/explainer?
  Bestaand materiaal wordt input, nooit genegeerd.
- Dan de repo mappen met `ls`/`grep` (grep-first per concern) tot de
  touchpoint-tabel uit `00-recon.md` compleet is.
- Verbod: concluderen of een latere fase starten vóór de tabel af is
  ("map eerst, patch dan" — het move-blok-0-principe uit wargame 09).

### Fase 1 — Bouwstenen

Tabel per component: **component / waar (pad) / rol / trust-niveau**. Elke rij
heeft een verplicht `evidence:`-veld (pad of grep-hit). Trust-niveau benoemt
expliciet wat privileged is (de blast radius) en wat gedelegeerd wordt aan
derden.

### Fase 2 — Constraints

Zes vaste lenzen, elk verplicht ingevuld met bewijs óf "⚠ Open":

1. **egress** — welke outbound verbindingen, naar wie, met welke payload
2. **data/storage** — waar leeft state, wat is verplaatsbaar/encrypted
3. **secrets** — waar staan credentials, hoe geïnjecteerd
4. **identity/toegang** — authN/authZ, rollen, enforcement-punt
5. **compliance/papierwerk** — welke regimes gelden (GDPR/DORA/…), welk bewijs
6. **operatie** — logging, monitoring, health, incident-pad

### Fase 3 — Beslissingen

Per ontwerpvraag één decision record (`03-decision.md`):
**context → opties (≥2) → trade-offs → aanbeveling → abort-condities**.

Met `--peer-review`: het fase-3-concept gaat door de bestaande
`/peer-review`-skill (event-bus, ander model) en het verdict wordt verwerkt
vóór oplevering. Default: uit.

### Fase 4 — Open vragen

`04-open-vragen.md` is de ⚠ Open-ledger. Kernregel: **een open vraag is een
geldig resultaat** — nooit invullen wat niet te weten valt. Elke open vraag
noemt wie/wat het antwoord kan leveren.

## Evidence-regels (het cheap-model-hart)

1. Elke feitclaim heeft `evidence:` — een pad, grep-hit of commando-output.
2. Onbekend → "⚠ Open"; een aanname mag nooit als feit worden opgeschreven.
3. Geen lege secties of "TBD" bij oplevering.

`validate.sh` dwingt dit deterministisch af:

- alle template-secties aanwezig en niet-leeg;
- alle `evidence:`-paden bestaan op het filesystem;
- geen "TBD"/"TODO" in de oplevering;
- elk decision record heeft ≥2 opties en ≥1 abort-conditie;
- de open-vragen-ledger bestaat.

Faalt de check → het model fixt vóór presenteren. Validate vangt vorm-fouten;
denk-fouten vangt de optionele peer-review.

## Output-contract

- **agentBrain:** `local/projects/<slug>/architecture.md`, aangemaakt via
  `scripts/new-note.sh` (correcte frontmatter + UUID5; de validate-hook rejectt
  handmatige id's).
- **Doel-repo:** kopie naar `docs/architecture/<datum>-<onderwerp>.md` zodat de
  repo self-contained is.

## Foutafhandeling

- Geen toegang tot de repo/het pad → stop met duidelijke melding (geen
  fantasie-analyse).
- `brain_search` leeg → filesystem-fallback conform het lookup-first-protocol.
- `validate.sh` faalt → fixen en opnieuw valideren; presenteren met een falende
  validatie is een auto-fail.
- Peer-review-verdict negatief → decision record herzien of de onenigheid
  expliciet in het record opnemen (nooit stilzwijgend negeren).

## Acceptatietest

Proefrun met een goedkoper model (Agent-tool, `model: haiku` of `sonnet`) op een
bekende casus uit de vault (het klant-dossier waar deze werkwijze uit voortkomt;
benchmark: de bestaande explainer + sessie-analyse aldaar). De skill is geslaagd als het
goedkope model met de skill een dossier oplevert dat qua bouwstenen, constraints
en open vragen ≈ overeenkomt met de benchmark, en `validate.sh` groen is.

## Beslissingen (uit de brainstorm)

| Vraag | Besluit |
|---|---|
| Scope | Volledige cyclus (analyse + ontwerp + open vragen) |
| Output | agentBrain (`local/projects/<slug>/`) + kopie in doel-repo |
| Kwaliteitsborging | Aanpak A (templates + gates) met optionele `--peer-review`-vlag |
| Plek | `local/skills/` eerst, promote na 2× bewezen |
| Taal | Default EN; voertaal via `--lang`/op verzoek; markers taal-onafhankelijk |
| HTML | Verplichte mermaid-diagrammen in het dossier; render via `brain-explain` (`--html`) |

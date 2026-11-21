# Juju

WoW Forever-addon (klient 1.60.x, `## Interface: 16001`) som viser **hva mobben du har som target dropper, med drop-%**, og lar deg **søke på et item for å finne den beste mobben å farme**.

Drop-% blir bedre jo flere som deler data: hver spiller teller hva mobs dropper, og tellingene slås sammen til felles tall for alle.

*English summary at the bottom.*

---

## Funksjoner

- **Drop-liste ved target:** klikk på en mob, så vises det den dropper, med høyest % øverst. Listen skjules når du angriper og kommer tilbake når kampen er over. Vinduet kan dras dit du vil.
- **To kilder for %:**
  - hvit % kommer fra Wowhead (via QuestieDB)
  - grønn % kommer fra Juju: dine egne kills pluss det andre spillere har delt
  - drops uten kjent % skjules til det finnes minst 10 kills av mobben
- **Søk:** `/juju linen` eller klikk på Juju-knappen ved minimap. Du får opp alle mobs som dropper itemet, med level, sone og %.
- **Deling:** `/juju eksport` lager en tekst du kan sende inn (se under).

## Installasjon

1. Last ned `Juju.zip`: GitHub → *Actions* → siste «Bygg»-kjøring → *Artifacts*.
2. Pakk ut slik at du får `World of Warcraft/_forever_/Interface/AddOns/Juju/Juju.toc`.
3. Dobbeltklikk `Juju/Opplaster/installer.cmd` én gang, så deles dropsene dine automatisk og du får fellesdata fra alle (se under). Dette kan hoppes over.
4. Start spillet og sjekk at Juju er huket av i AddOns-listen.

## Kommandoer

| Kommando | Gjør |
|---|---|
| `/juju` | Åpne søket |
| `/juju <navn>` | Søk direkte, for eksempel `/juju runecloth` |
| `/juju eksport` | Vis dataene dine som tekst du kan sende inn |
| `/juju deling` | Skru automatisk deling via Juju-opplasteren av og på |
| `/juju target` | Skru drop-listen ved target av og på |
| `/juju flytt` | Sett drop-listen tilbake under target-rammen |
| `/juju knapp` | Skjul eller vis minimap-knappen |

## Hjelp til med drop-% 🙌

Jo flere som deler, jo sikrere blir prosentene. Spesielt for sjeldne drops, som trenger hundrevis av kills.

**Automatisk med Juju-opplasteren (anbefalt):**
Opplasteren følger med i Juju-mappa (`Juju/Opplaster`).
1. Dobbeltklikk `Interface/AddOns/Juju/Opplaster/installer.cmd` én gang. Du trenger ikke administrator-rettigheter.
2. Ferdig. Hver kill og hva den droppet blir registrert av Juju. Når du logger ut eller skriver `/reload` (det er da WoW lagrer data), sender opplasteren det som er nytt. Samtidig henter den de nyeste fellesdataene fra alle spillere, og de vises i spillet etter neste `/reload`.

```
WoW (Juju) ──► SavedVariables ──► Juju-opplaster ──► Cloudflare ──► GitHub ──► fellesdata ──► alle
```

Skru av deling i spillet med `/juju deling`. Fjern opplasteren med `avinstaller.cmd`.

**Manuelt via GitHub:**
1. Skriv `/juju eksport` i spillet, eller klikk «Del mine data» i søkevinduet.
2. Trykk **Ctrl+C** for å kopiere teksten. Den starter med `JUJU1;`.
3. Gå til *Issues → New issue → «Send inn Juju-data»*, lim inn teksten og send.
4. En robot sjekker dataene, legger dem inn og svarer i issuet.

Du kan også legge ved filen `WTF/Account/<konto>/SavedVariables/Juju.lua`. Gi den nytt navn til `Juju.txt`, eller pakk den i en `.zip`, for GitHub godtar ikke `.lua`-filer som vedlegg.

**Via Discord:** lim inn teksten fra `/juju eksport`, eller legg ved `Juju.lua`, i Juju-kanalen. Vedlikeholderen legger den inn.

Send gjerne inn på nytt etter en tids spilling. Den nyeste innsendingen din erstatter den forrige, og ingenting telles dobbelt.

### Personvern

Bare tre ting deles: **mob-ID, antall kills og hvor mange ganger hvert item droppet**. Ingen karakternavn, ingen posisjon og ingen kontoinformasjon. Juju lager en tilfeldig, anonym ID per installasjon. Den brukes bare til at den nyeste innsendingen din erstatter den gamle, og til at dine egne kills ikke telles to ganger i spillet.

### Hvordan tallene holdes ærlige

- Bare den nyeste innsendingen per spiller teller, og én GitHub-konto teller som én spiller.
- Urimelige tall forkastes, for eksempel flere drops enn kills. Hver spiller kan påvirke hver mob med maks 5000 kills.
- Innsendte filer **kjøres aldri**. De leses av en egen parser, og bare tallene lagres.

## For utviklere

Se [CONTRIBUTING.md](CONTRIBUTING.md): hvordan data legges inn, sammenslåing, nytt uttrekk fra QuestieDB og tester.

## Lisens og kreditering

Juju er lisensiert under **GNU GPL v3.0** (se [LICENSE](LICENSE)).

- **Drop-data:** hentet fra [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0). Drop-ratene der kommer fra Wowhead.
- **Fellesdata (`Juju/SharedData.lua`):** delt av Juju-brukere.

---

## English summary

Juju is a WoW Forever addon that shows what your target drops (with drop chances) and lets you search an item to find the best mob to farm it. Drop rates come from Wowhead (via QuestieDB) and from counts shared by Juju players: run `/juju eksport` in game and paste the text into a *"Send inn Juju-data"* issue. A bot validates and merges it automatically. Only mob IDs, kill counts and item counts are shared. Licensed GPL-3.0. Drop data from QuestieDB (GPL-3.0).

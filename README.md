# Juju

WoW Forever-addon (klient 1.60.x, `## Interface: 16001`) som viser **hva mobben under musa dropper, med drop-%**, og lar deg **søke på et item for å finne den beste mobben å farme**.

Drop-% blir bedre jo flere som bruker Juju. Hver spiller teller hva mobs dropper, og Juju deler tellingene **automatisk inne i spillet** med andre Juju-spillere. Du trenger ikke installere noe annet enn addonen.

*English summary at the bottom.*

---

## Funksjoner

- **Drop-liste når musa er over en mob:** hold musa over en mob, så vises det den dropper, med høyest % øverst. Listen forsvinner når musa flyttes vekk, og skjules når du angriper. Den blir stående mens musa er over selve listen, så du kan dra den dit du vil.
- **To kilder for %:**
  - Ett tall som starter på Wowhead-% (via QuestieDB) og glir mot det Juju-spillerne faktisk ser, litt for hver kill. Jo flere kills, jo mer er det spillernes eget tall.
  - items fra skinning er merket «(Skinning)» og viser **skinning-%**, altså hvor ofte du får dem når du skinner mobben. Juju-spillernes skinning telles for seg og deles som drops. Står det «skinnable», finnes det ingen skinning-data ennå.
  - items som bare Juju kjenner, vises fra første drop (dempet de første kills)
- **Søk:** `/juju linen`, eller klikk på Juju-knappen ved minimap. Du får opp alle mobs som dropper itemet, med level, sone og %.
- **Automatisk deling:** hver kill og hva den droppet deles med Juju-spillere i guilden din, gruppen din og Juju-kanalen.

## Installasjon

1. Installer Juju fra CurseForge, eller last ned `Juju.zip`: GitHub → *Actions* → siste «Bygg»-kjøring → *Artifacts*.
2. Pakk ut slik at du får `World of Warcraft/_forever_/Interface/AddOns/Juju/Juju.toc`.
3. Start spillet og sjekk at Juju er huket av i AddOns-listen.
4. Juju-kanalen står på **ON** fra start. Da deler du med alle Juju-spillere på realmen, ikke bare guild og gruppe. Kanalen vises ikke i chatten. Knappen **ON/OFF** ved tittelen i Juju-søket, eller `/juju channel`, slår den av og på.

## Kommandoer

All tekst i Juju er på engelsk (fra 1.5.0). De gamle norske kommandoene i parentes virker fortsatt.

| Kommando | Gjør |
|---|---|
| `/juju` | Åpne søket |
| `/juju <navn>` | Søk direkte, for eksempel `/juju runecloth` |
| `/juju channel` (`kanal`) | Slå Juju-kanalen av og på (ON fra start) |
| `/juju sync` | Vis status for delingen: hvor mange spillere og hvor det sendes |
| `/juju share` (`deling`) | Skru delingen av og på |
| `/juju export` (`eksport`) | Vis dataene dine som tekst, for manuell innsending |
| `/juju target` (`list`) | Skru drop-listen (mus over mob) av og på |
| `/juju move` (`flytt`) | Sett drop-listen tilbake til standardplassen |
| `/juju button` (`knapp`) | Skjul eller vis minimap-knappen |

## Slik blir drop-% bedre for alle

```
deg ──┐                                            ┌──► nye spillere
guild ┼─► Juju deler usynlig i spillet ─► vedlikeholderens Juju ─► GitHub (fellesdata) ─► ny versjon
gruppe┘   (og videre fra spiller til spiller)
```

1. **Du dreper og looter.** Juju teller hver kill og hva den droppet.
2. **Juju deler med Juju-spillere** i guild, gruppe og Juju-kanalen. Det skjer med usynlige addon-meldinger, sakte og aldri i kamp. Dataene sprer seg videre fra spiller til spiller, så de når også dem du aldri treffer.
3. **Vedlikeholderen samler alt** og legger det inn i fellesdataene på GitHub.
4. **De nyeste fellesdataene deles også i spillet.** GitHub signerer fellesdataene digitalt. Har en Juju-spiller nyere fellesdata enn deg, får du dem automatisk, og du trenger ikke laste ned Juju på nytt. Juju sjekker signaturen og kaster alt som er endret eller forfalsket.

Delingen bruker bare det spillet selv tillater. Sier spillet nei til en vei, for eksempel guild-meldinger på en realm, slutter Juju å prøve den veien for resten av økten.

**Manuell innsending** (for eksempel hvis du sjelden er pålogget samtidig med andre):
`/juju export` → **Ctrl+C** → GitHub *Issues → New issue → «Send inn Juju-data»* → lim inn. Eller lim inn i Juju-kanalen på Discord.

### Personvern

Bare tre ting deles: **mob-ID, antall kills og hvor mange ganger hvert item droppet**. Ingen posisjon og ingen kontoinformasjon. Juju lager en tilfeldig, anonym ID per installasjon, slik at nyeste data erstatter eldre og ingenting telles dobbelt. I spillet ser mottakeren navnet på karakteren som sendte meldingen, slik det alltid er med addon-meldinger, men navnet lagres ikke i fellesdataene.

### Hvordan tallene holdes ærlige

- **I gruppe og raid telles hvert lik én gang.** Juju-spillerne i gruppa avtaler usynlig hvem som teller det, og den som teller får med alle items som noen så.
- **Fellesdataene er signert av GitHub.** Ingen kan forfalske dem, selv om de deles fra spiller til spiller.

- **Alt sjekkes etter de samme reglene overalt:** inne i spillet, hos mottakeren og på GitHub. Urimelige tall forkastes, for eksempel flere drops enn kills, og hver spiller kan påvirke hver mob med maks 5000 kills.
- **Juju tar bare imot data den selv har bedt om.** Én spiller kan føre inn maks 30 nye spillere per dag, og maks 1000 lagres.
- **Bare den nyeste versjonen per spiller teller.**
- **Innsendt data kjøres aldri.** Den leses som tall.

## For vedlikeholdere og utviklere

Se [CONTRIBUTING.md](CONTRIBUTING.md): opplasteren (bare hos vedlikeholderen), Cloudflare-mottakeren, sammenslåing, nytt uttrekk fra QuestieDB og tester.

## Lisens og kreditering

Juju er lisensiert under **GNU GPL v3.0** (se [LICENSE](LICENSE)).

- **Drop-data:** hentet fra [QuestieDB](https://github.com/Questie/Questie) (GPL-3.0). Drop-ratene der kommer fra Wowhead.
- **Fellesdata (`Juju/SharedData.lua`):** delt av Juju-spillere.

---

## English summary

Juju is a WoW Forever addon that shows what the mob under your mouse drops (with drop chances) and lets you search an item to find the best mob to farm it. Drop rates come from Wowhead (via QuestieDB) and from counts Juju players share automatically in-game (invisible addon messages to guild, group and an optional hidden "JujuData" channel). The maintainer's copy forwards everything to GitHub, so every new version ships the community numbers. Players install nothing but the addon. Only mob IDs, kill counts and item counts are shared. Licensed GPL-3.0. Drop data from QuestieDB (GPL-3.0).

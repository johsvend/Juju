# Juju – plan: deling av drop-data mellom spillere

**Mål:** Juju skal bli bedre jo flere som bruker den. Hver spiller teller hva mobs dropper. Tellingene deles og slås sammen, så «?» erstattes av ekte drop-% fra WoW Forever.

**Status (v1.4, 21.11.2026):**

| Del | Status |
|---|---|
| 1.1–1.3 Kildekode i repo, GPL-3.0, kreditering, uttrekksverktøy | ✅ Ferdig. `AddOns/Juju` er en junction til `Juju/` i repoet. |
| 1.4 MatsPrice: lisens og kreditering | ✅ LICENSE og TOC-felt lagt til. Ikke flyttet inn i noe repo. |
| 2.1 Egne og delte tall, uten dobbelttelling | ✅ Gjort med snapshot ved eksport og `SharedData.lua`, i stedet for `peers`. |
| 2.2 Ingen dobbelttelling i gruppe | ✅ v1.4: gruppa avtaler hvem som teller hvert lik, med alle items. |
| 2.3 Hvor sikkert tallet er (kills og spillere) | ✅ Vises i listen og tooltip. Fargekoding etter sikkerhet gjenstår. |
| 2.4 Ingen «?» | ✅ Skjules til det finnes minst 10 kills. |
| 3 Deling inne i spillet | ✅ v1.3: guild, gruppe/raid og Juju-kanalen. Data spres videre, med grenser og sjekk. Ikke testet i ekte spill ennå. |
| Innsamling til GitHub: din Juju → opplaster (bare hos deg) → Cloudflare → GitHub | ✅ Bygget og testet lokalt. ⏳ Cloudflare-mottakeren må settes opp (se `cloudflare/README.md`). |
| 4 Innsending (GitHub-skjema, robot, Discord-veiledning) og sammenslåing | ✅ Ligger på GitHub (johsvend/Juju), og jobbene kjører. |
| Fellesdata deles i spillet (signert av GitHub) | ✅ v1.4. Ikke testet i ekte spill ennå. |
| 5 README, endringslogg | ✅ |
| 5 CurseForge/Wago | ⏸ Utsatt etter ønske. |

---

## Fase 1 – Klargjøre for deling (kildekode og lisens)

| # | Oppgave | Ferdig når |
|---|---|---|
| 1.1 | Flytt kildekoden for Juju til dette repoet (`Documents/Juju`). Addon-mappa i WoW blir en kopi eller lenke. | Koden ligger i git, og installasjon i WoW virker som før. |
| 1.2 | Legg til lisensen **GPL-3.0** (`LICENSE`). Kreditér QuestieDB i `README.md` og i `Juju.toc`. | Fil og kreditering på plass. *Påkrevd: drop-dataene kommer fra QuestieDB (GPL-3.0).* |
| 1.3 | Legg uttrekksskriptet (`tools/extract_drops.py`) i repoet, så `DropData.lua` kan bygges på nytt når QuestieDB oppdateres. | `python tools/extract_drops.py` lager en identisk `DropData.lua`. |
| 1.4 | Gjør det samme for MatsPrice (eget repo eller mappe): GPL-3.0 og kreditering, siden spawn-dataene også kommer fra QuestieDB. | Som 1.2. |

## Fase 2 – Bedre datakvalitet lokalt (grunnlaget for deling)

| # | Oppgave | Ferdig når |
|---|---|---|
| 2.1 | **Ny lagringsform:** tellinger per kilde. Egne tall i `mine`, andre spillere i `peers[spiller-id]`, og innebygde fellestall i `shipped`. Gamle `mobs` flyttes over automatisk. | `/reload` med gammel database gir samme tall som før. |
| 2.2 | **Ingen dobbelttelling i gruppe:** bare den som looter liket teller det, og lik-GUID huskes. | Test: to spillere i gruppe dreper 10 mobs og får 10 kills totalt, ikke 20. |
| 2.3 | **Visning av hvor sikkert tallet er:** «8 % (40/500 kills, 12 spillere)». Fargen viser sikkerheten: grå under 20 kills, gul under 100, hvit over. | Drop-listen og søket viser kills og antall spillere. |
| 2.4 | **Erstatte «?»:** vis egen eller delt % når den finnes. Helt ukjente vises nederst som «–». | Ingen «?» der vi har tall. |

## Fase 3 – Deling inne i spillet

Addons kan ikke bruke internett. Deling skjer med addon-meldinger (`C_ChatInfo.SendAddonMessage`). Det virker på Forever, for VoidGather brukte det.

| # | Oppgave | Detaljer |
|---|---|---|
| 3.1 | **Protokoll** | Prefiks `JUJU1`. Meldinger er på maks 255 tegn. Formatet er `versjon;npcID;kills;item:antall,item:antall`. Store lister deles i flere meldinger. |
| 3.2 | **Kanaler** | Guild og gruppe/raid først. Deretter eventuelt en egen kanal for alle Juju-brukere på realmen, hvis klienten tillater at addons blir med i kanaler (må testes). |
| 3.3 | **Sende** | Bare nye endringer siden sist (delta), maks rundt 1 melding per sekund, aldri i kamp. Full synk når noen ber om det («hei, jeg er ny»). |
| 3.4 | **Motta og slå sammen** | Lagres per avsender i `peers`. Totalen er summen av alle kilder, uten egne tall to ganger. |
| 3.5 | **Beskyttelse mot tull-data** | Avvis urimelige tall, for eksempel flere drops enn kills eller over 5000 kills av én mob på kort tid. Begrens hvor mye én spiller kan påvirke én mob. Mulighet til å se bort fra en bestemt spiller. |
| 3.6 | **Innstillinger** | Avkryssinger for «Del data med guild/gruppe/realm» og «Motta data». Begge står på fra start, og alt kan skrus av. |
| 3.7 | **Personvern** | Bare mob-ID, kills og item-tellinger deles. Ingen posisjon og ingen andre data om spilleren. |

**Ferdig når:** to kontoer i samme guild ser hverandres kills i Juju innen et minutt, uten lagg eller spam, og uten «blocked action».

## Fase 4 – Felles data i hver ny versjon

Deling i spillet når bare dem som er pålogget samtidig. For at *nye* spillere skal få alt fra dag én, bygges fellestallene inn i hver versjon.

| # | Oppgave | Ferdig når |
|---|---|---|
| 4.1 | **Innsending:** spillere sender inn `WTF/Account/<konto>/SavedVariables/Juju.lua` via GitHub, Discord eller e-post. Senere kan en «Eksporter»-knapp i Juju lage en tekst å lime inn. | Fremgangsmåten er beskrevet i README. |
| 4.2 | **Sammenslåingsskript** (`tools/merge_submissions.py`): leser alle innsendte filer, fjerner duplikater og avvikere, og skriver `SharedData.lua`. | Skriptet kjører på en mappe med filer og gir én fil. |
| 4.3 | Juju leser `SharedData.lua` som kilden `shipped` i tillegg til egne og delte tall. | Nye brukere ser tall uten å ha drept noe. |
| 4.4 | Fast rutine: slå sammen og legge ut ny versjon, for eksempel annenhver uke. | Rutinen er dokumentert. |

## Fase 5 – Publisering

| # | Oppgave | Ferdig når |
|---|---|---|
| 5.1 | README på norsk og engelsk: hva Juju gjør, kommandoer, deling og personvern. | |
| 5.2 | Versjonsnummer og endringslogg (`CHANGELOG.md`). | |
| 5.3 | Legge ut på CurseForge og/eller GitHub Releases med `## Interface: 16001`. | Andre kan installere Juju. |
| 5.4 | Kanal for tilbakemeldinger (GitHub Issues eller Discord). | |

---

## Risiko og åpne spørsmål

- **Klientsperrer:** Forever sperrer noen funksjoner for addons (combat-log, minimap-tooltip). Det må testes tidlig om addon-meldinger og egne kanaler er tillatt. Det er første oppgave i fase 3.
- **Sjeldne drops:** en drop på 1 % trenger flere hundre kills før tallet er sikkert. Vanlige drops blir gode raskt.
- **Tull-data:** én spiller kan sende feil tall med vilje. Det løses med begrensning per spiller og ved å se bort fra avvikere (3.5).
- **Vedlikehold:** noen må kjøre sammenslåingen og legge ut nye versjoner (fase 4.4).
- **Lisens:** GPL-3.0 betyr at koden må være åpen. Det passer godt med et fellesskapsprosjekt.

## Rekkefølge

1. Fase 1 (lisens og repo). Kort jobb, og må gjøres før noe deles.
2. Fase 2 (datakvalitet). Gjør tallene troverdige.
3. Fase 3 (deling i spillet). Begynner med å teste at addon-meldinger virker på Forever.
4. Fase 4 (felles data i versjonene).
5. Fase 5 (publisering).

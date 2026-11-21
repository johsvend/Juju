# Juju – for vedlikeholdere og utviklere

## Oppbygning

| Sti | Hva |
|---|---|
| `Juju/` | Selve addonen. I WoW er `Interface/AddOns/Juju` en *junction* som peker hit, så endringer virker etter `/reload`. |
| `Juju/DropData.lua` | Wowhead-% og drops fra QuestieDB. Generert av `tools/extract_drops.py`. |
| `Juju/SharedData.lua` | Felles tellinger fra spillere. Generert av `tools/merge_submissions.py`. **Skal ikke redigeres for hånd.** |
| `data/submissions/` | Én renset fil per spiller (`<id>.txt`, eksportformat). |
| `data/authors.json` | Hvilken spiller-ID hver GitHub-konto har sendt inn, så én konto teller som én spiller. |
| `data/summary.md` | Kort oversikt etter siste sammenslåing. |
| `tools/` | Python-verktøy. Bare standardbiblioteket, unntatt `extract_drops.py`, som trenger `cbor2`. |
| `tests/` | `python -m unittest discover -s tests -v` |
| `.github/` | Innsendingsskjema og automatikk (GitHub Actions). |
| `Juju/Sync.lua` | Deling inne i spillet (addon-meldinger til guild, gruppe og Juju-kanalen). |
| `uploader/` | Juju-opplasteren. **Bare hos vedlikeholderen.** Ikke med i Juju.zip. |
| `cloudflare/` | Juju-mottakeren (Cloudflare Worker) som opplasteren sender til. |

## Hvordan data når GitHub

```
spillere ──(i spillet)──► din Juju ──(utlogging/reload)──► SavedVariables
   ──► Juju-opplasteren (din PC) ──► Cloudflare ──► data/submissions/<id>.txt ──► robot ──► SharedData.lua
```

1. **Alle Juju-spillere deler med hverandre i spillet** (`Sync.lua`). Din Juju tar vare på det den mottar (`JujuDB.peers`).
2. **Ved hver utlogging og `/reload`** skriver Juju alle poster som ikke allerede ligger i fellesdataene til `JujuDB.uploads`.
3. **Opplasteren på din PC** sender dem til mottakeren, med maks 50 spillere per forespørsel, og henter nyeste `SharedData.lua`. Hos deg er addon-mappa en junction til repoet, så der hopper opplasteren over hentingen, og fellesdataene kommer i stedet med `git pull`.
4. **Mottakeren lagrer én fil per spiller**, der nyeste vinner, og roboten slår sammen.

Jo mer du er pålogget i guild, gruppe og Juju-kanalen, jo mer samler din Juju inn.

### Installere opplasteren (bare deg, én gang)

1. Sett opp mottakeren først (se `cloudflare/README.md`), og sett adressen i `uploader/config.json`.
2. Dobbeltklikk `uploader/installer.cmd`. Det lager en planlagt oppgave som kjører hvert 5. minutt.
3. Loggen ligger i `%LOCALAPPDATA%\JujuUploader\log.txt`. Fjern opplasteren med `uploader/avinstaller.cmd`.

## Signeringsnøkkelen (viktig)

Fellesdataene signeres, slik at Juju trygt kan dele dem fra spiller til spiller.

- **Den private nøkkelen** ligger i `%USERPROFILE%\.juju\juju-signing-key.json` og som GitHub-hemmeligheten `JUJU_SIGNING_KEY`. **Den skal aldri inn i repoet.** Ta en sikkerhetskopi av filen, for eksempel på en minnepinne eller i en passordbehandler.
- **Den offentlige nøkkelen** ligger i `Juju/PubKey.lua`. Den kan bare *sjekke* signaturer, ikke lage dem.
- **Roboten signerer** i «Juju-data»-jobben. Mangler hemmeligheten, blir fellesdataene usignert, og da deler ikke Juju dem videre i spillet. Fellesdataene i selve addonen virker fortsatt.
- **Hvis nøkkelen er mistet eller lekket:**
  1. Lag en ny med `python tools/jujusign.py keygen <fil>`.
  2. Sett ny `J.PUBKEY_N` i `Juju/PubKey.lua` (`python tools/jujusign.py pubkey <fil>`).
  3. Oppdater hemmeligheten: `Get-Content <fil> -Raw | gh secret set JUJU_SIGNING_KEY`.
  4. Gi ut en ny versjon av Juju. Gamle versjoner godtar da ikke nye pakker før spillerne oppdaterer.
- **Signer lokalt:** sett miljøvariabelen `JUJU_SIGNING_KEY` til innholdet i nøkkelfilen før du kjører `tools/merge_submissions.py`.

## Legge inn data mottatt i Discord

```
python tools/ingest.py "C:\sti\til\Juju.lua"      # eller .txt / .zip, flere filer går fint
python tools/merge_submissions.py
git add -A data Juju/SharedData.lua
git commit -m "Juju-data: Discord-innsendinger"
git push
```

Innlimt tekst fra `/juju eksport`: lagre den som en `.txt`-fil og kjør `ingest.py` på filen.
`ingest.py` sjekker og renser dataene og lagrer bare tallene. En eldre innsending fra samme spiller erstatter aldri en nyere.

## Innsending via GitHub (automatisk)

`.github/workflows/juju-data.yml` kjører når et issue med etiketten `juju-data` opprettes eller redigeres:

1. `tools/ingest.py --issue` leser innlimt tekst eller vedlegg (bare fra GitHub sine egne vedleggsadresser).
2. `tools/merge_submissions.py` bygger `SharedData.lua` på nytt.
3. Endringene commites til `main`, og roboten svarer og lukker issuet.

Issue-teksten er utrygg. Den gis bare til Python via en miljøvariabel og kjøres aldri.

**Engangsoppsett på GitHub:** opprett etiketten `juju-data` (`gh label create juju-data --color 7fd4ff`), og sørg for at *Settings → Actions → General → Workflow permissions* står på «Read and write».

## Ny versjon av drop-data fra QuestieDB

```
pip install -r tools/requirements.txt
python tools/extract_drops.py            # bruker QuestieDB fra standard WoW Forever-installasjon
```

## Tester

- `python -m unittest discover -s tests -v`: parser, avvisning av tull-data, sammenslåing, «nyeste vinner», én spiller per konto, og issue-innsending.
- «Bygg»-workflowen kjører testene, sjekker Lua-syntaks med `luac5.1` og lager `Juju.zip`.

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

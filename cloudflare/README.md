# Juju-mottaker (Cloudflare Worker)

Tar imot data fra Juju-opplasteren og lagrer dem i GitHub-repoet (`data/submissions/<id>.txt`). Lagringen starter «Juju-data»-roboten, som slår alt sammen til `Juju/SharedData.lua`.

**Gratis:** Cloudflare Workers sin gratisplan tillater 100 000 forespørsler per dag, og en spiller sender høyst én gang per utlogging eller `/reload`.

## Engangsoppsett (rundt 10 minutter)

### 1. GitHub-nøkkel (bare for dette repoet)
1. GitHub → avataren din → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.
2. Fyll ut:
   - **Name:** `juju-mottaker`
   - **Expiration:** 1 år (sett en påminnelse om å fornye)
   - **Repository access:** *Only select repositories* → `johsvend/Juju`
   - **Permissions → Repository permissions → Contents:** *Read and write*. Ingenting annet.
3. Kopier nøkkelen (`github_pat_…`). Den vises bare én gang.

### 2. Cloudflare
1. Lag en gratis konto på https://dash.cloudflare.com/sign-up.
2. Kjør dette i en terminal i denne mappa (`cloudflare/`):
   ```
   npx wrangler login              # åpner nettleseren, godkjenn
   npx wrangler deploy             # laster opp mottakeren
   npx wrangler secret put GITHUB_TOKEN    # lim inn github_pat_… når den spør
   ```
3. `wrangler deploy` skriver ut adressen, for eksempel `https://juju-mottaker.<navn>.workers.dev`.
4. Test den ved å åpne adressen i nettleseren. Den skal svare «Juju-mottaker OK».

### 3. Koble opplasteren til
Sett adressen, med `/submit` på slutten, i `uploader/config.json`:
```json
"endpoint": "https://juju-mottaker.<navn>.workers.dev/submit"
```
Commit og push. Nye nedlastinger av Juju-opplasteren bruker da riktig adresse.

## Sikkerhet
- **Nøkkelen** ligger bare som en hemmelighet hos Cloudflare, aldri i koden. Den kan bare skrive filer i dette ene repoet.
- **Alt som sendes inn sjekkes** etter samme regler som `tools/jujudata.py`. Bare tall lagres, normalisert, og ingenting kjøres.
- **Den nyeste innsendingen per spiller vinner.** En eldre innsending kan ikke overskrive en nyere.
- **Maks 6 innsendinger per minutt per IP-adresse**, og maks 5000 kills per mob per spiller.

## Tester
`node --test` i denne mappa. GitHub simuleres, så ingenting sendes ut.

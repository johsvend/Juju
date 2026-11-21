# Endringslogg

## 1.4.3
- **Egne skinning-tall:** Juju teller skinning per mob (hvor mange ganger den er skinnet, og hva det ga), og deler og sender dem som drops. Teknisk lagres de som mob-ID + 10 000 000. Skinning-items viser skinning-%, ikke den lille sjansen for leather i vanlig loot. Uten data står det «skinnes». Søket viser mobs som gir itemet ved skinning.

## 1.4.2
- **Jevne tall uten kill-grense:** vist % = (Wowhead-% veid som 50 kills + Juju-drops) / (50 + Juju-kills). Hver kill fra en hvilken som helst Juju-spiller flytter tallet litt mot det spillerne faktisk ser, uten brå hopp. Items uten Wowhead-% vises fra første drop, dempet med 5 kills.

## 1.4.1
- **Ett gult tall per drop:** Juju-% vises i stedet for Wowhead-% når mobben har minst 10 kills og itemet har droppet. Ellers vises Wowhead-%. Tooltipen viser begge og hvilken som vises. Listene sorteres etter tallet som vises.
- **«(Skinning)» etter items fra skinning**, for eksempel leather, hides og scales. Juju lærer flere selv når du skinner, og skinning-loot telles fortsatt ikke som drop.

## 1.4.0
- **Ingen dobbelttelling i gruppe og raid:** Juju-spillerne i gruppa avtaler usynlig hvem som teller et lik (den med alfabetisk første navn blant dem som så det), og den som teller får med alle items alle så. Alene telles det som før.
- **Fellesdata deles i spillet:** GitHub signerer fellesdataene (RSA-2048 og SHA-256). Har noen nyere fellesdata, får du dem automatisk uten å laste ned Juju på nytt. Pakker med feil signatur kastes. Ingen karakternavn ligger i repoet.
- **Meldinger bruker `;` som skilletegn** i stedet for `|`, som er spillets spesialtegn.

## 1.3.3
- **Kanal-knappen viser ON/OFF** (grønn/rød) ved tittelen «Juju Monster Drop Search».
- **Juju-kanalen er ON fra start:** Juju blir med 10 sekunder etter innlogging. Velger du OFF, blir det stående OFF. Hvis spillet ikke tillater automatisk innmelding, prøver Juju aldri igjen av seg selv, og et klikk på OFF slår den på.

## 1.3.2
- **Søkevinduet:** tett, mørk bakgrunn og søkefelt med forstørrelsesglass. Forklaringslinjen og delingsstatusen er fjernet, mens knappen «Bli med i / Forlat Juju-kanalen» står nederst til høyre. Status vises med `/juju sync`.

## 1.3.1
- **Drop-listen følger musa:** den vises når musa er over en mob og forsvinner når musa flyttes vekk, i stedet for å vises ved klikk. Den blir stående litt, og så lenge musa er over listen, slik at den kan dras.

## 1.3.0
- **Deling inne i spillet, uten å installere noe:** Juju deler kill- og drop-tellinger usynlig med andre Juju-spillere i guild, gruppe/raid og Juju-kanalen. Dataene sprer seg videre fra spiller til spiller.
- **Juju-kanalen:** «Bli med i Juju-kanalen» i søkevinduet, eller `/juju kanal`. Kanalen er skjult fra chatten.
- **Sikkerhet:** alt som mottas sjekkes etter samme regler som på GitHub. Juju tar bare imot data den har bedt om, én spiller kan føre inn maks 30 nye spillere per dag, og maks 1000 lagres.
- **Forever-hensyn:** sier spillet nei til en vei, stenges den for resten av økten. Ingenting sendes i kamp, og maks 2 meldinger sendes per sekund.
- `/juju sync` viser status for delingen.
- **Opplasteren er bare for vedlikeholderen**, og er ikke lenger med i Juju.zip. Den sender alt vedlikeholderens Juju har samlet inn, mange spillere per forespørsel.
- **Ingen dobbelttelling:** hvis fellesdataene inneholder dine kills men det tilhørende snapshotet mangler, brukes bare fellesdataene.

## 1.2.0
- **Automatisk deling:** Juju lager opplastingstekst ved hver utlogging og `/reload` (bare hvis noe er nytt). Skru av med `/juju deling`.
- **Juju-opplasteren** (Windows, ingen installasjon av andre programmer): sender data til Juju-mottakeren hvert 5. minutt og henter nyeste fellesdata inn i addonen. Fellesdata sjekkes linje for linje før de skrives.
- **Juju-mottakeren** (Cloudflare Worker): sjekker innsendinger og lagrer dem i GitHub, der roboten slår dem sammen.
- **Én nedlasting:** opplasteren ligger i `Juju/Opplaster` i Juju.zip.
- Inntil 10 eksport-snapshots tas vare på, og alltid det fellesdataene inneholder, så egne kills aldri telles dobbelt.

## 1.1.0
- **Fellesdata:** Juju leser `SharedData.lua` med kill- og drop-tellinger fra andre spillere. Grønn % = Juju-data (dine og delte kills), med antall spillere.
- **Deling:** `/juju eksport` og knappen «Del mine data» viser dataene dine som tekst til innsending.
- **Ingen dobbelttelling:** når fellesdataene inneholder din egen tidligere innsending, trekkes den fra og dine nåværende tall brukes i stedet.
- Anonym installasjons-ID. Bare mob-ID, kills og item-tellinger deles.
- Lisens: GPL-3.0. Drop-data fra QuestieDB er kreditert.

## 1.0.x
- Drop-liste ved target med Wowhead-% (QuestieDB). Skjules i kamp og kan flyttes.
- Lærer egne drop-% fra kills og loot. Skinning og annen innsamling telles ikke.
- Søk på item for å finne beste mob å farme.
- Drops uten % skjules til det finnes minst 10 kills.
- Rettet: «blocked action» ved innlogging (combat-loggen er sperret i Forever) og vinduet festet til TargetFrame.

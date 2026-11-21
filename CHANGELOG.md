# Endringslogg

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

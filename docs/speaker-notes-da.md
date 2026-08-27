# Talernoter - RHEL Image Mode / bootc-demo

## Indledning

I dag vil jeg vise en anden måde at tænke på Linux-livscyklusstyring.

I stedet for at installere en server og løbende ændre den over tid definerer vi
operativsystemet som et image. Det image bygges fra kildekode, gemmes i et
registry og bruges som livscyklusartefakt for systemet.

Det vigtigste er ikke kun bootc som kommando. Det vigtige er den driftsmodel,
der bygges omkring den.

## Hovedbudskab

```text
Operativsystemet bliver et versionsstyret, reproducerbart artefakt,
der kan rulles tilbage.
```

## Hvorfor er det vigtigt?

Traditionel serveradministration skaber ofte:

- Konfigurationsdrift
- Manuel patching og vedligeholdelsesvinduer
- Uensartede miljøer
- Begrænsede muligheder for rollback
- Dårlig sporbarhed fra ændringsanmodning til kørende system

Image Mode flytter dette i retning af:

- Git-baseret ændringsstyring
- Reproducerbare builds
- Registry-baseret distribution
- Transaktionelle opdateringer
- Operationel rollback
- Bedre standardisering

## Hvorfor er immutable images og containere vigtige?

Et immutable image er en defineret version af operativsystemet. Vi behandler
ikke den kørende host som et sted, hvor man laver ukontrollerede, permanente
ændringer. Når systemet skal ændres, bygger og udruller vi i stedet en ny
image-version.

Containere bruger den samme model: imaget bygges én gang, promoveres gennem
pipeline'en og køres ensartet i hvert miljø. Containeren eller VM'en kan
udskiftes, mens imaget forbliver den sporbare kilde til dens tilstand.

Det er vigtigt, fordi det giver os:

- **Ensartethed:** Udvikling, test og produktion bruger det samme byggede artefakt.
- **Mindre drift:** Ændringer foretages i kilden og bygges igen i stedet for at
  blive udført forskelligt på de enkelte maskiner.
- **Sikrere drift:** Opdateringer kan testes og forberedes før genstart eller
  udrulning.
- **Hurtig gendannelse:** En mislykket opdatering kan rulles tilbage til et
  kendt, velfungerende image.
- **Sporbarhed:** Vi kan knytte det kørende system til en bestemt image-digest,
  kildeændring og pipeline-kørsel.

Immutable betyder ikke, at systemet aldrig kan ændres. Det betyder, at
ændringerne er tilsigtede, versionsstyrede og leveres gennem en kontrolleret
livscyklus.

## Demo-trin: Repository

Det siger jeg:

Dette repository er sandhedskilden. Containerfile definerer operativsystemets
tilstand, scripts automatiserer lokale operationer, GitHub Actions kan bygge
imaget, og Quay fungerer som distributionspunkt.

Hvorfor det er vigtigt:

Det gør ændringer i operativsystemet mulige at gennemgå og auditere, før de
bliver til kørende infrastruktur.

## Demo-trin: Containerfile

Det siger jeg:

Containerfile er stedet, hvor vi definerer den ønskede tilstand for
operativsystemet. Det kan omfatte pakker, filer, services og konfiguration.

Det er den vigtige forskel fra manuel serverkonfiguration: Containerfile
beskriver det ønskede image, mens det kørende system behandles som en udrullet
version af imaget.

Kundeværdi:

Det gør det muligt at etablere standardiserede operativsystem-baselines,
golden images og ensartede udrulningsmønstre.

## Demo-trin: Build

Det siger jeg:

Nu bygger vi operativsystem-imaget. Det minder om den måde, application teams
bygger container images på, men målet er et bootbart operativsystem.

Kundeværdi:

De samme governance-mønstre, som bruges til applikationer, kan nu anvendes på
operativsystemlaget.

Imaget er det immutable bindeled mellem build og runtime. Når det er bygget og
testet, kan det samme artefakt promoveres i stedet for at blive bygget eller
genskabt manuelt i hvert miljø.

## Demo-trin: Quay

Det siger jeg:

Imaget publiceres til Quay. Det betyder, at operativsystemets livscyklus nu er
knyttet til et registry-artefakt med tags, historik og mulighed for scanning og
signering.

Kundeværdi:

Registry bliver et kontrolleret distributionspunkt for standardiserede
operativsystem-images.

## Demo-trin: QCOW2 / VM

Det siger jeg:

For at gøre resultatet konkret konverterer vi bootc-imaget til en VM-disk og
starter den.

Kundeværdi:

Det forbinder moderne image-baseret livscyklusstyring med eksisterende
virtualiseringsmiljøer.

## Demo-trin: bootc status

Det siger jeg:

Det kørende system ved, hvilket image det er baseret på. Det giver os en tydelig
forbindelse mellem kildekode, image og den kørende host.

Kundeværdi:

Det forbedrer sporbarhed og supportmuligheder.

## Demo-trin: Opdatering

Det siger jeg:

I stedet for manuelt at patche individuelle pakker flytter vi systemet til en
ny image-version.

Kundeværdi:

Det gør ændringshåndtering mere forudsigelig og lettere at teste før produktion.

Vi erstatter systemet med en ny, deklareret version i stedet for at opbygge et
ukendt sæt pakkeændringer på den eksisterende host. Det er sådan, immutability
reducerer drift over tid.

## Demo-trin: Rollback

Det siger jeg:

Hvis den nye tilstand ikke fungerer, ruller vi tilbage til det tidligere kendte,
velfungerende image.

Kundeværdi:

Rollback bliver operationelt enkelt og en integreret del af livscyklusdesignet.

Fordi det tidligere image stadig er en kendt, velfungerende version, afhænger
gendannelse ikke af, at vi husker, hvilke individuelle pakker eller
konfigurationsfiler der blev ændret.

## Vinkler til forskellige målgrupper

### Linux-drift

Fokusér på:

- Standardiserede baselines
- Ensartet patching
- Mindre drift
- Hurtigere gendannelse

### OpenShift- / Kubernetes-teams

Fokusér på:

- GitOps-tankegang
- Immutable infrastruktur
- Platform engineering
- Udvidelse til OpenShift Virtualization

### Enterprise-arkitekter

Fokusér på:

- Governance
- Sporbarhed
- Software supply chain
- Livscyklusmodel

### Ledelse

Fokusér på:

- Lavere operationel risiko
- Mere forudsigelige ændringer
- Hurtigere rollback
- Tydeligt ejerskab

## Stærk afslutning

Dette demo handler ikke om at erstatte alle Linux-administrationsprocesser fra
den ene dag til den anden. Det handler om at vise, hvor Linux-livscyklusstyring
bevæger sig hen: mod versionsstyrede images, kontrollerede pipelines, registry-
distribution og sikrere Day 2-drift.

For mange kunder er det første skridt ikke en produktionsudrulning. Det første
skridt er en vurdering: Hvor kan image-baseret livscyklusstyring reducere drift,
forbedre compliance eller forenkle platformdrift?
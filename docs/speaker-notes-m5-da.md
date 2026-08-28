# Talernoter: RHEL Image Mode på Mac M5 og UTM

## Formål

Denne version er en 40-minutters demo af Image Mode med en Apple Silicon Mac,
en ARM64 UTM-VM og en valgfri OpenShift Virtualization-extension.

Alle tunge builds, qcow2-genereringer og registry-publiceringer skal være
færdige før sessionen. Live-demoen handler om den operationelle livscyklus:

```text
image -> VM -> opdatering -> fejl -> rollback -> rettelse
```

## Åbning

Titlen er:

> RHEL Image Mode: Fra pets til cattle – og videre til "immutable reality"

I dag viser jeg, hvad den titel betyder i praksis. Vi behandler ikke VM'en som
en unik server, der ændres manuelt over tid. Vi behandler den som en kørende
version af et image.

Det betyder ikke, at RHEL holder op med at være RHEL. Vi kan stadig bruge
systemd, SSH, services, logs og de normale driftsværktøjer. Forskellen er,
hvordan den ønskede OS-tilstand leveres og opdateres.

## 1. Image-modellen

Vis repository og forklar image-hierarkiet:

```text
rhel10-golden
    -> httpd-service
        -> webpage-v1 / webpage-broken / webpage-v3-fixed
```

Talepunkter:

- Golden image indeholder den fælles RHEL-baseline.
- Workload-images genbruger baselinen.
- Et image er et versionsstyret artefakt.
- Registryet er distributionspunktet.
- VM'en er en deployment af imaget.

## 2. Test som container

Kør imaget med Podman og vis websiden på `http://localhost:8080`.

Det viser, at bootc-images kan testes med mange af de samme værktøjer som
application containers. Vi tester først hurtigt, før vi involverer en VM.

Det er ikke det samme som at sige, at en container og en VM har samme runtime-
rolle. Pointen er, at build- og testmodellen kan genbruges.

## 3. Samme image som VM

Vis UTM-VM'en og kør:

```bash
sudo bootc status
curl localhost
```

Fremhæv booted image, digest, RHEL-version og eventuelle staged/rollback
deployments.

VM'en er nu en rigtig RHEL-server. Image Mode ændrer ikke de almindelige
driftsværktøjer; det ændrer livscyklussen for OS'et.

## 4. Test AI Lab Recipes-containeren først

Sæt `CHATBOT_IMAGE` til den præcise image-reference fra den valgte AI Lab
Recipes-opskrift. Kør containeren først separat med Podman og vis den i Podman
Desktop sammen med logs, port og image metadata.

Sig:

> Før vi gør chatbotten til en del af operativsystemets deployment, tester vi
> den som en almindelig container. Det gør fejlsøgning og godkendelse hurtigere.

Testen bruger `localhost:8081` som standard. Porten kan ændres i
`demo-env.sh`, hvis recipe-containeren lytter på en anden intern port.

## 5. Deploy chatbotten med bootc

Den næste image-version indeholder chatbotten som en systemd Quadlet. Quadlet-
filen beskriver containeren deklarativt, og systemd starter den sammen med VM'en.

Vis:

```bash
sudo bootc status
sudo systemctl status chatbot.service
```

Sig:

> Vi går fra en manuel container-test til en reproducerbar image-definition.
> Alle VM'er, der får den nye image-version, får samme containeropsætning.

## 6. Deploy en opdatering

Kør `bootc switch` til den nye webpage-version og genstart VM'en.

Sig:

> Vi ændrer ikke Apache eller filer manuelt på serveren. Vi bygger en ny
> deklareret version og lader VM'en skifte til den.

Vis den nye webside og `bootc status`. Peg på, at den tidligere deployment stadig
kan genkendes som rollback-version.

## 7. Vis en kontrolleret fejl

Skift til `demo-broken-arm64`. Denne version har med vilje en fejl, eksempelvis
at HTTPD ikke er enabled.

Vis `systemctl status httpd`, `curl localhost` og `bootc status`.

Vigtigt budskab:

> Immutable betyder ikke fejlfri. Det betyder, at fejlen er knyttet til en
> bestemt image-version, og at vi kan gå tilbage til den tidligere tilstand.

## 8. Rollback

Kør:

```bash
sudo bootc rollback --apply
```

Efter VM'en er tilbage, vis `bootc status` og websiden igen.

Sig:

> Recovery afhænger ikke af, at vi husker alle manuelle ændringer. Den tidligere
> deployment er et kendt image, som allerede er gemt på systemet.

## 9. Deploy rettelsen

Skift til `demo-v3-fixed-arm64`, genstart og vis websiden.

Forklar den realistiske proces:

```text
ændring i Git -> build og test -> image i registry -> promotion -> bootc switch
```

De images, der bruges live, er forberedt på forhånd for at undgå ventetid på
package- og disk-builds.

## 10. Mange VM'er fra samme repository-opdatering

Efter den fungerende version kan vi løfte blikket fra én VM til en hel flåde.
Alle VM'er kan følge samme image-reference, og den samme testede image-version
kan stages på flere systemer uden individuelle image-builds.

Kør den planlagte fleet-kommando og vis for eksempel:

```text
demo-web-01 (192.168.64.19) -> bootc switch demo-v3-fixed-arm64
demo-web-02 (192.168.64.20) -> bootc switch demo-v3-fixed-arm64
demo-web-03 (192.168.64.21) -> bootc switch demo-v3-fixed-arm64
demo-web-04 (192.168.64.22) -> bootc switch demo-v3-fixed-arm64
```

Sig:

> Den vigtige forskel på pets og cattle er ikke, at vi aldrig har flere hosts.
> Det er, at hosts ikke længere kræver hver sin manuelle behandling.

I denne lokale demo er fleet-visningen plan-only. I et rigtigt miljø sættes
`FLEET_APPLY=1`, og `VM_TARGETS` indeholder de faktiske SSH-targets. Reboots kan
derefter styres af en change window eller en automation-platform.

## 11. OpenShift Virtualization-extension

Denne del er kort og kan udelades, hvis hoveddemoen har brug for ekstra tid.

- OpenShift Virtualization opretter og kører VM'en.
- bootc styrer Image Mode-livscyklussen inde i VM'en.
- SNO'en bruger et forberedt AMD64-image.
- UTM-demoen bruger ARM64-images på Mac M5.
- Det er samme Containerfile og lifecycle-model, men ikke nødvendigvis samme
  binære image-digest.

## Afslutning

> Vi gik fra image til VM, fra VM til opdatering, fra fejl til rollback og fra
> rollback til en rettet version. Det er “pets til cattle” omsat til konkret
> Linux-drift.

Image Mode er ikke en magisk erstatning for al administration. Det er en anden
leverancemodel for OS'et, som giver versionsstyring, reproducerbarhed, bedre
sporbarhed og en enkel rollback-mekanisme.

## Trade-offs

- Images og registry bliver centrale afhængigheder.
- Opdateringer kræver disciplin omkring image-build og test.
- Data og host-specifik state skal holdes adskilt fra OS-imaget.
- Nogle ændringer kræver reboot; soft reboot er en optimering, ikke en garanti.
- ARM64 lokalt og AMD64 på SNO kræver separate platform builds eller et
  multi-architecture image.
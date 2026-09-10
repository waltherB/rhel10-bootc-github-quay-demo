# Talernoter: RHEL Image Mode / bootc-demo (Præsentationsguide)

**Målgruppe:** (Tilpas efter publikum: Linux-drift, OpenShift/K8s, Arkitekter, Ledelse)
**Hovedbudskab:** Operativsystemet skal behandles som et versionsstyret, reproducerbart artefakt, der kan rulles tilbage.

---

## 💡 Slide 1: Introduktion - Paradigmeskiftet
**Titel:** Fra drift til artefakt: Livscyklusstyring af OS
**Nøglepunkt:** Vi skifter fokus fra at *patch'e* en kørende server til at *bygge* og *udrulle* et versionsstyret image.
**Problem (Traditionel drift):**
*   Konfigurationsdrift (Manuelle ændringer over tid).
*   Uensartede miljøer (Dev $\neq$ Test $\neq$ Prod).
*   Svær sporbarhed (Hvad ændrede jeg, og hvorfor?).
*   Kompleks rollback.
**Løsning (Image Mode):**
*   OS defineres som et image (deklarativt).
*   Ændringer sker i kilden (Git-baseret).
*   Distribution sker via et Registry (Quay).
*   Opdateringer er transaktionelle og sporbar.

---

## 💡 Slide 2: Hvorfor er Immutable Images vigtige?
**Titel:** Immutable vs. Mutable: Sikkerhed og Reproducerbarhed
**Koncept:** Et immutable image er en "snapshot" af en perfekt tilstand. Vi ændrer ikke det, der kører; vi udskifter det.
**Fordele:**
1.  **Ensartethed:** Samme image i alle miljøer.
2.  **Sporbarhed:** Hvert kørende system kan spores tilbage til en specifik image-digest og commit.
3.  **Sikkerhed:** Alle ændringer skal gennemgå en kontrolleret pipeline (Build $\rightarrow$ Test $\rightarrow$ Deploy).
4.  **Rollback:** Gendannelse er blot en gen-udrulning af et kendt, velfungerende image.

---

## 💡 Slide 3: Demo-Flow (De 5 Nøglekomponenter)
**Titel:** Fra Kode til Kørsel: Demo-arkitekturen
**1. Kildekode (Repository):**
*   **Hvad:** Sandhedskilden for OS-tilstanden.
*   **Værdi:** Alle ændringer skal her.
**2. Definition (Containerfile):**
*   **Hvad:** Deklarerer det ønskede OS-image (pakker, konfig, services).
*   **Værdi:** Gør OS-tilstanden eksplicit og maskinlæsbar.
**3. Bygning (Build):**
*   **Hvad:** Processen, der tager definitionen og skaber det faktiske, bootbare image.
*   **Værdi:** Standardiserer build-processen.
**4. Distribution (Quay Registry):**
*   **Hvad:** Et centralt, versionsstyret lager for de færdige images.
*   **Værdi:** Sikrer, at kun godkendte, scannede images kan bruges.
**5. Runtime (QCOW2 / VM):**
*   **Hvad:** Konvertering og kørsel af imaget i et virtualiseret miljø.
*   **Værdi:** Forbinder moderne image-principper med eksisterende infrastruktur.

---

## 💡 Slide 4: Demo-Trin-Gennemgang (Hurtig Gennemgang)
**Titel:** Live Demo: Se det i praksis
*   **[Vis Repository]:** Peg på `Containerfile` og forklar, hvordan det definerer tilstanden.
*   **[Vis Build]:** Kør build-processen. Vis, at det skaber et *immutable* artefakt.
*   **[Vis Quay]:** Vis, at artefaktet registreres med et tag og en digest.
*   **[Vis VM/QCOW2]:** Start VM'en fra det nye image. Vis, at den er baseret på det seneste, godkendte artefakt.
*   **[Vis Opdatering/Rollback]:** Simuler en opdatering (ny commit $\rightarrow$ ny build $\rightarrow$ ny image) og derefter en rollback til den forrige, kendte version.

---

## 🎯 Afslutning: Hvad skal publikum tage med?
**Opsummering:**
*   **Mindset:** Tænk i images, ikke i patches.
*   **Værdi:** Reducer operationel risiko, øg sporbarheden og standardiser platformen.
*   **Næste skridt:** Identificer det område i jeres infrastruktur, hvor en image-baseret tilgang vil give størst gevinst (f.eks. patching, applikationslag, eller hele OS-laget).
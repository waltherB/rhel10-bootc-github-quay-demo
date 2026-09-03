#!/usr/bin/env bash
set -euo pipefail

# RHEL Image Mode demo 
# Tunge builds og diskkonvertering sker før sessionen; dette script
# demonstrerer den operationelle livscyklus med færdigpublicerede images.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

: "${QUAY_REPO:=quay.io/waba/bootc-guide}"
: "${IMAGE_GOOD:=${QUAY_REPO}:demo-v1-arm64}"
: "${IMAGE_UPDATE:=${QUAY_REPO}:demo-v2-chatbot-arm64}"
: "${IMAGE_BROKEN:=${QUAY_REPO}:demo-broken-arm64}"
: "${IMAGE_FIXED:=${QUAY_REPO}:demo-v3-fixed-arm64}"
: "${CHATBOT_PORT:=8501}"
: "${RUN_CHATBOT_EXTENSION:=1}"
: "${AI_LAB_RECIPES_DIR:=}"
: "${VM_SSH:=demo@192.168.64.18}"
: "${VM_SSH_KEY:=${HOME}/.ssh/id_ed25519}"
: "${VM_REBOOT_TIMEOUT:=240}"
: "${RUN_SNO_EXTENSION:=0}"
: "${RUN_FLEET_EXTENSION:=1}"
: "${FLEET_APPLY:=0}"
: "${VM_TARGETS:=demo@192.168.64.20 demo@192.168.64.21 demo@192.168.64.22 demo@192.168.64.23}"

BOLD='\033[1m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
RED='\033[1;31m'
RESET='\033[0m'

pause() {
  local message="${1:-Tryk ENTER for at fortsætte...}"
  echo
  echo -e "${BOLD}  ${message}${RESET}"
  read -r
}

step() {
  echo
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  TRIN $1: $2${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo
  pause "Tryk ENTER for at starte trin $1..."
}

say() {
  echo -e "${YELLOW}  ▶  $*${RESET}"
}

note() {
  echo -e "${BLUE}  ℹ  $*${RESET}"
}

ascii() {
  echo -e "${CYAN}$*${RESET}"
}

run() {
  echo -e "${GREEN}  \$ $*${RESET}"
  "$@"
}

remote() {
  ssh -i "${VM_SSH_KEY}" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=8 \
    "${VM_SSH}" "$@"
}

wait_for_vm() {
  local elapsed=0
  note "Venter på at ${VM_SSH} accepterer SSH (op til ${VM_REBOOT_TIMEOUT}s)..."

  while (( elapsed < VM_REBOOT_TIMEOUT )); do
    if ! remote true >/dev/null 2>&1; then
      break
    fi
    ((elapsed += 5))
    sleep 5
  done

  while (( elapsed < VM_REBOOT_TIMEOUT )); do
    if remote true >/dev/null 2>&1; then
      note "VM er tilgængelig igen efter ${elapsed}s."
      return 0
    fi
    ((elapsed += 5))
    sleep 5
    if (( elapsed % 30 == 0 )); then
      note "Venter stadig på VM-genstart (${elapsed}/${VM_REBOOT_TIMEOUT}s)..."
    fi
  done
  echo -e "${RED}  VM blev ikke tilgængelig inden for ${VM_REBOOT_TIMEOUT}s. Genstarten kan stadig være i gang – tjek UTM og prøv SSH-tjekket igen.${RESET}" >&2
  return 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}  Påkrævet kommando ikke fundet: $1${RESET}" >&2
    exit 1
  }
}

show_config() {
  note "GOD     = ${IMAGE_GOOD}"
  note "OPDATER = ${IMAGE_UPDATE}"
  note "BRUDT   = ${IMAGE_BROKEN}"
  note "RETTET  = ${IMAGE_FIXED}"
  note "AI-chatbot = AI Lab Recipes chatbot (localhost:${CHATBOT_PORT})"
  note "UTM VM     = ${VM_SSH}"
  note "Flåde      = ${VM_TARGETS}"
  note "Alle images og ARM64 qcow2-disken skal være forberedt inden demoen."
}

require_command podman
require_command ssh
[[ -f "${VM_SSH_KEY}" ]] || {
  echo -e "${RED}  SSH-nøgle ikke fundet: ${VM_SSH_KEY}${RESET}" >&2
  exit 1
}

check_images() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Preflight: Verificerer images${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  local images=("${IMAGE_GOOD}" "${IMAGE_UPDATE}" "${IMAGE_BROKEN}" "${IMAGE_FIXED}")

  for img in "${images[@]}"; do
    if podman inspect "$img" >/dev/null 2>&1; then
      echo -e "${GREEN}  ✅ $img fundet${RESET}"
    else
      echo -e "${RED}  ❌ $img ikke fundet. Kør: podman pull $img${RESET}"
      exit 1
    fi
  done
  echo ""
}

# ── Intro ─────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   RHEL 10 Image Mode Demo                                    ║"
echo "  ║   pets  →  cattle  →  immutable reality.                     ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${CYAN}"
echo "  Komplet demoforløb:"
echo ""
echo "   ┌──────────────┐     ┌────────────┐     ┌──────────────┐     ┌──────────┐"
echo "   │ Git repo     │     │ Quay.io    │     │ UTM VM       │     │ Flåde    │"
echo "   │ Containerfile│     │ Registry   │     │ ARM64 RHEL   │     │ 4× VMs   │"
echo "   └──────┬───────┘     └─────┬──────┘     └──────┬───────┘     └────┬─────┘"
echo "          │  build+sign       │  bootc switch      │                  │"
echo "          └──────────────────►│◄───────────────────┘   flåde-opdater  │"
echo "                              └──────────────────────────────────────►┘"
echo "                              promote dev→prod"
echo "                              rollback bevaret til enhver tid"
echo -e "${RESET}"
show_config
check_images
pause "Tryk ENTER for at starte demoen..."

# ── TRIN 1 ────────────────────────────────────────────────────────────────────
step 1 "Se imagemodellen"

ascii "  Hvad vi kigger på:"
ascii ""
ascii "   ┌──────────────────────────────────────────────────────────────┐"
ascii "   │  Git-repository  (single source of truth)                    │"
ascii "   │                                                              │"
ascii "   │   Containerfile  ──►  definerer hele OS deklarativt          │"
ascii "   │   files/          ──►  motd, config, certifikater bagt ind   │"
ascii "   │   .github/        ──►  CI bygger, signerer, pusher til Quay  │"
ascii "   │   scripts/        ──►  lokalt build + demo-runner            │"
ascii "   └──────────────────────────────────────────────────────────────┘"
ascii ""
ascii "   VM'en er en udrulet instans af et image."
ascii "   Repo'et er kilden til sandhed – ikke den kørende maskine."
echo ""
say "Repository'et definerer operativsystemet som et bootbart image."
say "Et golden image genbruges af service- og webside-images."
say "VM'en er en udrulet version af et image – ikke kilden til sandhed."
pause "Tryk ENTER for at fortsætte..."

# ── TRIN 2 ────────────────────────────────────────────────────────────────────
step 2 "Test image som container"

ascii "  Samme image, to runtimes:"
ascii ""
ascii "   ┌────────────────────────┐"
ascii "   │  Quay.io               │"
ascii "   │  :demo-v1-arm64        │"
ascii "   └───────────┬────────────┘"
ascii "               │  podman pull"
ascii "               ▼"
ascii "   ┌────────────────────────┐   podman run -p 8080:80"
ascii "   │  Lokalt podman-lager   │ ──────────────────────────► http://localhost:8080"
ascii "   │  (arm64 image)         │"
ascii "   └────────────────────────┘"
ascii ""
ascii "   ✔  Ingen VM nødvendig – hurtig feedback inden vi rører infrastruktur"
echo ""
say "Det samme bootc-image kan testes med almindelige container-værktøjer."
run podman pull "${IMAGE_GOOD}"
run podman rm -f bootc-demo-test 2>/dev/null || true
run podman run --rm -d --name bootc-demo-test -p 8080:80 "${IMAGE_GOOD}"
pause "Åbn http://localhost:8080 i en browser, tryk derefter ENTER..."
run podman stop bootc-demo-test

# ── TRIN 2b ───────────────────────────────────────────────────────────────────
step "2b" "Verificer signering og digest i Quay"

ascii "  Hvert image signeres ved push via nøglefri Cosign (OIDC):"
ascii ""
ascii "   ┌─────────────────┐  cosign sign   ┌──────────────────────────────────┐"
ascii "   │ local-sign-     │ ─────────────► │ Quay.io                          │"
ascii "   │ keyless.sh      │                │  image manifest  +  signatur     │"
ascii "   └─────────────────┘                │  (OCI referrer vedhæftet)        │"
ascii "                                      └──────────────────────────────────┘"
ascii ""
ascii "   local-sign-keyless.sh gør følgende:"
ascii "     1. skopeo inspect  →  oversætter tag til digest"
ascii "     2. cosign sign <repo>@<digest>  (OIDC, ingen langtidsholdbar nøgle)"
ascii "     3. cosign verify   →  bekræfter vedhæftning i Quay"
ascii ""
ascii "   Digest binder sammen:  Quay-tag  ↔  VM-booted image  ↔  git commit SHA"
echo ""
say "Hvert pushét image signeres med nøglefri Cosign – ingen langtidsholdbar nøgle."
say "skopeo inspect viser den digest, der binder Quay, VM og git-commit sammen."
note "Signering udføres af: ./scripts/local-sign-keyless.sh"
run skopeo inspect --raw "docker://${IMAGE_GOOD}" | python3 -m json.tool 2>/dev/null | head -30 || \
  run skopeo inspect --raw "docker://${IMAGE_GOOD}" | head -30
note "Cosign-verificering:"
run cosign verify \
  --certificate-identity-regexp="https://github.com/waltherB/rhel10-bootc-github-quay-demo" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  "${IMAGE_GOOD}" 2>&1 | head -20 || \
cosign verify \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  "${IMAGE_GOOD}" 2>&1 | head -20 || \
  note "Signatur ikke fundet for dette tag – signer med: IMAGE=${IMAGE_GOOD} ./scripts/local-sign-keyless.sh"
pause "Slide: Quay – digest, tag og signering. Tryk ENTER for at fortsætte..."

# ── TRIN 2c ───────────────────────────────────────────────────────────────────
step "2c" "Promover dev → prod (gh workflow dispatch)"

ascii "  Promovering = skopeo copy – IKKE et nyt build:"
ascii ""
ascii "   ┌──────────────────────┐  gh workflow run   ┌───────────────────────┐"
ascii "   │ GitHub Actions       │ ─────────────────► │ promote-prod.yml      │"
ascii "   │ promote-prod.yml     │                    └──────────┬────────────┘"
ascii "   └──────────────────────┘                               │  skopeo copy"
ascii "                                                          ▼"
ascii "   ┌──────────────────────┐                    ┌───────────────────────┐"
ascii "   │ Quay: :demo-v1-arm64 │ ─────────────────► │ Quay: :prod-arm64     │"
ascii "   │ (uændret digest)     │   samme SHA-digest └───────────────────────┘"
ascii "   └──────────────────────┘"
ascii ""
ascii "   ✔  Det der blev testet i CI er præcis det, der kører i prod"
echo ""
say "Promovering bruger skopeo copy – samme digest, bare et nyt :prod-tag."
say "Intet nyt build: det der blev testet i CI er præcis det, der når prod."
note "Udløser: gh workflow run promote-prod.yml --field source_tag=demo-v1-arm64"
run gh workflow run promote-prod.yml \
  --repo waltherB/rhel10-bootc-github-quay-demo \
  --field source_tag=demo-v1-arm64 || \
  note "gh workflow dispatch sprunget over – kør manuelt hvis nødvendigt."
note "Følger fremgang..."
run gh run watch --repo waltherB/rhel10-bootc-github-quay-demo || true
pause "Slide: Promovering flytter referencen – den genbygger ikke indholdet. Tryk ENTER..."

# ── TRIN 3 ────────────────────────────────────────────────────────────────────
step 3 "Inspicer den kørende UTM VM"

ascii "  Det samme image kører nu som et fuldt RHEL OS inde i UTM:"
ascii ""
ascii "   ┌────────────────────────┐   ssh ${VM_SSH}"
ascii "   │  Mac (denne maskine)   │ ──────────────────────────────────────────►"
ascii "   └────────────────────────┘                                            │"
ascii "                                                  ┌──────────────────────┴──────┐"
ascii "                                                  │  UTM VM  (ARM64 RHEL 10)    │"
ascii "                                                  │                             │"
ascii "                                                  │  sudo bootc status          │"
ascii "                                                  │    booted: :demo-v1-arm64   │"
ascii "                                                  │    staged:  (ingen)         │"
ascii "                                                  │                             │"
ascii "                                                  │  curl http://localhost      │"
ascii "                                                  │    → webside fra image      │"
ascii "                                                  └─────────────────────────────┘"
echo ""
say "Nu kører den samme imagemodel som en fuld RHEL VM."
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── TRIN 4 ────────────────────────────────────────────────────────────────────
step 4 "Test AI-chatbot som container"

ascii "  Inden vi bager chatbotten ind i OS-image, tester vi den som en almindelig pod:"
ascii ""
ascii "   test-chatbot-container-m5.sh gør følgende:"
ascii ""
ascii "   1. Kloner ai-lab-recipes  (eller bruger AI_LAB_RECIPES_DIR hvis sat)"
ascii "      └─►  github.com/containers/ai-lab-recipes"
ascii ""
ascii "   2. make quadlet  →  genererer chatbot.yaml (Podman Kube-manifest)"
ascii "      ┌──────────────────────────────────────────────────────┐"
ascii "      │  chatbot.yaml indeholder:                            │"
ascii "      │    - app-container    (Streamlit UI)                 │"
ascii "      │    - model-server     (llama.cpp)                    │"
ascii "      │    - model-image      (GGUF-vægte)                   │"
ascii "      └──────────────────────────────────────────────────────┘"
ascii ""
ascii "   3. podman kube play chatbot.yaml"
ascii "      └─►  pod kører på localhost:${CHATBOT_PORT}"
ascii ""
ascii "   ✔  Samme Quadlet-definition bages ind i bootc-image i Trin 5"
echo ""
say "Vi tester AI Lab Recipes-containeren, inden vi lægger den i OS-image."
say "Podman Desktop kan vise containeren, logs, port og image-metadata her."
pause "Tryk ENTER for at fortsætte..."
if [[ "${RUN_CHATBOT_EXTENSION}" == "1" ]]; then
  run env AI_LAB_RECIPES_DIR="${AI_LAB_RECIPES_DIR}" \
    CHATBOT_PORT="${CHATBOT_PORT}" \
    ./scripts/test-chatbot-container-m5.sh
else
  note "RUN_CHATBOT_EXTENSION=0; springer chatbot-test over."
fi

# ── TRIN 5 ────────────────────────────────────────────────────────────────────
step 5 "Udrul chatbotten via en bootc-opdatering"

ascii "  Workload-levering via imageopdatering – ingen SSH-config, ingen Ansible:"
ascii ""
ascii "   ┌────────────────────────┐  bootc switch        ┌──────────────────────────┐"
ascii "   │ Quay                   │ ◄─────────────────── │  UTM VM                  │"
ascii "   │ :demo-v2-chatbot       │   henter nye lag     │  (henter fra Quay)       │"
ascii "   └────────────────────────┘                      └─────────────┬────────────┘"
ascii "                                                                 │  systemctl reboot"
ascii "                                                                 ▼"
ascii "                                                   ┌─────────────────────────────┐"
ascii "                                                   │  UTM VM  (genstartet)       │"
ascii "                                                   │                             │"
ascii "                                                   │  chatbot.service            │"
ascii "                                                   │  (systemd Quadlet)          │"
ascii "                                                   │  → localhost:${CHATBOT_PORT}│"
ascii "                                                   └─────────────────────────────┘"
ascii ""
ascii "   Chatbot-Quadlet'en er bagt ind i :demo-v2-chatbot – den starter"
ascii "   automatisk ved hvert boot, styret af systemd, ingen manuelle trin."
echo ""
say "Det næste image indeholder chatbotten som et systemd Quadlet."
say "Containeren er nu en del af imagedefinitionen og starter med VM'en."
pause "Tryk ENTER for at fortsætte..."
if [[ "${RUN_CHATBOT_EXTENSION}" != "1" ]]; then
  note "RUN_CHATBOT_EXTENSION=0; springer chatbot-udrulning over."
else
  run remote sudo bootc switch "${IMAGE_UPDATE}"
  run remote sudo bootc status
  pause "Chatbot-image er staged. Tryk ENTER for at genstarte VM'en..."
  run remote sudo systemctl reboot || true
  wait_for_vm
  run remote sudo bootc status
  run remote sudo systemctl daemon-reload
  run remote sudo systemctl --no-pager --full status chatbot.service || true
  run remote sudo systemctl list-unit-files --all | grep -Ei 'chatbot|llamacpp' || true
  note "Chatbotten burde være tilgængelig på VM'ens port ${CHATBOT_PORT}."
fi

# ── TRIN 6 ────────────────────────────────────────────────────────────────────
step 6 "Inspicer den opdaterede VM"

ascii "  Efter genstart kører VM'en det nye image:"
ascii ""
ascii "   ┌────────────────────────────────────────────────────────────────┐"
ascii "   │  UTM VM  (genstartet med :demo-v2-chatbot-arm64)               │"
ascii "   │                                                                │"
ascii "   │  bootc status                                                  │"
ascii "   │    booted:   :demo-v2-chatbot-arm64   ◄── NY                   │"
ascii "   │    rollback: :demo-v1-arm64           ◄── bevaret              │"
ascii "   │                                                                │"
ascii "   │  curl http://localhost  →  webside virker stadig               │"
ascii "   │  chatbot.service        →  kører (Quadlet auto-start)          │"
ascii "   └────────────────────────────────────────────────────────────────┘"
ascii ""
ascii "   Nøglepunkt: den forrige deployment gemmes ALTID som rollback-mål."
ascii "   Intet er gået tabt – bootc holder begge deployments på disk."
echo ""
say "En workload-ændring leveres som et nyt image – ikke som manuelle ændringer på hosten."
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── TRIN 7 ────────────────────────────────────────────────────────────────────
step 7 "Udrul en bevidst ødelagt version"

ascii "  Simulerer en fejlbehæftet release – httpd er bevidst ikke aktiveret:"
ascii ""
ascii "   ┌────────────────────────┐  bootc switch        ┌──────────────────────────┐"
ascii "   │ Quay                   │ ◄─────────────────── │  UTM VM                  │"
ascii "   │ :demo-broken-arm64     │  henter ødelagt image│                          │"
ascii "   └────────────────────────┘                      └─────────────┬────────────┘"
ascii "                                                                  │  systemctl reboot"
ascii "                                                                  ▼"
ascii "                                                   ┌─────────────────────────────┐"
ascii "                                                   │  UTM VM  (genstartet)       │"
ascii "                                                   │                             │"
ascii "                                                   │  httpd.service  FEJLET      │"
ascii "                                                   │  curl http://localhost      │"
ascii "                                                   │    → forbindelse afvist     │"
ascii "                                                   └─────────────────────────────┘"
ascii ""
ascii "   Dette er demoens 'åh nej'-øjeblik – sætter scenen for rollback-historien."
echo ""
say "Denne version indeholder en kendt fejl: HTTP-tjenesten er ikke aktiveret."
say "Fejlen gør rollback synlig og giver publikum en reel gendannelsessti."
run remote sudo bootc switch "${IMAGE_BROKEN}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo systemctl --no-pager --full status httpd || true
run remote curl -fsS http://localhost | lynx -stdin -dump || true
run remote sudo bootc status
pause

# ── TRIN 8 ────────────────────────────────────────────────────────────────────
step 8 "Rul tilbage til den kendte gode deployment"

ascii "  Én kommando, én genstart – tilbage til en kendt god tilstand:"
ascii ""
ascii "   ┌──────────────────────────────────────────────────────────────────┐"
ascii "   │  UTM VM  (kører ødelagt image)                                   │"
ascii "   │                                                                  │"
ascii "   │  sudo bootc rollback --apply                                     │"
ascii "   │    →  aktiverer den forrige deployment-post                      │"
ascii "   │    →  genstarter med :demo-v2-chatbot-arm64                      │"
ascii "   └──────────────────────────────────────────────────────────────────┘"
ascii "                              │  genstart"
ascii "                              ▼"
ascii "   ┌──────────────────────────────────────────────────────────────────┐"
ascii "   │  UTM VM  (rullet tilbage)                                        │"
ascii "   │                                                                  │"
ascii "   │  bootc status                                                    │"
ascii "   │    booted:   :demo-v2-chatbot-arm64   ◄── gendannet              │"
ascii "   │    rollback: :demo-broken-arm64       ◄── (stadig der)           │"
ascii "   │                                                                  │"
ascii "   │  curl http://localhost  →  virker igen                           │"
ascii "   └──────────────────────────────────────────────────────────────────┘"
ascii ""
ascii "   Ingen geninstallation. Ingen Ansible. Ingen SSH-config-kirurgi."
ascii "   bootc bevarer begge deployments – rollback er altid én genstart væk."
echo ""
say "bootc bevarer den forrige deployment som rollback-mål."
run remote sudo bootc rollback --apply || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── TRIN 9 ────────────────────────────────────────────────────────────────────
step 9 "Udrul det rettede image"

ascii "  Rettelsen er en ny imageversion – bygget, testet og promoveret via CI:"
ascii ""
ascii "   ┌──────────────────┐  git commit+push   ┌───────────────────────────────┐"
ascii "   │ Containerfile    │ ─────────────────► │ GitHub Actions                │"
ascii "   │ (httpd-rettelse) │                    │  build → sign → push          │"
ascii "   └──────────────────┘                    │  :demo-v3-fixed-arm64         │"
ascii "                                           └──────────────┬────────────────┘"
ascii "                                                          │  bootc switch"
ascii "                                                          ▼"
ascii "                                           ┌──────────────────────────────────┐"
ascii "                                           │  UTM VM  (genstartet)            │"
ascii "                                           │                                  │"
ascii "                                           │  httpd.service  ✔  kører         │"
ascii "                                           │  curl http://localhost  ✔        │"
ascii "                                           └──────────────────────────────────┘"
ascii ""
ascii "   Samme OS-livscyklusmønster: byg én gang → test → lever som image."
echo ""
say "Rettelsen bygges én gang, testes og leveres som en ny imageversion."
run remote sudo bootc switch "${IMAGE_FIXED}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause

# ── TRIN 10 ───────────────────────────────────────────────────────────────────
if [[ "${RUN_FLEET_EXTENSION}" == "1" ]]; then
  step 10 "Én repo-opdatering, mange VM-udrulninger"

  ascii "  Det samme testede image anvendes på en flåde – demo-fleet-update-m5.sh:"
  ascii ""
  ascii "   ┌──────────────────────────┐"
  ascii "   │ Quay                     │"
  ascii "   │ :demo-v3-fixed-arm64     │"
  ascii "   └────────────┬─────────────┘"
  ascii "                │  for each VM in VM_TARGETS:"
  ascii "                │  ssh <mål> sudo bootc switch <image>"
  ascii "                │"
  ascii "                ├──────────────────►  demo@192.168.64.20  (demo-web-01)"
  ascii "                ├──────────────────►  demo@192.168.64.21  (demo-web-02)"
  ascii "                ├──────────────────►  demo@192.168.64.22  (demo-web-03)"
  ascii "                └──────────────────►  demo@192.168.64.23  (demo-web-04)"
  ascii ""
  ascii "   FLEET_APPLY=${FLEET_APPLY}  →  $([ "${FLEET_APPLY}" == "1" ] && echo "LIVE: bootc switch køres på hver VM" || echo "KUN PLAN: viser kommandoer, ingen ændringer foretages")"
  ascii ""
  ascii "   Efter staging: genstart VM'er i dit ændringsvindue for at anvende."
  ascii "   Alle VM'er får det identiske, signerede, testede image – ingen drift."
  echo ""
  say "Det testede image kan anvendes på en flåde ved hjælp af samme målreference."
  note "Flåde: ${VM_TARGETS}"
  IMAGE_UPDATE="${IMAGE_FIXED}" VM_TARGETS="${VM_TARGETS}" FLEET_APPLY="${FLEET_APPLY}" \
    ./scripts/demo-fleet-update-m5.sh
  pause "Tryk ENTER for at fortsætte..."
fi

# ── TRIN 11 (valgfrit SNO) ────────────────────────────────────────────────────
if [[ "${RUN_SNO_EXTENSION}" == "1" ]]; then
  step 11 "Valgfrit: den samme model på OpenShift Virtualization"

  ascii "  Den lokale demo brugte ARM64 i UTM; SNO kører AMD64-image nativt:"
  ascii ""
  ascii "   ┌──────────────────────┐  skopeo copy     ┌────────────────────────────┐"
  ascii "   │ Quay                 │ ───────────────► │ Quay                       │"
  ascii "   │ :dev-disk-amd64      │  samme digest    │ :prod-disk-amd64           │"
  ascii "   └──────────────────────┘                  └──────────────┬─────────────┘"
  ascii "                                                             │  CDI import"
  ascii "                                                             ▼"
  ascii "   ┌──────────────────────────────────────────────────────────────────────┐"
  ascii "   │  OpenShift Virtualization (SNO x86_64)                               │"
  ascii "   │                                                                      │"
  ascii "   │  ansible-playbook provision-vm.yml                                   │"
  ascii "   │    →  Namespace, PullSecret, DataVolume, VirtualMachine              │"
  ascii "   │                                                                      │"
  ascii "   │  bootc status  (via virtctl ssh)                                     │"
  ascii "   │    booted: :prod-amd64                                               │"
  ascii "   └──────────────────────────────────────────────────────────────────────┘"
  ascii ""
  ascii "   OpenShift styrer VM-platformen."
  ascii "   bootc styrer gæste-OS-livscyklussen – samme mønster som UTM."
  echo ""
  say "Den lokale demo brugte ARM64 i UTM; SNO-udvidelsen bruger et færdigbygget AMD64-image."
  say "OpenShift styrer VM-platformen, mens bootc styrer gæste-OS-livscyklussen."
  note "Vis den forberedte VirtualMachine, dens DataVolume og bootc status over SSH."
  pause
fi

# ── Oprydning ─────────────────────────────────────────────────────────────────
say "Rydder op efter demo-ressourcer..."
run podman rm -f bootc-demo-test 2>/dev/null || true

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   Demo afsluttet                                             ║"
echo "  ║                                                              ║"
echo "  ║   byg → signer → promover → udrul → chatbot                  ║"
echo "  ║   → fejl → rollback → ret → flåde                            ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

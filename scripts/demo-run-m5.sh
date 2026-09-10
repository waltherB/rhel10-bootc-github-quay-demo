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
: "${RUN_SNO_EXTENSION:=1}"
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

# ── Trin-spring-logik for demo-run-m5.sh ─────────────────────────────────────
STEP_ORDER=(1 2 2b 2c 3 4 5 6 7 8 9 10 11)
_STEP_REACHED=0

step_index() {
  local target="$1"
  local idx=0
  local step
  for step in "${STEP_ORDER[@]}"; do
    if [[ "${step}" == "${target}" ]]; then
      echo "${idx}"
      return 0
    fi
    ((idx++))
  done
  echo "-1"
}

should_run() {
  local id="$1"
  local start_step="${START_STEP:-}"
  local current_index target_index

  if [[ -z "${start_step}" || "${_STEP_REACHED}" -eq 1 ]]; then
    _STEP_REACHED=1
    return 0
  fi

  current_index="$(step_index "${id}")"
  target_index="$(step_index "${start_step}")"

  if [[ "${current_index}" == "-1" ]]; then
    echo -e "${RED}  ⚠  Ukendt trin-ID ${id}; kører det alligevel${RESET}"
    _STEP_REACHED=1
    return 0
  fi

  if [[ "${target_index}" == "-1" ]]; then
    echo -e "${RED}  ⚠  Ukendt START_STEP=${start_step}; kører fra begyndelsen${RESET}"
    _STEP_REACHED=1
    return 0
  fi

  if [[ "${current_index}" -ge "${target_index}" ]]; then
    _STEP_REACHED=1
    return 0
  fi

  echo -e "${BLUE}  ⏭  Springer trin ${id} over (START_STEP=${START_STEP})${RESET}"
  return 1
}

# ── Intro ─────────────────────────────────────────────────────────────────────
if [[ -n "${START_STEP:-}" ]]; then
  echo -e "${YELLOW}  ⏩  START_STEP=${START_STEP} — springer trin over før '${START_STEP}'${RESET}"
  echo ""
fi

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
echo "   ┌──────────────┐     ┌────────────┐     ┌──────────────┐      ┌──────────┐"
echo "   │ Git repo     │     │ Quay.io    │     │ UTM VM       │      │ Flåde    │"
echo "   │ Containerfile│     │ Registry   │     │ ARM64 RHEL   │      │ 4× VMs   │"
echo "   └──────┬───────┘     └─────┬──────┘     └──────┬───────┘      └────┬─────┘"
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
if should_run 1; then
step 1 "Se imagemodellen"
ascii "  REPOSITORYET ER SANDHEDSKILDEN"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────────────┐"
ascii "  │ Git repository       │"
ascii "  │                      │"
ascii "  │ Containerfile        │"
ascii "  │ files/               │"
ascii "  │ .github/workflows/   │"
ascii "  │ scripts/             │"
ascii "  └──────────┬───────────┘"
ascii "             │ build"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ Bootc image          │"
ascii "  │ versioneret OS       │"
ascii "  └──────────┬───────────┘"
ascii "             │ deploy"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ VM                   │"
ascii "  │ instans af imaget    │"
ascii "  └──────────────────────┘"
ascii ""
ascii "  Kilden er Git. VM'en er resultatet."
pause "Tryk ENTER "
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
fi

# ── TRIN 2 ────────────────────────────────────────────────────────────────────
if should_run 2; then
step 2 "Test image som container"

ascii "  SAMME IMAGE, TO RUNTIMES"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "                         ┌──────────────────────┐"
ascii "                         │ Quay                 │"
ascii "                         │ :demo-v1-arm64       │"
ascii "                         └──────────┬───────────┘"
ascii "                                    │ podman pull"
ascii "                    ┌───────────────┴───────────────┐"
ascii "                    │                               │"
ascii "                    ▼                               ▼"
ascii "          ┌──────────────────┐            ┌──────────────────┐"
ascii "          │ Container        │            │ UTM VM           │"
ascii "          │ hurtig test      │            │ fuldt RHEL OS    │"
ascii "          └──────────────────┘            └──────────────────┘"
ascii ""
ascii "  Først test som container. Derefter deploy som OS."

ascii ""
ascii "   ✔  Ingen VM nødvendig – hurtig feedback inden vi rører infrastruktur"
echo ""
say "Det samme bootc-image kan testes med almindelige container-værktøjer."
pause "Tryk ENTER for at fortsætte..." 
run podman pull "${IMAGE_GOOD}"
run podman rm -f bootc-demo-test 2>/dev/null || true
run podman run --rm -d --name bootc-demo-test -p 8080:80 "${IMAGE_GOOD}"
pause "Åbner http://localhost:8080 i en browser, tryk derefter ENTER..."
run podman stop bootc-demo-test
fi

# ── TRIN 2b ───────────────────────────────────────────────────────────────────
if should_run 2b; then
step "2b" "Verificer signering og digest i Quay"

ascii "  TRUSTED IMAGE"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "   ┌─────────────────┐  cosign sign   ┌──────────────────────────────────┐"
ascii "   │ local-sign-     │ ─────────────► │ Quay.io                          │"
ascii "   │ keyless.sh      │                │  image manifest  +  signatur     │"
ascii "   └─────────────────┘                │  (OCI referrer vedhæftet)        │"
ascii "                                      └──────────────────────────────────┘"
ascii ""
ascii "   local-sign-keyless.sh kan anvende:"
ascii "     1. keyless OIDC Cosign-signering (standard)"
ascii "     2. lokal COSIGN_KEY + COSIGN_PUB til COSIGN verify --key"
ascii "     3. lokal COSIGN_KEY + COSIGN_CERT til X.509-signering og cert-baseret verificering"
ascii ""
ascii "   Digest binder sammen:  Quay-tag  ↔  VM-booted image  ↔  git commit SHA"
echo ""
say "Hvert pushét image kan signereres med nøglefri OIDC eller med en lokal cosign nøgle/sertifikat."
say "skopeo inspect viser den digest, der binder Quay, VM og git-commit sammen."
note "Signering udføres af: ./scripts/local-sign-keyless.sh"
pause "Tryk ENTER for at fortsætte..." 
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
  note "Signatur ikke fundet for dette tag – signer med: IMAGE=${IMAGE_GOOD} ./scripts/local-sign-keyless.sh eller med COSIGN_KEY/COSIGN_PUB/COSIGN_CERT"
pause "Quay – digest, tag og signering. Tryk ENTER for at fortsætte..."
fi

# ── TRIN 2c ───────────────────────────────────────────────────────────────────
if should_run 2c; then
step "2c" "Promover dev → prod (gh workflow dispatch)"

ascii "  PROMOVERING ER IKKE ET NYT BUILD"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────────────┐"
ascii "  │ Quay                 │"
ascii "  │ :demo-v1-arm64       │"
ascii "  │ digest: sha256:....  │"
ascii "  └──────────┬───────────┘"
ascii "             │ skopeo copy"
ascii "             │ samme digest"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ Quay                 │"
ascii "  │ :prod-arm64          │"
ascii "  │ digest: sha256:....  │"
ascii "  └──────────────────────┘"
ascii ""
ascii "  dev → prod ændrer tagget, ikke indholdet."
ascii "   ✔  Det der blev testet i CI er præcis det, der kører i prod"
echo ""
say "Promovering bruger skopeo copy – samme digest, bare et nyt :prod-tag."
say "Intet nyt build: det der blev testet i CI er præcis det, der når prod."
note "Udløser: gh workflow run promote-prod.yml --field source_tag=demo-v1-arm64"
pause "Tryk ENTER for at fortsætte..." 
run gh workflow run promote-prod.yml \
  --repo waltherB/rhel10-bootc-github-quay-demo \
  --field source_tag=demo-v1-arm64 || \
  note "gh workflow dispatch sprunget over – kør manuelt hvis nødvendigt."
note "Følger fremgang..."
run gh run watch --repo waltherB/rhel10-bootc-github-quay-demo || true
pause "Promovering flytter referencen – den genbygger ikke indholdet. Tryk ENTER..."
fi

# ── TRIN 3 ────────────────────────────────────────────────────────────────────
if should_run 3; then
step 3 "Inspicer den kørende UTM VM"

ascii "  IMAGE BLIVER TIL ET KØRENDE OS"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────┐       SSH        ┌──────────────────────┐"
ascii "  │ Mac          │ ───────────────► │ UTM VM               │"
ascii "  │ demo-runner  │                  │ ARM64 RHEL 10        │"
ascii "  └──────────────┘                  │                      │"
ascii "                                    │ bootc status         │"
ascii "                                    │ curl localhost       │"
ascii "                                    └──────────────────────┘"
ascii ""
ascii "  Quay leverer imaget."
ascii "  bootc administrerer OS-livscyklussen."
ascii "  UTM leverer VM-platformen."  
echo ""
say "Nu kører den samme imagemodel som en fuld RHEL VM."
pause "Tryk ENTER for at fortsætte..." 
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause
fi

# ── TRIN 4 ────────────────────────────────────────────────────────────────────
if should_run 4; then
step 4 "Test AI-chatbot som container"
ascii "  Det er så moderne med AI så lige et eksempel AI Lab Recipes chatbot (llama.cpp + Streamlit UI)"
ascii "  Vi tester den som en container, inden vi bager den ind i OS-image."
ascii " Det hedder quadlets og det er containers der håndteres af systemd's lifecycle management inde i image"
ascii ""
ascii "   test-chatbot-container-m5.sh gør følgende:"
ascii ""
ascii "   1. Kloner ai-lab-recipes"
ascii "      └─►  github.com/containers/ai-lab-recipes"
ascii ""
ascii "   2. make quadlet  →  genererer chatbot.yaml (Podman Kube-manifest)"
ascii "      ┌──────────────────────────────────────────────────────┐"
ascii "      │  chatbot.yaml indeholder:                            │"
ascii "      │    - app-container    (Streamlit UI)                 │"
ascii "      │    - model-server     (llama.cpp)                    │"
ascii "      │    - model-image      (GGUF-model)                   │"
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
fi

# ── TRIN 5 ────────────────────────────────────────────────────────────────────
if should_run 5; then
step 5 "Udrul chatbotten via en bootc-opdatering"
ascii ""

ascii "  WORKLOAD LEVERES SOM IMAGE-OPDATERING"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────────────┐"
ascii "  │ Quay                 │"
ascii "  │ :demo-v2-chatbot     │"
ascii "  └──────────┬───────────┘"
ascii "             │ bootc switch"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ UTM VM               │"
ascii "  │ image staged         │"
ascii "  └──────────┬───────────┘"
ascii "             │ systemctl reboot"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ VM kører ny version  │"
ascii "  │ chatbot.service      │"
ascii "  │ automatisk startet   │"
ascii "  └──────────────────────┘"
ascii ""
ascii "  Ingen manuel SSH-konfiguration."
ascii "  Ingen separat container-deployment."
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
fi

# ── TRIN 6 ────────────────────────────────────────────────────────────────────
if should_run 6; then
step 6 "Inspicer den opdaterede VM"

ascii "  Efter genstart kører VM'en det nye image:"
ascii "  NY VERSION, GAMMEL VERSION BEVARET"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────────────────────┐"
ascii "  │ UTM VM                       │"
ascii "  │                              │"
ascii "  │ booted:  :demo-v2-chatbot   │"
ascii "  │ rollback: :demo-v1-arm64    │"
ascii "  └──────────────────────────────┘"
ascii "                    │"
ascii "                    ▼"
ascii "       ┌──────────────────────────┐"
ascii "       │ bootc bevarer den         │"
ascii "       │ tidligere deployment      │"
ascii "       └──────────────────────────┘"
ascii ""
ascii "   NB: den forrige deployment gemmes ALTID som rollback-mål."
ascii "   Intet er gået tabt – bootc holder begge deployments på disk."
echo ""
say "En workload-ændring leveres som et nyt image – ikke som manuelle ændringer på hosten."
pause "Tryk ENTER for at fortsætte..." 
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause
fi

# ── TRIN 7 ────────────────────────────────────────────────────────────────────
if should_run 7; then
step 7 "Udrul en bevidst ødelagt version"

ascii "  FEJLBEHÆFTET RELEASE"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────────────┐"
ascii "  │ Quay                 │"
ascii "  │ :demo-broken-arm64   │"
ascii "  │ httpd ikke aktiveret │"
ascii "  └──────────┬───────────┘"
ascii "             │ bootc switch"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ UTM VM               │"
ascii "  │ systemctl reboot     │"
ascii "  └──────────┬───────────┘"
ascii "             │ test"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ FEJL                 │"
ascii "  │ httpd.service failed │"
ascii "  │ curl: afvist         │"
ascii "  └──────────────────────┘"
ascii ""
ascii "   'Åh nej'-øjeblik – En rollback mulighed."
echo ""
say "Denne version indeholder en kendt fejl: HTTP-tjenesten er ikke aktiveret."
say "Fejlen gør rollback synlig og giver en reel gendannelsessti."
pause "Tryk ENTER for at fortsætte..." 
run remote sudo bootc switch "${IMAGE_BROKEN}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo systemctl --no-pager --full status httpd || true
run remote curl -fsS http://localhost | lynx -stdin -dump || true
run remote sudo bootc status
pause
fi

# ── TRIN 8 ────────────────────────────────────────────────────────────────────
if should_run 8; then
step 8 "Rul tilbage til den kendte gode deployment"

ascii "  Én kommando, én genstart – tilbage til en kendt god tilstand:"
ascii "  ROLLBACK TIL KENDT GOD TILSTAND"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────────────┐"
ascii "  │ Broken deployment    │"
ascii "  │ :demo-broken-arm64   │"
ascii "  └──────────┬───────────┘"
ascii "             │ bootc rollback --apply"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ Genstart             │"
ascii "  └──────────┬───────────┘"
ascii "             ▼"
ascii "  ┌──────────────────────┐"
ascii "  │ Kendt god deployment │"
ascii "  │ :demo-v2-chatbot     │"
ascii "  │ httpd virker igen    │"
ascii "  └──────────────────────┘"
ascii ""
ascii "  Ingen geninstallation."
ascii "  Ingen ny build."
ascii "  Én rollback-kommando."
ascii "  Ingen geninstallation. Ingen Ansible. Ingen SSH-config-kirurgi."
ascii "  bootc bevarer begge deployments – rollback er altid én genstart væk."
echo ""
pause "Tryk ENTER for at fortsætte..." 
run remote sudo bootc rollback --apply || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause
fi

# ── TRIN 9 ────────────────────────────────────────────────────────────────────
if should_run 9; then
step 9 "Udrul det rettede image"

ascii "  FIXET LEVERES SOM EN NY VERSION"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────┐     ┌──────────────────┐     ┌──────────────┐"
ascii "  │ Containerfile│ ───►│ GitHub Actions   │ ───►│ Quay         │"
ascii "  │ rettelse     │     │ build            │     │ :demo-v3     │"
ascii "  └──────────────┘     │ sign             │     └──────┬───────┘"
ascii "                       │ push             │            │"
ascii "                       └──────────────────┘            │ bootc switch"
ascii "                                                       ▼"
ascii "                                             ┌──────────────────┐"
ascii "                                             │ UTM VM           │"
ascii "                                             │ httpd OK         │"
ascii "                                             └──────────────────┘"
ascii ""
ascii "  Ret kildekoden, byg et nyt image, og lever den nye version."
ascii ""
ascii "  Samme OS-livscyklusmønster: byg én gang → test → lever som image."
echo ""
pause "Tryk ENTER for at fortsætte..." 
run remote sudo bootc switch "${IMAGE_FIXED}"
run remote sudo systemctl reboot || true
wait_for_vm
run remote sudo bootc status
run remote curl -fsS http://localhost | lynx -stdin -dump
pause
fi

# ── TRIN 10 ───────────────────────────────────────────────────────────────────
if should_run 10 && [[ "${RUN_FLEET_EXTENSION}" == "1" ]]; then
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
  pause "Tryk ENTER for at fortsætte..." 
  IMAGE_UPDATE="${IMAGE_FIXED}" VM_TARGETS="${VM_TARGETS}" FLEET_APPLY="${FLEET_APPLY}" \
    ./scripts/demo-fleet-update-m5.sh
  pause "Tryk ENTER for at fortsætte..."
fi

# ── TRIN 11 Deploy til OopenShift Virtulization ────────────────────────────────────────────────────
if should_run 11 && [[ "${RUN_SNO_EXTENSION}" == "1" ]]; then
  step 11 "Den samme model på OpenShift Virtualization"

  ascii "  Den lokale demo brugte ARM64 i UTM; SNO kører AMD64-image nativt:"
  ascii ""
  ascii "   ┌──────────────────────┐  skopeo copy     ┌────────────────────────────┐"
  ascii "   │ Quay                 │ ───────────────► │ Quay                       │"
  ascii "   │ :dev-disk-amd64      │  samme digest    │ :prod-disk-amd64           │"
  ascii "   └──────────────────────┘                  └──────────────┬─────────────┘"
  ascii "                                                            │  CDI import"
  ascii "                                                            ▼"
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
  note "Kører den automatiske OpenShift Virtualization deployment-orchestrator."
  note "Vis VirtualMachine, dens DataVolume og bootc status over SSH."
  run "./scripts/deploy-to-openshift-virt.sh" || true
  pause
fi

# Afslutning
ascii "  RHEL 10 IMAGE MODE LIFECYCLE"
ascii "  ─────────────────────────────────────────────────────────"
ascii ""
ascii "  ┌──────────────┐"
ascii "  │ Git          │"
ascii "  │ definition   │"
ascii "  └──────┬───────┘"
ascii "         │ build"
ascii "         ▼"
ascii "  ┌──────────────┐"
ascii "  │ Image        │"
ascii "  │ build + sign │"
ascii "  └──────┬───────┘"
ascii "         │ push"
ascii "         ▼"
ascii "  ┌──────────────┐"
ascii "  │ Quay         │"
ascii "  │ registry     │"
ascii "  └──────┬───────┘"
ascii "         │ promote"
ascii "         ▼"
ascii "  ┌──────────────┐"
ascii "  │ VM / fleet   │"
ascii "  │ bootc switch │"
ascii "  └──────┬───────┘"
ascii "         │"
ascii "         ├── update"
ascii "         ├── rollback"
ascii "         └── fleet rollout"
ascii ""
ascii "  byg → signer → promover → udrul → rollback"



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

# ── Oprydning ─────────────────────────────────────────────────────────────────
say "Link til OpenShift Virtualization SNO-udvidelsen:"
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   Script der starter ansible playbooks                       ║"
echo "  ║                                                              ║"
echo "  ║   ./scripts/provision-vm.sh                                  ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
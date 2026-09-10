#!/usr/bin/env bash
# Re-exec under Bash when the script is invoked explicitly with sh.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# ============================================================
#  RHEL 10 bootc Demo – præsentations-runner
#  Brug: ./scripts/demo-run.sh [START_STEP]
#
#  Hvert trin printer en titel + fortælling, og venter derefter på ENTER.
#  Kommandoer vises i en distinkt farve inden de køres.
#  Tryk Ctrl-C til enhver tid for at afbryde.
#
#  For at genstarte fra et bestemt trin, sæt START_STEP:
#    START_STEP=9a ./scripts/demo-run.sh
#  Gyldige trin-ID'er: 1 2 2b 3 4 5 6 7a 7b 7c 7d 8 9a 9b
#
#  ARKITEKTUR-OPDELING:
#    ARM64 bootc image + qcow2-disk bygges LOKALT (nativt på Mac),
#    bruges kun til den lokale UTM VM-demo (trin 2, 2b, 7b-8).
#    AMD64 bootc image + qcow2-disk bygges EKSTERNT af GitHub
#    Actions (nativt på ubuntu-latest runners), bruges kun til
#    OpenShift Virtualization på x86_64 SNO-klyngen (trin 9a).
#    De to krydser aldrig hinanden – se scripts/demo-env.sh.example.
#
#  For at forudindstille variabler, opret scripts/demo-env.sh:
#    export IMAGE_ARM="quay.io/waba/bootc-guide:dev-arm64"
#    export IMAGE_AMD="quay.io/waba/bootc-guide:dev-amd64"
#    export DISK_IMAGE_ARM="quay.io/waba/bootc-guide:dev-disk-arm64"
#    export DISK_IMAGE_AMD="quay.io/waba/bootc-guide:dev-disk-amd64"
#    export VM_SSH="demo@192.168.65.10"
#    export SNO_API="https://api.waba-sno.adc.lan"
#    export SNO_TOKEN="$(oc whoami -t)"
#    export DISK_IMAGE_AMD="quay.io/waba/bootc-guide:prod-disk-amd64"  # spring rebuild over
#  Se scripts/demo-env.sh.example for det fulde variabelsæt.
#  Den hentes automatisk hvis den eksisterer.
# ============================================================
set -euo pipefail

# ── Hent env-fil hvis den findes ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/demo-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/demo-env.sh"
fi

# ── Farver ───────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[1;36m'      # trin-headers
YELLOW='\033[1;33m'    # fortælling / talepunkter
GREEN='\033[1;32m'     # kommandoer der er ved at køre
BLUE='\033[1;34m'      # informationsnoter
RED='\033[1;31m'       # advarsler / manuelle handlinger påkrævet
RESET='\033[0m'

# ── Konfiguration – standarder bruges kun hvis env-variabel mangler ──
: "${IMAGE_ARM:=quay.io/waba/bootc-guide:dev-arm64}"
: "${IMAGE_AMD:=quay.io/waba/bootc-guide:dev-amd64}"
: "${VM_SUDO_PASSWORD:=redhat}"
: "${VM_USER:=demo}"

# ── Hjælper til at maskere følsomme data ─────────────────────
mask_value() {
  local val="$1"
  local len=${#val}
  if (( len <= 4 )); then
    echo "****"
  else
    echo "${val:0:3}****${val: -3}"
  fi
}

# ── Spørg efter evt. manglende variabel, bekræft forudindstillede værdier ─
prompt_var() {
  local var="$1"
  local prompt="$2"
  local default="${3:-}"
  local current
  local display_value

  current="$(printenv "$var" 2>/dev/null || true)"

  if [[ -n "${current}" ]]; then
    case "$var" in
      *TOKEN*|*PASSWORD*|*SECRET*|*KEY*|*ORG*|*B64*)
        display_value="$(mask_value "$current")"
        ;;
      *)
        display_value="$current"
        ;;
    esac

    echo -e "${BOLD}  ${prompt}${RESET}"
    echo -e "${BLUE}  Nuværende: ${display_value}${RESET}"
    echo -e "${BOLD}  Tryk ENTER for at bekræfte, eller skriv en ny værdi: ${RESET}"
    read -r input
    if [[ -n "${input}" ]]; then
      export "$var"="${input}"
    else
      export "$var"="${current}"
    fi

  elif [[ -n "${default}" ]]; then
    echo -e "${BOLD}  ${prompt}${RESET}"
    echo -e "${BLUE}  Standard: ${default}${RESET}"
    echo -e "${BOLD}  Tryk ENTER for at acceptere, eller skriv en ny værdi: ${RESET}"
    read -r input
    export "$var"="${input:-${default}}"

  else
    echo -e "${BOLD}  ${prompt}${RESET}"
    read -r input
    export "$var"="${input}"
  fi
}

# ── Trin-spring-logik ────────────────────────────────────────
STEP_ORDER=(1 2 2b 3 4 5 6 7a 7b 7c 7d 8 9a 9b)
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

# ── Hjælpefunktioner ─────────────────────────────────────────

step() {
  local number="$1"
  local title="$2"
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  TRIN ${number}: ${title}${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

narrate() {
  echo -e "${YELLOW}  ▶  $*${RESET}"
}

ascii() {
  echo -e "${CYAN}$*${RESET}"
}

run() {
  local cmd="$*"
  local masked_cmd
  masked_cmd=$(echo "$cmd" | sed -E \
    -e 's/(--token=|--password=|--secret=|--key=)[^ ]+/\1********/g' \
    -e 's/(ssh_pub_key=")[^"]+/\1********/g')

  echo ""
  echo -e "${GREEN}  \$ $masked_cmd${RESET}"
  echo ""
  eval "$@"
}

pause() {
  local msg="${1:-Tryk ENTER for at fortsætte...}"
  echo ""
  echo -e "${BOLD}  ↩  ${msg}${RESET}"
  read -r
}

manual() {
  echo ""
  echo -e "${RED}  ★  MANUELT: $*${RESET}"
  echo ""
}

note() {
  echo -e "${BLUE}  ℹ  $*${RESET}"
}

validate_image_for_openshift() {
  local image="$1"
  local authfile=""

  if [[ -n "${QUAY_DOCKER_CONFIG_B64:-}" ]]; then
    authfile="$(mktemp)"
    echo "${QUAY_DOCKER_CONFIG_B64}" | base64 --decode > "${authfile}"
  fi

  echo ""
  echo -e "${BLUE}  Validerer OpenShift VM-image: ${image}${RESET}"
  if ! command -v skopeo &>/dev/null; then
    echo -e "${RED}  FEJL: skopeo er påkrævet for at validere image.${RESET}"
    [[ -n "${authfile}" ]] && rm -f "${authfile}"
    exit 1
  fi

  if [[ -n "${authfile}" ]]; then
    skopeo inspect --authfile "${authfile}" "docker://${image}" >/dev/null 2>&1
  else
    skopeo inspect "docker://${image}" >/dev/null 2>&1
  fi
  local rc=$?

  [[ -n "${authfile}" ]] && rm -f "${authfile}"

  if [[ ${rc} -ne 0 ]]; then
    echo -e "${RED}  FEJL: Image ${image} er ikke tilgængeligt eller gyldigt til provisionering.${RESET}"
    echo -e "${RED}  Tjek Quay-auth og imagenavn, eller brug en anden IMAGE-værdi.${RESET}"
    exit 1
  fi

  echo -e "${BLUE}  Image ${image} er tilgængeligt til provisionering.${RESET}"
}

# ── Demo starter her ─────────────────────────────────────────

clear
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   RHEL 10 Image Mode Demo                                    ║"
echo "  ║   GitHub Actions · Quay · OpenShift Virt                     ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${BOLD}  Tjekker påkrævede variabler...${RESET}"
echo ""

if [[ -n "${START_STEP:-}" ]]; then
  echo -e "${YELLOW}  ⏩  START_STEP=${START_STEP} — springer trin over før '${START_STEP}'${RESET}"
  echo ""
fi

prompt_var IMAGE_ARM   "  Lokalt ARM64 bootc image (Mac / UTM VM): " "quay.io/waba/bootc-guide:dev-arm64"
prompt_var IMAGE_AMD   "  Eksternt AMD64 bootc image (GitHub CI / OpenShift): " "quay.io/waba/bootc-guide:dev-amd64"
prompt_var VM_SSH      "  UTM VM SSH-mål (f.eks. demo@192.168.65.10) – tjek 'arp -a': "
prompt_var VM_SSH_KEY  "  SSH privat nøgle til VM-adgang: " "${HOME}/.ssh/id_ed25519"
prompt_var VM_USER     "  SSH-brugernavn til VM'en: " "${VM_USER:-demo}"
prompt_var SNO_API     "  SNO API-URL (f.eks. https://api.din-klynge.example.com): "

if [[ -z "$(printenv SNO_TOKEN 2>/dev/null || true)" ]]; then
  if command -v oc &>/dev/null; then
    AUTO_TOKEN="$(oc whoami -t 2>/dev/null || true)"
    if [[ -n "${AUTO_TOKEN}" ]]; then
      echo -e "${BLUE}  SNO_TOKEN: auto-hentet via 'oc whoami -t'${RESET}"
      export SNO_TOKEN="${AUTO_TOKEN}"
    fi
  fi
fi
prompt_var SNO_TOKEN   "  SNO login-token (tryk ENTER for at bruge nuværende oc-session): "

if [[ -z "${QUAY_DOCKER_CONFIG_B64:-}" ]]; then
  AUTH_FILE="${HOME}/.config/containers/auth.json"
  if [[ ! -f "${AUTH_FILE}" ]]; then
    AUTH_FILE="${HOME}/.docker/config.json"
  fi
  if [[ ! -f "${AUTH_FILE}" ]]; then
    echo -e "${RED}  FEJL: Ingen container auth-fil fundet. Kør: podman login quay.io${RESET}"
    exit 1
  fi
  echo -e "${BOLD}  QUAY_DOCKER_CONFIG_B64 ikke sat – genererer fra ${AUTH_FILE}...${RESET}"
  export QUAY_DOCKER_CONFIG_B64
  QUAY_DOCKER_CONFIG_B64="$(base64 < "${AUTH_FILE}")"
fi

echo ""
note "IMAGE_ARM      = ${IMAGE_ARM}   (lokalt, UTM VM)"
note "IMAGE_AMD      = ${IMAGE_AMD}   (GitHub CI, OpenShift Virt)"
note "VM SSH         = ${VM_SSH}"
note "VM BRUGER      = ${VM_USER}"
note "VM SSH-NØGLE   = $(mask_value "$VM_SSH_KEY")"
note "SNO API        = ${SNO_API}"
note "SNO TOKEN      = ${SNO_TOKEN:0:8}…  (afkortet)"
note "DISK_IMAGE_AMD = ${DISK_IMAGE_AMD:-"(auto: ${IMAGE_AMD%:*}:${IMAGE_AMD##*:}-disk)"}"
echo ""
if [[ ! -f "${VM_SSH_KEY}" ]]; then
  echo -e "${RED}  FEJL: SSH-nøgle ${VM_SSH_KEY} ikke fundet. Opret eller angiv en gyldig privat nøgle.${RESET}"
  exit 1
fi
SSH_OPTIONS="-i '${VM_SSH_KEY}' -o BatchMode=yes -o StrictHostKeyChecking=no"
pause "Tryk ENTER for at starte demoen..."

# ────────────────────────────────────────────────────────────
step "1" "Vis repository-strukturen"
# ────────────────────────────────────────────────────────────
if should_run "1"; then
  ascii "  Ét git-repo driver hele OS-livscyklussen:"
  ascii ""
  ascii "   ┌──────────────────────────────────────────────────────────────┐"
  ascii "   │  Git-repository  (eneste kilde til sandhed)                  │"
  ascii "   │                                                              │"
  ascii "   │   Containerfile  ──►  definerer hele OS deklarativt          │"
  ascii "   │   files/          ──►  motd, config, certifikater bagt ind   │"
  ascii "   │   .github/        ──►  CI bygger, signerer, pusher til Quay  │"
  ascii "   │   ansible/        ──►  provisionerer VM'er på OpenShift      │"
  ascii "   └──────────────────────────────────────────────────────────────┘"
  ascii ""
  ascii "   GitHub Actions bygger, tester, signerer og pusher til Quay."
  ascii "   Ansible provisionerer VM'er på OpenShift Virtualization."
  echo ""
  narrate "Ét git-repo driver hele OS-livscyklussen"
  narrate "Containerfile definerer OS-image deklarativt"
  narrate "GitHub Actions bygger, tester, signerer og pusher til Quay"
  narrate "Ansible provisionerer VM'er på OpenShift Virtualization"
  echo ""
  pause
  narrate "Containerfile"
  run tree -C --gitignore
  echo ""
  run less Containerfile
  pause
fi

# ────────────────────────────────────────────────────────────
step "2" "Lokalt build på Mac M4"
# ────────────────────────────────────────────────────────────
if should_run "2"; then
  ascii "  Nativt ARM64-build direkte på Mac – ingen emulering:"
  ascii ""
  ascii "   ┌──────────────────┐   podman build (arm64)   ┌──────────────────────┐"
  ascii "   │  Containerfile   │ ──────────────────────── │ Lokalt Container OS  │"
  ascii "   └──────────────────┘                          │ (:dev-arm64)         │"
  ascii "                                                 └──────────────────────┘"
  ascii ""
  ascii "   TARGET_PLATFORM_LOCAL = linux/arm64"
  ascii "   Ingen kryds-kompilering, ingen emulering – rent nativt."
  echo ""
  narrate "Byg bootc-image lokalt til arm64 (nativt på M4)"
  narrate "TARGET_PLATFORM_LOCAL er linux/arm64 – ingen kryds-kompilering, ingen emulering"
  echo ""
  note "IMAGE_ARM=${IMAGE_ARM}  TARGET_PLATFORM_LOCAL=${TARGET_PLATFORM_LOCAL:-linux/arm64}"
  pause "Tryk ENTER for at starte lokalt build..."
  run "IMAGE_ARM=${IMAGE_ARM} TARGET_PLATFORM_LOCAL=${TARGET_PLATFORM_LOCAL:-linux/arm64} ./scripts/local-build.sh"
  pause
fi

# ────────────────────────────────────────────────────────────
step "2b" "Byg ARM64 qcow2-disk lokalt (til UTM VM)"
# ────────────────────────────────────────────────────────────
if should_run "2b"; then
  ascii "  bootc-image-builder kører nativt arm64-på-arm64 – ingen emulering:"
  ascii ""
  ascii "   ┌──────────────────────┐  bootc-image-builder   ┌──────────────────┐"
  ascii "   │ Lokalt Container OS  │ ─────────────────────► │ disk.qcow2       │"
  ascii "   │ (:dev-arm64)         │      (arm64)           │ (til UTM VM)     │"
  ascii "   └──────────────────────┘                        └──────────────────┘"
  ascii "                                                           │"
  ascii "                                                           │  podman build + push"
  ascii "                                                           ▼"
  ascii "                                                   ┌──────────────────┐"
  ascii "                                                   │ Quay             │"
  ascii "                                                   │ :dev-disk-arm64  │"
  ascii "                                                   └──────────────────┘"
  ascii ""
  ascii "   Denne qcow2 bruges KUN til den lokale UTM VM – aldrig OpenShift."
  echo ""
  narrate "bootc-image-builder kører nativt arm64-på-arm64 her – ingen emulering"
  narrate "Denne qcow2 bruges kun til at (gen)provisionere den lokale UTM VM"
  narrate "OpenShift får altid amd64-disk fra GitHub Actions"
  note "IMAGE_ARM=${IMAGE_ARM}  DISK_IMAGE_ARM=${DISK_IMAGE_ARM:-"${IMAGE_ARM%:*}:dev-disk-arm64"}"
  pause "Tryk ENTER for at bygge og pushe ARM64 qcow2..."
  run "IMAGE_ARM=${IMAGE_ARM} DISK_IMAGE_ARM=${DISK_IMAGE_ARM:-"${IMAGE_ARM%:*}:dev-disk-arm64"} ./scripts/local-build-qcow2.sh"
  pause
fi

# ────────────────────────────────────────────────────────────
step "3" "Rygtest af image som container"
# ────────────────────────────────────────────────────────────
if should_run "3"; then
  ascii "  Kør image som almindelig container – hurtig feedback inden VM-berøring:"
  ascii ""
  ascii "   ┌──────────────────────┐   podman run --rm -p   ┌──────────────────┐"
  ascii "   │ Lokalt Container OS  │ ─────────────────────► │ Smoke Test       │"
  ascii "   │ (:dev-arm64)         │                        │ (HTTP / MOTD)    │"
  ascii "   └──────────────────────┘                        └──────────────────┘"
  ascii ""
  ascii "   ✔  Verificerer webside og motd er bagt ind – ingen VM nødvendig"
  echo ""
  narrate "Kør image som en almindelig container først – hurtig feedback inden vi rører en VM"
  narrate "Tjek at websiden og motd er bagt ind"
  pause "Tryk ENTER for at starte rygtest..."
  run "IMAGE=${IMAGE_ARM} ./scripts/local-test.sh"
  pause
fi

# ────────────────────────────────────────────────────────────
step "4" "Push og signer image"
# ────────────────────────────────────────────────────────────
if should_run "4"; then
  ascii "  Push lokalt ARM64-image til Quay og signer med nøglefri Cosign:"
  ascii ""
  ascii "   ┌──────────────────────┐   podman push / cosign   ┌────────────────────┐"
  ascii "   │ Lokalt Container OS  │ ────────────────────────►│ Quay Registry      │"
  ascii "   └──────────────────────┘                          │ (:dev-arm64)       │"
  ascii "                                                     └────────────────────┘"
  ascii ""
  ascii "   ┌──────────────────────┐   git push / dispatch    ┌────────────────────┐"
  ascii "   │ Git Source Commit    │ ────────────────────────►│ GitHub Actions     │"
  ascii "   └──────────────────────┘                          │ (AMD64 Build)      │"
  ascii "                                                     └────────────────────┘"
  ascii ""
  ascii "   local-push.sh:         podman push :dev-arm64 → Quay"
  ascii "   local-sign-keyless.sh: skopeo → digest → cosign sign (OIDC)"
  echo ""
  narrate "Push :dev-arm64 til Quay.io (lokalt ARM64 image, til UTM VM)"
  narrate "Signer med nøglefri Cosign (OIDC – ingen langtidsholdbar nøglematerie)"
  pause "Tryk ENTER for at pushe og signere..."
  run "IMAGE_ARM=${IMAGE_ARM} ./scripts/local-push.sh"
  run "IMAGE=${IMAGE_ARM} ./scripts/local-sign-keyless.sh"

  narrate "Pusher nuværende git-ændringer til main for at udløse GitHub Actions CI..."
  narrate "CI bygger både :dev-amd64 og dens containerDisk (:dev-disk-amd64) sekventielt."

  if [ -n "$(git status --porcelain)" ]; then
    note "Lokale ændringer fundet. Committer og pusher..."
    run git commit -a -m "\"chore: push præsentationsfremskridt for at udløse CI\""
    run git push
  else
    note "Ingen lokale ændringer fundet."

    LOCAL_COMMITS=$(git log origin/main..HEAD 2>/dev/null || true)

    if [ -n "$LOCAL_COMMITS" ]; then
      note "Lokale commits eksisterer. Pusher..."
      run git push
    else
      note "Ingen nye commits at pushe. Laver en ændring i files/motd for at udløse CI..."

      MOTD_VERSION="v1-$(date +%F-%H%M%S)"
      echo "RHEL 10 Image Mode Demo ${MOTD_VERSION}" > files/motd

      note "Opdaterede files/motd til: ${MOTD_VERSION}"
      run cat files/motd

      if ! git remote -v | grep -q origin; then
        note "Ingen git remote konfigureret. Springer commit/push over."
      else
        run git add files/motd
        run git commit -m "\"chore: bump motd til ${MOTD_VERSION} for at udløse CI\""
        run git push
      fi
    fi
  fi
fi

# ────────────────────────────────────────────────────────────
step "5" "GitHub Actions CI-pipeline"
# ────────────────────────────────────────────────────────────
if should_run "5"; then
  ascii "  Hvert push til main udløser den konsoliderede pipeline:"
  ascii ""
  ascii "   ┌────────────────────┐   Byg / Signer / Push   ┌──────────────────────┐"
  ascii "   │ GitHub Runner      │ ──────────────────────► │ Quay Registry        │"
  ascii "   │ (ubuntu-latest)    │   (nativt amd64)        │ (:dev-amd64 &        │"
  ascii "   │                    │                         │  :dev-disk-amd64)    │"
  ascii "   └────────────────────┘                         └──────────────────────┘"
  ascii ""
  ascii "   Pipeline-trin:"
  ascii "     build OS-image  →  byg qcow2  →  byg containerDisk  →  push til Quay"
  ascii ""
  ascii "   ✔  Én samlet pipeline undgår race conditions eller duplikerede builds"
  echo ""
  narrate "Hvert push til main udløser: byg OS-image → byg qcow2 → byg containerDisk → push begge til Quay"
  manual "Åbn GitHub → Actions → 'Build, Sign, and Push bootc (AMD64 & ARM64)' og vis den kørende workflow"
  manual "Peg på: build-job, storage-config, Quay-push, Cosign-sign og containerDisk-push"
  note "Den enkelt konsoliderede pipeline undgår race conditions eller duplikerede builds."
  pause "Tryk ENTER når workflow er grøn..."
fi

# ────────────────────────────────────────────────────────────
step "6" "Promover :dev → :prod"
# ────────────────────────────────────────────────────────────
if should_run "6"; then
  ascii "  Promovering = skopeo copy – IKKE et nyt build:"
  ascii ""
  ascii "   ┌──────────────────────┐       skopeo copy       ┌────────────────────────┐"
  ascii "   │ Quay: :dev-amd64     │ ──────────────────────► │ Quay: :prod-amd64      │"
  ascii "   └──────────────────────┘    (Samme SHA-digest)   └────────────────────────┘"
  ascii ""
  ascii "   ✔  Det der blev testet er præcis det, der kører i prod – ingen overraskelser"
  echo ""
  narrate "Promote-workflow bruger skopeo copy – samme digest, bare et nyt tag"
  narrate "Intet nyt build – det der blev testet er præcis det, der når prod"
  manual "AMD64-image promoveres af GitHub Actions med source_tag: dev-amd64"
  pause "Tryk ENTER når :prod-amd64 er promoveret..."
fi

# ────────────────────────────────────────────────────────────
step "7a" "Lav en synlig ændring for at udløse en live opdateringsdemo"
# ────────────────────────────────────────────────────────────
if should_run "7a"; then
  ascii "  Ændr motd så opdateringen er tydelig på VM'en efter genstart:"
  ascii ""
  ascii "   ┌──────────────────────┐    git commit & push    ┌──────────────────────┐"
  ascii "   │ Opdater files/motd   │ ──────────────────────► │ GitHub Actions       │"
  ascii "   │ (versionsbump)       │                         │ (Lokalt ARM64)       │"
  ascii "   └──────────────────────┘                         └──────────────────────┘"
  echo ""
  narrate "Ændr motd så opdateringen er tydelig på VM'en efter genstart"
  pause "Tryk ENTER for at skrive det nye motd og pushe..."
  MOTD_VERSION="v2-$(date +%F-%H%M)"
  run "echo 'RHEL 10 Image Mode Demo ${MOTD_VERSION}' > files/motd"
  run cat files/motd
  run git add files/motd
  run git diff --cached -- files/motd
  run git commit -m "\"chore: bump motd til ${MOTD_VERSION} for live opdateringsdemo\""
  run git push
  narrate "GitHub-push registrerer ændringen; genbyg ARM64-image lokalt til UTM VM"
  manual "Kør ./scripts/local-build.sh, derefter ./scripts/local-push.sh for at publicere :dev-arm64"
  pause "Tryk ENTER når det nye :dev-arm64 image er pushet til Quay..."
fi

# ────────────────────────────────────────────────────────────
step "7b" "Tjek nuværende VM-tilstand (inden opdatering)"
# ────────────────────────────────────────────────────────────
if should_run "7b"; then
  ascii "  SSH ind i UTM VM og registrer den nuværende bootede digest:"
  ascii ""
  ascii "   ┌──────────────────────┐     ssh vm-status       ┌──────────────────────────┐"
  ascii "   │ Lokal arbejdsstation │ ──────────────────────► │ UTM Virtuel Maskine      │"
  ascii "   └──────────────────────┘                         │ (registrerer digest)     │"
  ascii "                                                    └──────────────────────────┘"
  ascii ""
  ascii "   vm-status er bagt ind i image – tilgængeligt overalt dette OS kører."
  echo ""
  narrate "SSH ind i UTM VM og registrer den nuværende bootede digest"
  narrate "vm-status er bagt ind i image – tilgængeligt overalt dette OS kører"
  note "Opretter forbindelse til ${VM_SSH}"
  pause "Tryk ENTER for at tjekke VM-status..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-status || true
  pause
fi

# ────────────────────────────────────────────────────────────
step "7c" "Hent og anvend opdateringen på VM'en"
# ────────────────────────────────────────────────────────────
if should_run "7c"; then
  ascii "  bootc upgrade henter de nye lag og stager dem atomisk:"
  ascii ""
  ascii "   ┌──────────────────────┐    ssh vm-upgrade       ┌──────────────────────────┐"
  ascii "   │ Quay Registry        │ ◄────────────────────── │ UTM Virtuel Maskine      │"
  ascii "   │ (:dev-arm64)         │   (bootc upgrade)       │ (Staged & Genstart)      │"
  ascii "   └──────────────────────┘                         └──────────────────────────┘"
  ascii ""
  ascii "   Det kørende OS er urørt indtil genstart – atomisk, sikker rollback-punkt bevaret."
  echo ""
  narrate "bootc upgrade henter de nye :dev-arm64 lag og stager dem"
  narrate "Det kørende OS er urørt indtil genstart – atomisk, sikker rollback-punkt bevaret"
  pause "Tryk ENTER for at udløse vm-upgrade (vil genstarte VM'en)..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-upgrade || true
  note "VM genstarter – venter 30 sekunder..."
  sleep 30
  pause "Tryk ENTER når VM'en er oppe igen (tjek UTM-konsollen om nødvendigt)..."
fi

# ────────────────────────────────────────────────────────────
step "7d" "Verificer opdateringen på VM'en"
# ────────────────────────────────────────────────────────────
if should_run "7d"; then
  ascii "  Ny digest bør adskille sig fra det vi så i trin 7b:"
  ascii ""
  ascii "   ┌──────────────────────┐     ssh vm-status       ┌──────────────────────────┐"
  ascii "   │ Lokal arbejdsstation │ ──────────────────────► │ UTM Virtuel Maskine      │"
  ascii "   └──────────────────────┘                         │ (verificer v2 digest)    │"
  ascii "                                                    └──────────────────────────┘"
  ascii ""
  ascii "   motd bør nu vise v2 – bevis på at det nye image kører."
  echo ""
  narrate "Ny digest bør adskille sig fra det vi så i trin 7b"
  narrate "motd bør nu vise v2"
  pause "Tryk ENTER for at verificere..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-status || true
  pause
fi

# ────────────────────────────────────────────────────────────
step "8" "Rollback"
# ────────────────────────────────────────────────────────────
if should_run "8"; then
  ascii "  Én kommando, én genstart – tilbage til præcis det forrige image:"
  ascii ""
  ascii "   ┌──────────────────────┐  sudo bootc rollback   ┌──────────────────────────┐"
  ascii "   │ Lokal arbejdsstation │ ──────────────────────►│ UTM Virtuel Maskine      │"
  ascii "   └──────────────────────┘                        │ (Ruller tilbage & Genstart)│"
  ascii "                                                   └──────────────────────────┘"
  ascii ""
  ascii "   bootc bevarer den forrige deployment – rollback er øjeblikkelig, ingen geninstallation."
  ascii "   Én kommando, én genstart – tilbage til det præcise forrige image."
  echo ""
  narrate "bootc bevarer den forrige deployment – rollback er øjeblikkelig, ingen geninstallation"
  narrate "Én kommando, én genstart – tilbage til det præcise forrige image"
  pause "Tryk ENTER for at udløse rollback..."
  note "En sudo-adgangskodeprompt vises inde i SSH-sessionen. Indtast VM'ens sudo-adgangskode."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" "sudo bootc rollback" || true
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" "sudo systemctl reboot" || true
  note "VM genstarter efter rollback – venter 30 sekunder..."
  sleep 30
  pause "Tryk ENTER når VM'en er oppe igen..."
  run ssh -tt ${SSH_OPTIONS} "${VM_SSH}" vm-status || true
  pause
fi

# ────────────────────────────────────────────────────────────
step "9a" "OpenShift Virtualization – byg disk-image og provisionér VM"
# ────────────────────────────────────────────────────────────
if should_run "9a"; then
  ascii "  Samme OS, nu som KubeVirt VirtualMachine på SNO:"
  ascii ""
  ascii "   ┌──────────────────────┐   skopeo promote    ┌──────────────────────────┐"
  ascii "   │ Quay: dev-disk-amd   │ ─────────────────── │ Quay: prod-disk-amd      │"
  ascii "   └──────────────────────┘   (samme digest)    └─────────────┬────────────┘"
  ascii "                                                              │  CDI Pull"
  ascii "   ┌──────────────────────┐   Ansible Playbook  ┌─────────────▼────────────┐"
  ascii "   │ OpenShift Klynge     │ ◄────────────────── │ KubeVirt / Virt VM       │"
  ascii "   │ (SNO x86_64)         │                     │ (provision-vm.yml)       │"
  ascii "   └──────────────────────┘                     └──────────────────────────┘"
  ascii ""
  ascii "   provision-vm.yml opretter: Namespace, PullSecret, DataVolume, VirtualMachine"
  ascii "   CDI importerer VM-disk fra Quay – ingen HTTP-server nødvendig."
  echo ""
  narrate "Samme OS, nu kørende som en KubeVirt VirtualMachine på SNO"
  narrate "Vi byggede :dev-disk-amd64 i trin 4 – nu promoverer vi til :prod-disk-amd64 (samme digest, nyt tag)"
  narrate "CDI henter :prod-disk-amd64 direkte fra Quay – ingen HTTP-server nødvendig"
  narrate "Kun AMD64-disk bruges her – x86_64 SNO-klyngen kan ikke køre arm64"
  note "Logger ind på SNO-klynge: ${SNO_API}"
  if [[ -n "${SNO_TOKEN}" ]]; then
    run oc login "${SNO_API}" --token="${SNO_TOKEN}" --insecure-skip-tls-verify
  else
    manual "Kør: oc login ${SNO_API} --token=<dit-token> --insecure-skip-tls-verify"
    pause "Tryk ENTER når du er logget ind på SNO..."
  fi

  _BASE="${IMAGE_AMD%:*}"
  PROD_IMAGE_AMD="${PROD_IMAGE_AMD:-${_BASE}:prod-amd64}"
  SOURCE_DISK_AMD="${DISK_IMAGE_AMD:-${_BASE}:dev-disk-amd64}"
  PROD_DISK_IMAGE_AMD="${PROD_DISK_IMAGE_AMD:-${_BASE}:prod-disk-amd64}"
  note "PROD_IMAGE_AMD      = ${PROD_IMAGE_AMD}"
  note "PROD_DISK_IMAGE_AMD = ${PROD_DISK_IMAGE_AMD}  (containerDisk til CDI)"

  until skopeo inspect docker://$DISK_IMAGE_AMD >/dev/null 2>&1; do
    echo "Venter på $DISK_IMAGE_AMD..."
    sleep 15
  done
  narrate "Trin 9a-i: promover :dev-disk-amd64 → :prod-disk-amd64 via skopeo copy (samme digest, nyt tag)"
  narrate "Spejler OS-image-promoveringen: :dev-amd64 → :prod-amd64 – intet nyt build, det der blev testet kører"
  pause "Tryk ENTER for at promovere :dev-disk-amd64 → :prod-disk-amd64..."
  run SOURCE_DISK="${SOURCE_DISK_AMD}" TARGET_DISK="${PROD_DISK_IMAGE_AMD}" ./scripts/local-promote-disk.sh

  narrate "Trin 9a-ii: Ansible opretter Namespace, PullSecret, DataVolume og VirtualMachine"
  pause "Tryk ENTER for at køre Ansible-provisionerings-playbook..."
  run ansible-playbook ansible/provision-vm.yml \
    -e "disk_image=${PROD_DISK_IMAGE_AMD}" \
    -e "ssh_pub_key=\"$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'ERSTAT_NØGLE')\""
  manual "Åbn OpenShift-konsollen → Virtualization → VirtualMachines og vis VM'en starte"
  pause
fi

# ────────────────────────────────────────────────────────────
step "9b" "OpenShift Virtualization – opgrader VM med Ansible"
# ────────────────────────────────────────────────────────────
if should_run "9b"; then
  ascii "  Samme bootc-opgraderingsloop, nu orkestreret af Ansible via virtctl SSH:"
  ascii ""
  ascii "   ┌──────────────────────┐   Ansible Playbook   ┌──────────────────────────┐"
  ascii "   │ upgrade-vm.yml       │ ──────────────────── │ virtctl SSH / bootc      │"
  ascii "   └──────────────────────┘                      │ (Automatisk opgradering) │"
  ascii "                                                 └──────────────────────────┘"
  ascii ""
  ascii "   Tjek før → opgrader → genstart → verificer – fuldt automatiseret."
  echo ""
  narrate "Samme bootc-opgraderingsloop, nu orkestreret af Ansible via virtctl SSH"
  narrate "Tjek før, opgrader, genstart, verificer – fuldt automatiseret"
  pause "Tryk ENTER for at køre Ansible-opgradering-playbook..."
  run ansible-playbook ansible/upgrade-vm.yml
  pause
fi

# ────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   Demo afsluttet!                                            ║"
echo "  ║                                                              ║"
echo "  ║   Repo:                        ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Chatbot som Quadlet i RHEL Image Mode

Denne extension viser en AI Lab Recipes-chatbot i to trin:

```text
AI Lab Recipes image
    -> test som almindelig container
    -> Quadlet i næste bootc-image
    -> bootc switch
    -> reboot
    -> systemd starter chatbot-containeren
```

## Konfiguration

Sæt den eksakte image-reference fra den valgte AI Lab Recipes-opskrift i den
lokale `scripts/demo-env.sh`:

```bash
export AI_LAB_RECIPES_DIR=""
export CHATBOT_PORT="8501"
```

Recipe-projektets app-, model-server- og model-images er defineret af recipe'en.
Standard-chatbotten bruger port `8501` internt.

## Test før Image Mode

Test først imaget separat og vis det i Podman Desktop:

```bash
./scripts/test-chatbot-container-m5.sh
```

Åbn derefter `http://localhost:8081` eller den konfigurerede port. Kontroller,
at containeren starter, at logs ser fornuftige ud, og at chatbot-endpointet
svarer.

## Byg update-imaget

Kør:

```bash
./scripts/prepare-demo-m5.sh
```

Scriptet bygger `IMAGE_UPDATE` med denne Quadlet:

```ini
The generated artifacts reference:

- `quay.io/ai-lab/chatbot:latest`
- `quay.io/ai-lab/llamacpp_python:latest`
- `quay.io/ai-lab/granite-7b-lab:latest`
```

Den endelige bootc-image indeholder altså både RHEL-webworkloaden og chatbot-
containerens deklaration. Containeren installeres ikke manuelt på den kørende
VM.

## Demo på VM'en

Efter `demo-run-m5.sh` har staged og rebootet update-imaget, vis:

```bash
sudo bootc status
sudo systemctl status chatbot.service
sudo journalctl -u chatbot.service --no-pager
podman ps
```

Åbn chatbotten via VM'ens IP-adresse på port `8081`.

## Vigtige forbehold

- Chatbot-imaget er en workload-container; det gør ikke hele RHEL-imaget CVE-frit.
- “0 CVE” er resultatet af en bestemt scanning på et bestemt tidspunkt.
- Gem scanner, database-version, tidspunkt og image-digest sammen med build-artifactet.
- Hvis chatbotten kræver model-filer eller persistent data, skal de ligge på et
  separat volume og ikke inde i det immutable OS-image.
- Hvis recipe-containeren kræver environment variables, secrets eller volumes,
  skal de tilføjes til Quadlet-filen efter recipe-dokumentationen.

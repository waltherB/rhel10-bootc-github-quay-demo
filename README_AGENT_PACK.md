# Bootc Copilot Agent Knowledge Pack - Version 2

This pack adds a repository-local knowledge base for a Microsoft 365 Copilot declarative agent focused on a Red Hat Enterprise Linux Image Mode / bootc demo.

## How to install

From the root of the repository:

```bash
unzip bootc-agent-pack-v2.zip

git add .agent docs README_AGENT_PACK.md

git commit -m "Add Bootc Demo Copilot Agent knowledge pack v2"

git push
```

## Intended agent role

The agent should act as a senior Red Hat/Linux platform engineer and help with:

- Demo preparation
- Script review
- bootc troubleshooting
- GitHub Actions and Quay workflows
- QCOW2 image generation
- Live demo recovery
- Speaker notes
- Enterprise architecture positioning
- Service/productization opportunities for Atea

## Important note

This pack is designed as a knowledge and instruction pack. It does not replace testing the actual repository scripts. When the agent is used, it should always inspect the current repository files before giving repo-specific advice.

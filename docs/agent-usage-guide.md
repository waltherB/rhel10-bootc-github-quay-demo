# Copilot Agent Usage Guide

## How To Use The Agent

Start prompts with one of the command keywords.

## Architecture Review

```text
BOOTC_ARCHITECT
Review the current repository and suggest the top 10 improvements for enterprise demo value.
```

## Script Review

```text
BOOTC_REVIEW
Review scripts/local-build.sh for live demo reliability.
```

## Risk Review

```text
BOOTC_RISK
I need to run this demo tomorrow for a customer. Identify what can fail and what I should prepare.
```

## Live Recovery

```text
BOOTC_RECOVERY
This failed during rehearsal:

podman push quay.io/example/rhel10-bootc-demo:latest

Error:
unauthorized: access to the requested resource is not authorized
```

## Speaker Notes

```text
BOOTC_SPEAKER
Create a 15 minute customer-facing narrative for Linux platform engineers.
```

## Checklist

```text
BOOTC_CHECKLIST
Generate a pre-flight checklist for running this on a MacBook M4 with UTM.
```

## Runbook

```text
BOOTC_RUNBOOK
Generate a complete 30 minute demo runbook with commands, expected output and fallback paths.
```

## Best Practice

Ask the agent to separate:

```text
What exists in the repo
What is inferred
What is recommended
```

Example:

```text
BOOTC_ARCHITECT
Review this repository. Separate facts from assumptions and recommendations.
```

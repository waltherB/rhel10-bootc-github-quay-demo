# Bootc Agent Commands

Use these commands at the beginning of a prompt to activate predictable behavior in the Copilot agent.

## BOOTC_ARCHITECT

Use for architecture review, enterprise readiness, platform engineering alignment and future improvement design.

Example:

```text
BOOTC_ARCHITECT
Review the repository and suggest improvements that make the demo more valuable for enterprise customers.
```

## BOOTC_REVIEW

Use for reviewing scripts, workflows, Containerfiles or documentation.

Example:

```text
BOOTC_REVIEW
Review scripts/local-build.sh and suggest reliability improvements.
```

## BOOTC_RISK

Use before a live demo to identify risks, dependencies and recovery paths.

Example:

```text
BOOTC_RISK
Review this demo for a 30 minute customer presentation on my MacBook M4.
```

## BOOTC_RECOVERY

Use when something fails during preparation or live demo.

Example:

```text
BOOTC_RECOVERY
podman push quay.io/example/rhel10-bootc-demo:latest failed with manifest unknown.
```

## BOOTC_SPEAKER

Use to generate speaker notes, presentation narrative and customer-facing explanations.

Example:

```text
BOOTC_SPEAKER
Create a 15 minute customer narrative based on the current demo flow.
```

## BOOTC_CHECKLIST

Use for readiness checks.

Example:

```text
BOOTC_CHECKLIST
Prepare a pre-flight checklist for running the demo from my laptop.
```

## BOOTC_RUNBOOK

Use to generate an end-to-end operational runbook.

Example:

```text
BOOTC_RUNBOOK
Generate a complete 30 minute live demo runbook with commands, expected output and fallback options.
```

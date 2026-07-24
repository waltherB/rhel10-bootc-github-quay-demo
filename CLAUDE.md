# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Karpathy Guidelines

These are coding principles inspired by Andrej Karpathy's approach to software engineering, designed to reduce common LLM coding mistakes.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Core Behavioral Guidelines

### 1. Think Before Coding
**Don't assume. Don't hide confusion. Surface tradeoffs.**
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First
**Minimum code that solves the problem. Nothing speculative.**
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes
**Touch only what you must. Clean up only your own mess.**
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

### 4. Goal-Driven Execution
**Define success criteria. Loop until verified.**
Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

## Core Engineering Principles

1. **Clarity Over Cleverness**: Write code for humans first, machines second.
2. **Readability**: Code is read far more often than written. Use clear naming and keep functions focused.
3. **Testing and Validation**: Test driven development (TDD) when possible. Verify assumptions explicitly.
4. **Modularity and Separation of Concerns**: Loose coupling, high cohesion. Clear interfaces between modules.
5. **Documentation**: Document "why" decisions, not "what" code does. Keep comments updated with code.
6. **Debugging and Validation**: Add instrumentation for visibility. Log important state transitions.
7. **Code Review and Iteration**: Embrace refactoring and make incremental improvements.
8. **No Premature Optimization**: Make it work first, make it clear second, optimize last (if needed).
9. **Consistency**: Consistent naming conventions, code style, and error handling.

## Applied to This Project

- Use clear names for payment states and transaction statuses
- Keep API clients simple and focused
- Document the MobilePay integration strategy
- Write tests that validate payment flows
- Keep controller logic minimal
- Use logging for transaction tracking
- Separate concerns between auth, payments, and webhooks

## Odoo & OCA Coding Guidelines

1. **Module Structure and Versioning**
   - Use the singular form in module names.
   - Version numbers should follow `Odoo_Version.x.y.z` (e.g., `17.0.1.0.0`).
   - Standard directory structure: `controllers/`, `data/`, `models/`, `security/`, `views/`, etc.

2. **XML Files**
   - Indent using four spaces. Place `id` attribute before `model`.
   - Naming `xml_id`: `<model_name>_<record_name>` for data.
   - For views: `<model_name>_view_<view_type>` (e.g., `res_users_view_form`).
   - For actions: `<model_name>_action`.

3. **Python Guidelines**
   - Adhere to PEP8 and PyFlakes.
   - Order imports: Standard library, third-party, Odoo imports (`odoo`), Odoo modules, Local imports.
   - Use UpperCamelCase for classes (e.g., `AccountInvoice`) and snake_case for variables.
   - Avoid `_id` or `_ids` suffixes for variables that contain recordsets instead of actual IDs.

4. **Database & SQL**
   - **No SQL Injection**: Never use string concatenation or interpolation for SQL queries. Use `psycopg2` parameters.
   - **Never commit the transaction**: The Odoo framework handles transactions; do not call `cr.commit()` manually.




## Development Workflow

### Core Commands
- **Clone & Setup**: Ensure you have `podman`, `qemu-img`, and `cosign` installed.
- **Build OCI Image**: `./scripts/local-build.sh`
- **Smoke Test**: `./scripts/local-test.sh`
- **Push to Quay**: `./scripts/local-push.sh`
- **Sign with Cosign**: `./scripts/local-sign-keyless.sh`
- **Build QCOW2 Disk**: `./scripts/local-qcow2.sh` (Handles `amd64` and `arm64` variants)
- **Push Disk Image**: `./scripts/local-push-disk.sh`
- **Run Demo:** `./scripts/demo-run.sh`

### Environment Setup
The project uses a `scripts/demo-env.sh` file to manage environment variables for the demonstration runner. It is recommended to mirror these values in your local environment when running interactive scripts.

## Architecture & Structure

This repository demonstrates **Bootc** (Red Hat's system-build approach) and **OpenShift Virtualization**. The flow follows a "Build, Sign, Deploy" pipeline:

### 1. OS Image Lifecycle
- **source**: A base image (e.g., Fedora/RHEL) is processed by `bootc-image-builder`.
- **Development**: Images are tagged as `:dev` and pushed to Quay for quick iteration.
- **Validation**: The system undergoes smoke tests using standard container execution before being promoted.
- **Production**: Final images are promoted to `:prod` via `skopeo copy` (ensuring identical digests) and then transformed into `containerDisk` OCI images for KubeVirt/CDI consumption.

### 2. Infrastructure Layers
- **Build System**: Uses Podman for container-native building and local testing.
- **Storage/Registry**: Quay.io serves as the registry for both OS image layers and the final `.qcow2` disk images (packaged as `containerDisk`).
- **Orchestration**: OpenShift Virtualization (KubeVirt) manages VM lifecycles.
- **Provisioning**: Ansible is used to automate the creation, configuration, and upgrading of VMs within the OpenShift cluster.

### 3. Key Directories
- `scripts/`: Contains all core logic for building images, pushing to registries, and running the interactive demonstration runner.
- `ansible/`: Playbooks for VM lifecycle management (Provisioning, Upgrading).
- `config/`: Configuration files (e.g., `config.toml`) used by the `bootc-image-builder`.
- `gitops/`: Relevant configurations for OpenShift Virtualization (KubeVirt) resource definitions.
- `app/`: Small sample application content used during the demo to verify boot successfulity.

## Project Specifics
- **Architecture**: The default target is often `linux/amd64` for compatibility with most cloud runners, but the system supports `arm64` (e.g., Mac M1/M2/M3/M4) builds via `TARGET_PLATFORM`.
- **Bootc Focus**: This project specifically showcases how Bootc enables "Image Mode" where the OS is treated as an immutable container image.

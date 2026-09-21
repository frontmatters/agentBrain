# agentBrain: zero to hero

This guide installs **agentBrain**, the local-first memory layer for AI coding agents. agentBrain is not an agent and not a harness. It gives agents a shared Markdown knowledge base, shared instructions, skills, and optional add-ons.

## 1. What agentBrain does

agentBrain stores your reusable context in one place:

- `system/` contains the public framework, rules, skills, integrations, and templates.
- `vault/` contains your private knowledge, such as learnings, troubleshooting notes, projects, preferences, and daily notes.
- Agent integrations install a pointer so Claude Code, Pi, Copilot, Cursor, and other clients can read the same brain.

The data stays on your machine. agentBrain does not require a database, embeddings, or a cloud account.

## 2. Install the prerequisites

On macOS, the easiest route is the bootstrap installer. It installs the required developer tools, agentBrain, and the Pi integration:

```sh
curl -fsSL https://getagentbrain.com/install.sh | bash
```

If you prefer to inspect the repository first, clone it and run the bootstrap script:

```sh
git clone https://github.com/frontmatters/agentBrain.git ~/Developer/agentBrain
cd ~/Developer/agentBrain
bash scripts/installer/bootstrap/macos.sh
```

For a minimal or non-macOS setup:

```sh
git clone https://github.com/frontmatters/agentBrain.git ~/Developer/agentBrain
cd ~/Developer/agentBrain
./setup.sh
```

The setup is idempotent. Running it again refreshes connectors and keeps your existing vault data.

## 3. Understand what setup changes

Setup creates or refreshes the private vault, agent pointers, shared skills, and detected integrations. The default private vault link is `~/.agentBrain/vault`.

The installer does not put your notes in the public framework. Your private vault remains separate from the tracked `system/` files.

Inspect the available setup options before an advanced install:

```sh
./setup.sh --help
```

Useful options include `--yes` for non-interactive setup, `--home=PATH` for an alternate tool-config home, and `--vault=PATH` for a shared or custom vault location.

## 4. Start a harness and connect a model

agentBrain is the memory layer, so installation does not by itself create an active AI conversation. After setup, start one of the harnesses you installed and make sure that harness can send a request to a model.

For Pi, start a fresh login shell first when the installer added tools to your shell configuration:

```sh
exec zsh -l
pi
```

On the first Pi run, use `/login` and complete the provider authentication. Then use `/onboard` inside Pi. Pi has the deepest agentBrain integration and is the recommended first harness on macOS.

For Claude Code, GitHub Copilot CLI, Gemini CLI, or OpenCode, start the corresponding command, complete its account login or provider setup, and only then run `/onboard` when that harness supports agentBrain skills. The integration only supplies the brain pointer and shared skills; it does not authenticate your AI account for you.

For the agentBrain Harness Web UI, start it with:

```sh
brain harness
```

Open the displayed local URL, configure a model provider in the Web UI, select a workspace, and start a session. The Harness Web UI is a separate component from agentBrain itself. Its provider setup is described in [`docs/integrations/abh.md`](./integrations/abh.md).

### If you use Ollama

Ollama is a local model runtime, not an account login. Install or update it when the installer offers it, then install at least one model before starting the harness:

```sh
ollama pull <model-name>
ollama list
```

Replace `<model-name>` with the model you want to use, such as a model supported by your machine. Start Ollama when your platform requires a running service:

```sh
ollama serve
```

Configure the harness to use the installed local model. Do not run `/onboard` until the harness can successfully send a test request. A successful model response proves that authentication or local model setup is complete; `/onboard` then writes your preferences into the brain.

## 5. Run onboarding

Run onboarding only after the harness is running and connected to a model:

```text
/onboard
```

Onboarding helps you configure personal preferences, optional organization and team scopes, add-ons, locale, and the release channel. It starts with `vault/preferences/personal/` and asks before adding optional scopes or capabilities.

If your harness cannot run slash commands, run the model-free wizard directly:

```sh
brain onboard
```

The wizard does not need an AI model. It writes the same fixed-choice preferences locally, so it is also the recovery path when a harness login or model setup is not complete. Read [`system/skills.md`](../system/skills.md), inspect [`system/addons/README.md`](../system/addons/README.md), and run the relevant CLI commands from the next sections.

## 6. Verify the installation

Run the health audit from the repository root:

```sh
bash scripts/checks/doctor.sh
```

Then verify the detected agent integrations:

```sh
bash scripts/selftest.sh
```

You can list the self-tests and run one client only:

```sh
bash scripts/selftest.sh --list
bash scripts/selftest.sh --only=claude-code
```

A healthy setup means the pointer and skills for each detected agent resolve to the same agentBrain checkout, the vault is readable, and the framework checks pass.

## 7. Use the brain in daily work

Start an agent in any project. The agent reads the agentBrain pointer at session start and can use the shared skills.

Use the knowledge lifecycle deliberately:

1. Ask the agent to read relevant brain notes before making a decision.
2. Save a reusable technical discovery with `/save-learning`.
3. Save a reproducible bug fix with `/save-troubleshoot`.
4. Record a project milestone with `/project-update`.
5. Park unfinished work with `/park`.
6. Resume it later with `/unpark`.
7. Run `/doctor` when the framework or vault may be inconsistent.

A good first task is:

> Read the relevant agentBrain instructions. Inspect this project and tell me which existing patterns, preferences, or troubleshooting notes apply. Do not modify files.

After solving a real problem, ask:

> Save the reusable solution as a troubleshooting note. Include the symptom, root cause, exact fix, verification command, and any conditions where it does not apply.

## 8. Add capabilities carefully

List the add-ons available on this checkout:

```sh
bash scripts/addons.sh status
```

Install an add-on only when you understand its privacy and network behavior:

```sh
bash scripts/addons.sh install <addon-id>
bash scripts/addons.sh check <addon-id>
bash scripts/addons.sh test <addon-id>
```

The add-on registry and each manifest explain what an add-on reads, writes, installs, and schedules. Add-ons are optional. The core brain does not depend on them.

## 9. Keep private knowledge separated

Use a space for employer or client knowledge:

```sh
bash scripts/new-space.sh <slug> --owner "<owner>" --relation client
```

Spaces live below `vault/spaces/<slug>/` and provide a boundary for context, sync, and recall. Use the space-aware commands described in [`docs/spaces.md`](./spaces.md).

Use incognito mode when you want to consult the brain without writing new notes:

```text
/incognito on
```

Turn it off when normal persistence is safe again:

```text
/incognito off
```

Never store API keys, passwords, tokens, or private credentials in shared notes. Keep operational secrets in the dedicated private security and integration areas, or use the configured secret helper.

## 10. Update agentBrain

Check whether an update is available:

```sh
bash scripts/brain-update.sh --check
```

Before updating, commit or back up local framework changes and make sure your private vault is safe. The update process refreshes the public framework while preserving the vault.

After an update, run:

```sh
bash scripts/checks/doctor.sh
bash scripts/selftest.sh
```

## 11. Move or uninstall

Move the checkout and update its pointers safely with:

```sh
bash scripts/setup/setup.sh --move-to /new/path/agentBrain
```

Remove the integrations without deleting your knowledge:

```sh
bash scripts/uninstall.sh
```

Read the uninstall output before confirming. The uninstall process is designed to remove what setup added while preserving your vault and checkout.

## 12. Next steps

- Read the [main README](../README.md) for the complete capability map.
- Read [agent integrations](./integrations/README.md) to understand each client.
- Read [spaces](./spaces.md) for client and employer isolation.
- Read [shared vaults](./shared-vault.md) for team knowledge.
- Read [`system/addons/README.md`](../system/addons/README.md) before enabling add-ons.
- Read [`system/skills.md`](../system/skills.md) for the complete shared skill inventory.

## FAQ

### Can multiple people use agentBrain?

Yes, but agentBrain does not provide application-style user accounts. Each person should normally have a separate operating-system account, home directory, agent configuration, credentials, and private vault.

Each user runs the setup from their own account:

```sh
git clone https://github.com/frontmatters/agentBrain.git ~/Developer/agentBrain
cd ~/Developer/agentBrain
./setup.sh
```

Do not run setup as User A while pointing `--home` at User B's home directory. Agent clients read fixed paths under the active user's real home, and mixing ownership creates broken pointers and unsafe credential access.

### Does each user need to run setup again?

For separate operating-system users, yes. Run setup once per user. Each run creates that user's agent pointers, skills, preferences, credentials, and private vault. The public framework can be shared through the repository, but the private vault should not be shared by default.

### Can users share one knowledge base?

Use a shared vault only when the users intentionally share its contents and access permissions. The private vault can be mounted explicitly with `--vault=PATH`, but this makes its notes shared data. For team or client knowledge, prefer the documented [shared vault](./shared-vault.md) or an owner-specific [space](./spaces.md) instead of pointing every user at one personal vault.

A shared vault does not merge users into one agent account. Each user still has separate agent credentials, local preferences, sessions, and integration configuration.

### Can one person have separate agentBrain profiles?

Use separate checkouts and separate configuration homes only when you need isolated environments, such as work and personal setups. `AGENTBRAIN_HOME` or `./setup.sh --home=PATH` changes the configuration base used by setup, but many agent clients still read fixed paths under the active operating-system home. For strong isolation, use separate operating-system users, containers, or machines.

### Can several users use the agentBrain Harness Web UI?

The Harness Web UI is a separate runtime component. It is not an account and does not turn agentBrain into a multi-user server. Run one isolated deployment per user, or place an authenticated multi-user layer in front of a deliberately designed deployment. Do not expose a local development server to other users without reviewing workspace access, credentials, session storage, and approval policy.

### Do users share API keys?

No. Each user should authenticate their own harness account or provider and keep credentials in that user's credential store. Ollama is local instead of account-based, but each user still needs access to the Ollama service and at least one pulled model.

### What is the correct order after setup?

Use this order:

1. Start one installed harness.
2. Log in to its AI provider, or configure a local Ollama model.
3. Send a small test request and confirm it succeeds.
4. Run `/onboard` inside the harness, or run `brain onboard` when the harness cannot expose the skill.
5. Run `brain doctor` and `bash scripts/selftest.sh`.

### What if another user already installed agentBrain on this machine?

Install under the second user's own home directory. Reusing another user's checkout is possible only when filesystem permissions, update ownership, vault routing, and privacy boundaries are intentionally designed. A fresh per-user checkout is the safer default.

## Installer questions and keyboard controls

The installer has two layers: the public installer prompt and the setup prompts that run after the repository is present. The exact list can change with the operating system, installed tools, existing profiles, and detected agents. The order below is the current interactive order.

### Universal menu controls

| Prompt type | Available actions |
| --- | --- |
| Single choice | `↑` and `↓` move, `Home` and `End` jump, `1` to `9` select immediately, `Enter` confirms the highlighted row, `Esc` cancels. |
| Multi-choice checkbox | `↑` and `↓` move, `Space` or the row number toggles the checkbox, `Home` and `End` jump, `Enter` applies, `Esc` cancels. |
| Yes or no | `←` and `→` or `↑` and `↓` move, `1` or `y` selects Yes, `2` or `n` selects No, `Enter` confirms, `Esc` selects No. |
| Text input | Type the value and press `Enter`. Required fields cannot be empty. |

The visible menu shows the default row. Pressing `Enter` accepts that default. A single-choice number does not need a second `Enter`; a multi-choice number toggles the row and still needs `Enter` to apply.

### Public installer order

Run `curl -fsSL https://getagentbrain.com/install.sh | bash` from a real interactive terminal. The installer asks these questions before and after cloning:

1. **Install or update agentBrain at `<destination>`?** Choose Yes to continue or No to cancel. If the destination already contains agentBrain and you choose No, the installer offers **Only personalize it instead?**. Enter accepts the default Yes; `n` cancels.
2. **How do you want to install?** Choose `guided` for explanations at each step or `quick` for minimal output. The default is `guided`.
3. After the platform bootstrap and setup complete, **Enable these add-ons?** appears when default add-ons are not already enabled. All available default add-ons start selected. Use arrows and Space to untick items, then Enter to apply.
4. **Set up optional devtools now?** Choose Yes to open the intent menu or No to skip. The default is No.
5. In the intent menu, toggle any of `mail`, `container`, `python`, and `local-ai` when available. These map to Mailpit, Colima plus ttyd, uv, and Ollama. Enter applies the selected intents.
6. The installer opens a fresh login shell on an interactive terminal. Run `pi`, then use `/login` to connect a model provider and `/onboard` to personalize the brain.

The public installer does not install an AI agent silently. It connects to agents that are already installed, or offers the explicit agent menu during setup.

### macOS bootstrap and direct setup order

The macOS bootstrap runs developer tools first, then `setup.sh`. On Linux, WSL, or a manual checkout, `./setup.sh` runs the setup portion directly.

1. **Install the recommended core tools now?** This appears when Node.js or Bun is missing. The default is Yes. No skips the install and prints the command to run later.
2. If required `git` or `python3` is missing, choose **Install missing dependencies via Homebrew?** on macOS or **Install missing dependencies via apt?** on Debian-like Linux. No stops with an installation instruction.
3. **Private vault selection.** A new checkout uses its local vault automatically. When an existing `local/` directory or another vault is present, setup may ask whether to move or link it to the selected vault. The default for moving existing local content is Yes.
4. **Optional agent CLI menu.** When run interactively, missing rows are marked for installation and installed rows are marked for uninstall. Toggle rows with arrows and Space, then Enter. The rows are `agentBrain Harness`, `Pi`, `Claude Code`, `GitHub Copilot CLI`, `Gemini CLI`, `OpenCode`, `GitHub Copilot extension`, and `Cline extension`. Installed rows are not changed unless you toggle them.
5. **Editor selection.** An extension row uses the only detected VS Code-family editor automatically. If several are present, choose the editor or `skip this row`. If none is present, choose `Visual Studio Code`, `VSCodium`, or `neither`.
6. **Harness Web autostart.** If the Harness is installed and autostart is already enabled, choose `keep` or `disable`. Otherwise answer **Start the agentBrain Harness Web UI automatically at login?**. The default is No.
7. **Install or update Ollama.** This optional capability offer is platform-specific. Accepting it installs or updates Ollama; declining leaves it for later.
8. **Your name for commits** and **Your email for commits** appear when Git identity is missing. Both are required text fields for this setup path. They configure the global Git identity used by vault autosync and spaces.
9. **Configure Pi now?** The default is Yes. This installs or updates Pi and connects its extensions, skills, and configuration. No leaves the command to run later.
10. **Enable the daily self-improving loop?** On macOS with the normal home, the default is No. Yes installs the daily launchd job.
11. **Pick developer tools now?** When setup is run directly, the default is No. Yes opens the `mail`, `container`, `python`, and `local-ai` checkbox menu described above.
12. **Personalize your brain now?** The default is Yes. Yes starts the model-free onboarding wizard. No leaves `brain onboard` or `/onboard` for later.
13. **Configure Pi now?** If Pi was detected but the deep integration was deferred, setup offers this again near the end. The default is Yes. This second question is about wiring the already-installed Pi integration, not installing the agent again.

Already satisfied steps do not ask again. Non-interactive runs use `--yes` or `AGENTBRAIN_ASSUME_YES=1`; they accept consequential defaults, skip agent CLI installation, and avoid interactive menus.

### Onboarding wizard order

The model-free `brain onboard` wizard uses the same menu controls. It asks the following questions, with conditional questions shown only when their condition applies:

1. **What language should we use?** `English`, `Nederlands`, `Deutsch`, `Français`, `Español`, `中文`, or `日本語`.
2. **What language should artifacts use?** If the conversation language is not English: `chat in your language; code, commits & docs in English` or `EVERYTHING in your language`.
3. **How much detail?** `short answers, minimal explanation`, `thorough explanations`, or `the agent judges per topic`.
4. **How autonomous should the agent be?** `check in frequently before acting`, `keep going, ask only when truly stuck`, or `run the whole task without interrupting`.
5. **Primary OS?** `macOS`, `Linux`, `Windows (WSL)`, `Raspberry Pi`, or `other` with typed text.
6. **Which editors do you use?** Multi-select `VS Code`, `Cursor`, `JetBrains`, `Neovim / Vim`, `Zed`, or `other` with typed text.
7. **Which languages and frameworks do you use most?** Multi-select the detected or known entries, with a custom entry available.
8. **Where do you host code?** Multi-select the detected or known entries, with a custom entry available.
9. **Which design default should generated UI follow?** `follow the system / offer a toggle`, `dark as default`, or `light as default`.
10. **How should decisions be made?** `simplest thing that works wins`, `weigh options carefully first`, or `ship, then iterate`.
11. **Which release channel?** `stable`, `prerelease`, and `edge` only when this checkout is an insider development checkout.
12. **How should updates behave?** `prompt when an update is available`, `only mention it at session start`, `update automatically behind the doctor gate`, or `manual only`.
13. **Which preference scopes should be active?** `personal only`, `personal + organization`, or `personal + organization + team`.

The wizard derives the locale from the language choice and writes the selected values into the appropriate private preference notes. It preserves existing answers when you rerun it.

## Glossary

| Term | Meaning |
| --- | --- |
| **Add-on** | An optional agent-agnostic capability managed through `scripts/addons.sh`. |
| **Agent integration** | A pointer, skill link, or configuration entry that lets an agent read agentBrain. |
| **Brain** | The complete agentBrain installation, including its public framework and private vault. |
| **Space** | A private context compartment for one client, employer, or other owner. |
| **Vault** | The private Markdown knowledge store containing your notes and personal context. |

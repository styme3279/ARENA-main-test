# ARENA (runnable material)

This repository holds the **runnable ARENA material** — the exercise and solution
notebooks, `solutions.py` files, and Streamlit instruction pages for every
chapter. It is everything you need to install and run ARENA.

> ⚠️ **This repo is auto-generated.** The source of truth is the master repo
> [`styme3279/ARENA_master_test`](https://github.com/styme3279/ARENA_master_test).
> Do not hand-edit the chapter files here — edit the `master_X_Y.py` files in the
> master repo instead. A GitHub Action rebuilds this repo whenever master changes
> (see [How the build works](#how-the-build-works) below).

## Install & run

```bash
# 1. Clone this repo
git clone https://github.com/styme3279/ARENA-main-test.git

# 2. Run the install script (creates a conda env and installs requirements)
bash ARENA-main-test/install.sh
```

To launch the Streamlit instructions locally:

```bash
streamlit run chapter0_fundamentals/instructions/Home.py
```

## Contents

```
chapter0_fundamentals/        Chapter 0 — Fundamentals
chapter1_transformer_interp/  Chapter 1 — Transformer Interpretability
chapter2_rl/                  Chapter 2 — Reinforcement Learning
chapter3_llm_evals/           Chapter 3 — LLM Evaluations
chapter4_alignment_science/   Chapter 4 — Alignment Science
  └─ exercises/<part>/        *_exercises.ipynb, *_solutions.ipynb, solutions.py, tests, utils
  └─ instructions/            Streamlit app + generated pages/
requirements.txt              Python dependencies
install.sh                    One-shot environment setup
```

## How the build works

| Repo | Workflow | Role |
| --- | --- | --- |
| `ARENA_master_test` | `.github/workflows/notify-main.yml` | On push to `main`, sends a `repository_dispatch` (`master-push`) to this repo. |
| `ARENA-main-test` (here) | `.github/workflows/build-from-master.yml` | Checks out the master repo, runs the conversion tool over every chapter, and commits the regenerated notebooks/pages back here. |

### Incremental vs. full builds

A push to master sends the commit range (`before`..`after`), and the builder
rebuilds **only what changed** (`scripts/incremental_build.sh`):

* an edited `master_X_Y.{py,ipynb}` → only section `X.Y` is regenerated and its
  output copied over;
* an edited support/runtime file (`tests.py`, `utils.py`, data, `requirements.txt`,
  `.streamlit/`, …) → that file is copied/deleted directly, no rebuild;
* a change to the conversion tool or `config.yaml` (`infrastructure/core/**`), or
  an unusable commit range → it falls back to a **full rebuild**.

Manual and scheduled runs always do a full rebuild via `scripts/build_and_sync.sh`,
which drives `infrastructure/core/main.py` over chapters `0`–`4` and copies the
runnable output (chapters + `requirements.txt`, `install.sh`, `pyproject.toml`,
`.streamlit/`, `.devcontainer/`, …) into this repo.

You can trigger a rebuild manually from the **Actions** tab (*Build ARENA from
master* → *Run workflow*), optionally choosing which chapters or which master ref
to build from.

### One-time setup

* **In `ARENA_master_test`** — add a secret `MAIN_REPO_DISPATCH_TOKEN`: a PAT
  that can send a `repository_dispatch` to this repo (fine-grained PAT with
  *Contents: Read and write* on `ARENA-main-test`, or a classic PAT with `repo`
  scope). The built-in `GITHUB_TOKEN` cannot trigger workflows across repos.
* **In `ARENA-main-test`** — only if the master repo is **private**, add a secret
  `MASTER_REPO_TOKEN` that can read it. For a public master repo nothing is
  needed.

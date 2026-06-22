#!/usr/bin/env bash
#
# Build the runnable ARENA material from master files, and sync it into a
# destination repo.
#
# Pipeline (per chapter): master_X_Y.py  ->  X.Y_*_exercises.ipynb,
# X.Y_*_solutions.ipynb, solutions.py, and the Streamlit instruction pages.
# This is exactly what infrastructure/core/main.py does; we just drive it over
# every chapter and copy the results out.
#
# Usage:
#   scripts/build_and_sync.sh <master_repo_dir> <dest_dir> [chapter_numbers...]
#
#   master_repo_dir : path to a checkout of ARENA_master_test (the source repo)
#   dest_dir        : path to the runnable repo to populate (usually ".")
#   chapter_numbers : which chapters to build (default: 0 1 2 3 4)
#
# Examples:
#   scripts/build_and_sync.sh _master .          # build everything
#   scripts/build_and_sync.sh _master . 0 1      # only chapters 0 and 1
#
# Requires: python with `pyyaml`, `tabulate` (and `ruff` for formatting), rsync.

set -euo pipefail

MASTER_DIR="${1:?usage: build_and_sync.sh <master_repo_dir> <dest_dir> [chapters...]}"
DEST_DIR="${2:?usage: build_and_sync.sh <master_repo_dir> <dest_dir> [chapters...]}"
shift 2 || true

CHAPTERS=("$@")
if [ "${#CHAPTERS[@]}" -eq 0 ]; then
  CHAPTERS=(0 1 2 3 4)
fi

MASTER_DIR="$(cd "$MASTER_DIR" && pwd)"
DEST_DIR="$(cd "$DEST_DIR" && pwd)"

# Chapter directories that hold the runnable material.
CHAPTER_DIRS=(
  chapter0_fundamentals
  chapter1_transformer_interp
  chapter2_rl
  chapter3_llm_evals
  chapter4_alignment_science
)

# Top-level files needed to install & run ARENA (README is intentionally NOT
# synced — this repo keeps its own).
RUNTIME_FILES=(
  requirements.txt
  pyproject.toml
  install.sh
  style.css
  st_chat.py
  st_dependencies.py
  test.py
)

# Top-level directories needed at runtime.
RUNTIME_DIRS=(
  .streamlit
  .devcontainer
)

echo "==> master = $MASTER_DIR"
echo "==> dest   = $DEST_DIR"
echo "==> chapters = ${CHAPTERS[*]}"

# The conversion tool writes the Streamlit pages into instructions/pages/ but
# does not create that directory itself, so make sure it exists.
echo "==> Ensuring instructions/pages/ directories exist"
for ch in "${CHAPTER_DIRS[@]}"; do
  [ -d "$MASTER_DIR/$ch" ] && mkdir -p "$MASTER_DIR/$ch/instructions/pages"
done

echo "==> Building notebooks from master files"
pushd "$MASTER_DIR/infrastructure/core" >/dev/null
for ch in "${CHAPTERS[@]}"; do
  echo "--- building chapter ${ch}.* ---"
  # ruff_format is left false on purpose: it's a cosmetic reformat of the
  # generated .py files, it requires ruff, and a failure in it aborts the
  # section *after* outputs are written, skipping the import post-processing
  # for split-solution sections. Skipping it gives a clean, complete build.
  python main.py \
    --chapters="${ch}.*" \
    --use_py=true \
    --generate_files=true \
    --overwrite=true \
    --verbose=false \
    --ruff_format=false
done
popd >/dev/null

# Mirror ONLY the chapters we actually built. Mirroring a chapter we didn't
# build would `--delete` its generated output in dest (it's absent from the
# fresh master checkout). CHAPTER_DIRS is indexed by chapter number (0-4).
echo "==> Syncing runnable material into $DEST_DIR"
for ch in "${CHAPTERS[@]}"; do
  dir="${CHAPTER_DIRS[$ch]:-}"
  if [ -n "$dir" ] && [ -d "$MASTER_DIR/$dir" ]; then
    rsync -a --delete \
      --exclude='__pycache__/' \
      --exclude='*.pyc' \
      --exclude='.ipynb_checkpoints/' \
      "$MASTER_DIR/$dir/" "$DEST_DIR/$dir/"
  fi
done

for f in "${RUNTIME_FILES[@]}"; do
  [ -f "$MASTER_DIR/$f" ] && cp -f "$MASTER_DIR/$f" "$DEST_DIR/$f"
done

for d in "${RUNTIME_DIRS[@]}"; do
  [ -d "$MASTER_DIR/$d" ] && rsync -a --delete "$MASTER_DIR/$d/" "$DEST_DIR/$d/"
done

echo "==> Done."

#!/usr/bin/env bash
#
# Incremental build: rebuild ONLY the sections whose master files changed between
# two commits of the master repo, and sync ONLY the affected files into the
# destination repo.
#
# Usage:
#   scripts/incremental_build.sh <master_dir> <dest_dir> <before_sha> <after_sha>
#
# How changed paths are classified (generated outputs are never committed in the
# master repo, so a master diff only ever contains *source* files):
#   infrastructure/chapters/**/master_X_Y.{py,ipynb}  -> rebuild section X.Y
#   infrastructure/core/**                            -> GLOBAL change (full rebuild)
#   chapterN_*/**                                     -> support file: copy/delete as-is
#   requirements.txt, install.sh, .streamlit/**, ...  -> runtime file: copy/delete
#   anything else (README, infrastructure/archive, …) -> ignored
#
# Exit codes:
#   0  -> incremental build completed (or nothing relevant changed)
#   10 -> a global change was detected, or the diff could not be computed;
#         the caller should perform a FULL rebuild instead.

set -euo pipefail

MASTER_DIR="$(cd "${1:?usage: incremental_build.sh <master_dir> <dest_dir> <before> <after>}" && pwd)"
DEST_DIR="$(cd "${2:?usage: incremental_build.sh <master_dir> <dest_dir> <before> <after>}" && pwd)"
BEFORE="${3:-}"
AFTER="${4:-}"

ZERO="0000000000000000000000000000000000000000"

# Need a usable before..after range, otherwise ask the caller for a full rebuild.
if [ -z "$BEFORE" ] || [ -z "$AFTER" ] || [ "$BEFORE" = "$ZERO" ]; then
  echo "No usable before/after range -> full rebuild needed."
  exit 10
fi
if ! git -C "$MASTER_DIR" cat-file -e "${BEFORE}^{commit}" 2>/dev/null; then
  echo "Before commit '$BEFORE' not reachable -> full rebuild needed."
  exit 10
fi

CHAPTER_DIRS=(
  chapter0_fundamentals
  chapter1_transformer_interp
  chapter2_rl
  chapter3_llm_evals
  chapter4_alignment_science
)
RUNTIME_FILES=" requirements.txt pyproject.toml install.sh style.css st_chat.py st_dependencies.py test.py "

is_chapter_path() {
  case "$1" in
    chapter0_fundamentals/*|chapter1_transformer_interp/*|chapter2_rl/*|chapter3_llm_evals/*|chapter4_alignment_science/*) return 0 ;;
    *) return 1 ;;
  esac
}
is_runtime_path() {
  case "$1" in
    .streamlit/*|.devcontainer/*) return 0 ;;
    *) [[ "$RUNTIME_FILES" == *" $1 "* ]] ;;
  esac
}

declare -A SECTIONS=()   # section ids to (re)build, e.g. SECTIONS[1.3.2]=1
COPY=()                  # source files to copy verbatim into dest
DELETE=()                # files to delete from dest

# Read the change list (no renames -> each entry is "status<TAB>path").
while IFS=$'\t' read -r status path; do
  [ -z "${status:-}" ] && continue

  # A master source file -> rebuild that section.
  case "$path" in
    infrastructure/chapters/*/master_*.py|infrastructure/chapters/*/master_*.ipynb)
      base="$(basename "$path")"      # master_1_3_2.py
      name="${base%.*}"               # master_1_3_2
      id="${name#master_}"            # 1_3_2
      id="${id//_/.}"                 # 1.3.2
      if [[ "$status" != D* ]]; then
        SECTIONS["$id"]=1
      fi
      continue
      ;;
  esac

  # The conversion tool or its config changed -> everything may be affected.
  case "$path" in
    infrastructure/core/*)
      echo "Global change detected ($path) -> full rebuild needed."
      exit 10
      ;;
  esac

  # Hand-written support file or runtime file -> sync it directly.
  if is_chapter_path "$path" || is_runtime_path "$path"; then
    if [[ "$status" == D* ]]; then
      DELETE+=("$path")
    else
      COPY+=("$path")
    fi
  fi
  # Anything else (README, infrastructure/archive, …) is ignored.
done < <(git -C "$MASTER_DIR" diff --name-status --no-renames "$BEFORE" "$AFTER")

if [ "${#SECTIONS[@]}" -eq 0 ] && [ "${#COPY[@]}" -eq 0 ] && [ "${#DELETE[@]}" -eq 0 ]; then
  echo "No runnable material changed in ${BEFORE:0:7}..${AFTER:0:7} — nothing to do."
  exit 0
fi

# --- Build the changed sections -------------------------------------------------
if [ "${#SECTIONS[@]}" -gt 0 ]; then
  echo "==> Rebuilding sections: ${!SECTIONS[*]}"

  # Snapshot untracked files *before* building, so afterwards we can copy ONLY
  # the files this build newly created (not any stray files already present).
  declare -A PRE_UNTRACKED=()
  while IFS= read -r -d '' f; do PRE_UNTRACKED["$f"]=1; done \
    < <(git -C "$MASTER_DIR" ls-files --others -z)

  for ch in "${CHAPTER_DIRS[@]}"; do
    [ -d "$MASTER_DIR/$ch" ] && mkdir -p "$MASTER_DIR/$ch/instructions/pages"
  done
  pushd "$MASTER_DIR/infrastructure/core" >/dev/null
  for id in "${!SECTIONS[@]}"; do
    echo "--- building section $id ---"
    python main.py \
      --chapters="$id" \
      --use_py=true \
      --generate_files=true \
      --overwrite=true \
      --verbose=false \
      --ruff_format=false
  done
  popd >/dev/null

  # Copy the files that appeared during the build (the generated output) into
  # dest. Generated output is never committed in master, so it shows up as new
  # untracked files under a chapter dir.
  echo "==> Copying generated output into $DEST_DIR"
  while IFS= read -r -d '' f; do
    [ -n "${PRE_UNTRACKED[$f]:-}" ] && continue       # already there before build
    case "$f" in
      */__pycache__/*|*.pyc) continue ;;
    esac
    if is_chapter_path "$f"; then
      mkdir -p "$DEST_DIR/$(dirname "$f")"
      cp -f "$MASTER_DIR/$f" "$DEST_DIR/$f"
      echo "  generated: $f"
    fi
  done < <(git -C "$MASTER_DIR" ls-files --others -z)
fi

# --- Sync directly-changed support / runtime files ------------------------------
for f in "${COPY[@]}"; do
  if [ -f "$MASTER_DIR/$f" ]; then
    mkdir -p "$DEST_DIR/$(dirname "$f")"
    cp -f "$MASTER_DIR/$f" "$DEST_DIR/$f"
    echo "  synced: $f"
  fi
done
for f in "${DELETE[@]}"; do
  if [ -e "$DEST_DIR/$f" ]; then
    rm -f "$DEST_DIR/$f"
    echo "  deleted: $f"
  fi
done

echo "==> Incremental build done."

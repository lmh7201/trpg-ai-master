#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# dnd_reference_ko 저장소에서 캐릭터 생성용 JSON 데이터를 가져온다.
# 이미 존재하면 pull, 없으면 shallow clone.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="https://github.com/lmh7201/dnd_reference_ko.git"
CLONE_DIR="/tmp/dnd_reference_ko"
SRC_DIR="dnd_korean/dnd-reference/src/data"
DEST_DIR="priv/data"

# 복사할 파일 목록
FILES=(
  classes.json
  races.json
  backgrounds.json
  feats.json
  spells.json
  classFeatures.json
  subclasses.json
  subclassFeatures.json
  weapons.json
  armor.json
  adventuringGear.json
  tools.json
)

echo "📦 dnd_reference_ko 데이터 동기화 시작..."

# 1) Clone 또는 Pull
if [ -d "$CLONE_DIR/.git" ]; then
  echo "  ↻ 기존 clone 업데이트 중..."
  git -C "$CLONE_DIR" pull --ff-only --quiet 2>/dev/null || true
else
  echo "  ⬇ 저장소 clone 중 (shallow)..."
  rm -rf "$CLONE_DIR"
  git clone --depth 1 --quiet "$REPO_URL" "$CLONE_DIR"
fi

# 2) 대상 디렉토리 준비
mkdir -p "$DEST_DIR"

# 3) 파일 복사
copied=0
for file in "${FILES[@]}"; do
  src="$CLONE_DIR/$SRC_DIR/$file"
  if [ -f "$src" ]; then
    cp "$src" "$DEST_DIR/$file"
    ((copied++))
  else
    echo "  ⚠ 파일 없음: $file"
  fi
done

echo "✅ 완료: ${copied}/${#FILES[@]}개 파일 → $DEST_DIR/"

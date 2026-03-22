#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# dnd_reference_ko 저장소에서 캐릭터 생성용 JSON 데이터를 가져온다.
# private 저장소이므로 로컬/CI에서 실행 (Docker 빌드 전에 사용).
#
# 사용법:
#   bash scripts/sync_dnd_data.sh              # 기본 (git clone)
#   GITHUB_TOKEN=xxx bash scripts/sync_dnd_data.sh  # CI 환경 (토큰 인증)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="lmh7201/dnd_reference_ko"
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

# Clone URL 결정 (GITHUB_TOKEN이 있으면 HTTPS 토큰 인증, 없으면 SSH)
if [ -n "${GITHUB_TOKEN:-}" ]; then
  REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO}.git"
  echo "  🔑 GITHUB_TOKEN으로 HTTPS 인증"
else
  REPO_URL="git@github.com:${REPO}.git"
  echo "  🔑 SSH 키 인증"
fi

# Clone 또는 Pull
if [ -d "$CLONE_DIR/.git" ]; then
  echo "  ↻ 기존 clone 업데이트 중..."
  git -C "$CLONE_DIR" pull --ff-only --quiet 2>/dev/null || {
    echo "  ⚠ pull 실패, 재clone..."
    rm -rf "$CLONE_DIR"
    git clone --depth 1 --quiet "$REPO_URL" "$CLONE_DIR"
  }
else
  echo "  ⬇ 저장소 clone 중 (shallow)..."
  rm -rf "$CLONE_DIR"
  git clone --depth 1 --quiet "$REPO_URL" "$CLONE_DIR"
fi

# 대상 디렉토리 준비
mkdir -p "$DEST_DIR"

# 파일 복사
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

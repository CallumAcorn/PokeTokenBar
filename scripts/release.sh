#!/usr/bin/env bash
#
# release.sh — 버전 배포 자동화 + 문서(README/웹페이지/cask) 일관성 검토.
#
# 사용:
#   PTB_NOTES_FILE=/tmp/notes.md ./scripts/release.sh 2.1.1
#   ./scripts/release.sh 2.1.1            # 노트 파일 없으면 최소 노트
#   ./scripts/release.sh --check-only     # 문서 일관성 검토만(배포 안 함)
#
# 단계: 1)test-gate 2)문서 검토 3)VERSION 범프 4)build+zip 5)커밋·push
#       6)GitHub Release 7)Homebrew cask 8)Pages 재빌드. 각 단계 실패 시 즉시 중단(set -e).
#
set -euo pipefail
cd "$(dirname "$0")/.."

# 포크 기본값. 업스트림으로 배포하려면 환경변수로 덮어쓴다.
REPO="${PTB_REPO:-CallumAcorn/PokeTokenBar}"
TAP_REPO="${PTB_TAP_REPO:-CallumAcorn/homebrew-tap}"
CASK_PATH="Casks/poke-token-bar-hardened.rb"
# 에셋 게이트 면제 기록. 버전을 명시한 줄만 유효하다(= 다음 릴리스에 자동 만료).
WAIVERS="docs/reference/asset-waivers.md"

# ── 문서 일관성 검토 (배포 전 항상 실행) ───────────────────────────────────
# 기계적으로 잡을 수 있는 것만 자동 경고. 내용(기능 설명) 변경 여부는 사람이 체크리스트로 판단.
doc_check() {
  local warn=0
  echo "▶ 문서 일관성 검토"
  # 정적 버전 하드코딩(릴리스마다 수동 갱신 필요 → 동적 배지 권장)
  if grep -rnE "img.shields.io/badge/release-v[0-9]" README*.md 2>/dev/null; then
    echo "  ⚠ README 에 정적 버전 배지가 있습니다(동적 github/v/release 배지 권장)."; warn=1
  fi
  # 제거된 의존성/도구 흔적 (필요 시 PATTERN 에 추가)
  for pat in ccusage; do
    if grep -rniq "$pat" README*.md 2>/dev/null; then
      echo "  ⚠ README 에 '$pat' 잔존 — 제거된 항목인지 확인."; warn=1
    fi
  done
  # UI 변경 → 스크린샷 staleness (실제 diff 상태 검증 — 수동 체크리스트가 통과의례로 묻히지 않게).
  # 직전 릴리스 태그 이후 UI 소스가 바뀌었는데 assets 스크린샷이 안 바뀌었으면 README 이미지 stale 가능.
  local last_tag ui_changed shot_changed
  last_tag=$(git describe --tags --match "v*" --abbrev=0 2>/dev/null || echo "")
  if [[ -n "$last_tag" ]]; then
    ui_changed=$(git diff --name-only "$last_tag"..HEAD -- 'Sources/PokeTokenBar/UI/' 2>/dev/null)
    shot_changed=$(git diff --name-only "$last_tag"..HEAD -- 'assets/settings*' 'assets/screenshot*' 'assets/menubar*' 'assets/shiny*' 2>/dev/null)
    if [[ -n "$ui_changed" && -z "$shot_changed" ]]; then
      echo "  ⚠ UI 소스가 $last_tag 이후 변경됐으나 스크린샷(assets/) 갱신 없음 — README 이미지 stale 가능:"
      echo "$ui_changed" | sed 's/^/       /'
      echo "     → 변경된 화면이면 assets 스크린샷 재생성 (README.md/ko/ja 각 언어)."
      warn=1
    fi

    # UI 표면이 바뀌었는데 **신규** 에셋이 없다 → 하드 게이트.
    #
    # 판정 기준이 커밋 메시지였을 때 이 게이트는 세 번 연속 헛돌았다: moves/TM, battles, gym badges 는
    # 전부 새 화면인데 커밋 제목이 `feat:` 이 아니라 조용히 통과했고, 정작 처음 걸린 건 업스트림에서
    # 체리픽한 설정 드롭다운(#212)이었다 — 상류가 conventional commits 를 쓴다는 이유만으로. 기여자의
    # 커밋 관례는 우리가 정할 수 없으니 **무엇이 바뀌었는가**(UI 소스 diff)로 판정한다.
    local new_assets waiver
    new_assets=$(git diff --name-only --diff-filter=A "$last_tag"..HEAD -- 'assets/' 2>/dev/null)
    # 면제는 기록으로만 — 커밋 타입을 바꾸는 우회는 이미 푸시된 커밋에선 히스토리 재작성이라 불가능하고
    # (hardened.5 에서 실제로 막혔다), 무엇보다 판단이 커밋 제목 안에 숨는다. 대신 **이번 버전을 적은**
    # 한 줄을 남긴다: 버전이 박혀 있으니 다음 릴리스에는 자동으로 만료되어 영구 우회로 굳지 않는다.
    # --check-only 는 VERSION 설정 **전에** 이 함수를 부른다(set -u 라 참조만으로 죽는다).
    # 그때는 면제를 조회할 대상 버전이 없으므로 항상 "면제 없음"으로 본다 = 게이트를 보여준다.
    waiver=""
    if [[ -n "${VERSION:-}" ]]; then
      waiver=$(grep -F "\`${VERSION}\`" "$WAIVERS" 2>/dev/null | grep -E "^\|" || true)
    fi
    if [[ -n "$ui_changed" && -z "$new_assets" ]]; then
      if [[ -n "$waiver" ]]; then
        echo "  ⚠ 에셋 게이트 면제 (기록됨 — $WAIVERS):"
        echo "$waiver" | sed 's/^/       /'
        warn=1
      else
        echo "  ✗ UI 소스가 $last_tag 이후 바뀌었는데 assets/ 에 **새로 추가된** 파일이 없습니다:"
        echo "$ui_changed" | sed 's/^/       /'
        echo "     → 새 화면·새 표면이면 전용 스크린샷을 만들어 README(ko/ja 포함)에 넣으세요."
        echo "     → 이번 릴리스엔 불필요하다고 판단했다면 $WAIVERS 에 이 버전으로 한 줄 남기세요:"
        echo "       | \`${VERSION:-<version>}\` | $(date +%F) | 사유 |"
        # 예외는 있지만 무기명이 아니다. 환경변수 우회구를 두지 않는 이유와 같다 — 그 변수는 습관이
        # 되지만, 버전이 박힌 기록은 다음 릴리스에 만료되고 리뷰에도 남는다.
        return 2
      fi
    fi
  fi
  cat <<'CHECK'
  ─ 수동 체크리스트 (내용 변경 시 갱신) ─────────────────────────────
   [ ] README.md / .ko / .ja : 기능 목록·요구사항·데이터소스·스크린샷
   [ ] 랜딩(gh-pages/index.html): hero·features·install·works-with·요구사항·푸터
       · 버전 배지는 동적(github/v/release) → 자동. 기능/문구만 수동.
       · 3개 언어 i18n 사전(en/ko/ja) 동시 갱신 + 키 정합 유지.
   [ ] homebrew-tap cask: caveats(설치 요구사항) 최신 상태인지
  ─────────────────────────────────────────────────────────────────
CHECK
  return $warn
}

if [[ "${1:-}" == "--check-only" ]]; then
  doc_check || true
  exit 0
fi

VERSION="${1:?사용: release.sh <version>  (예: 2.1.1)}"
# 포크 버전 형식: MAJOR.MINOR.PATCH 뒤에 선택적으로 -hardened.N.
# 접미사가 있는 이유: 업스트림과 이 포크가 **같은 버전 문자열로 다른 코드**를 내보내던 상태였다
# (둘 다 2.5.1 인데 업스트림은 자체 2.5.2 를 릴리스). 접미사가 둘을 영구히 구분한다.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-hardened\.[0-9]+)?$ ]] || { echo "✗ 버전 형식 오류: $VERSION (예: 2.5.1-hardened.2)"; exit 1; }
PREV=$(grep -oE 'VERSION="[^"]+"' scripts/build-app.sh | head -1 | sed -E 's/VERSION="([^"]+)"/\1/')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || { echo "✗ main 브랜치에서 실행하세요 (현재: $BRANCH) — 커밋/push 대상 일치 보장"; exit 1; }
echo "=== PokeTokenBar 릴리스 $PREV → $VERSION ==="

echo "▶ 1/8 릴리스 전 테스트 게이트"
./scripts/test-gate.sh >/dev/null || { echo "✗ test-gate 실패 — 중단"; exit 1; }
echo "  ✓ 통과"

# set -e 하에서 `doc_check; rc=$?` 는 실패 즉시 종료돼 rc 를 못 읽는다.
doc_rc=0; doc_check || doc_rc=$?
if [[ $doc_rc -eq 2 ]]; then
  echo "중단 — 새 기능에 필요한 에셋을 먼저 만드세요(프롬프트로 넘길 수 없는 게이트)."
  exit 1
elif [[ $doc_rc -ne 0 ]]; then
  read -r -p "  문서 경고가 있습니다. 그래도 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 문서 먼저 갱신하세요."; exit 1; }
fi

# 코드서명 신원 게이트는 여기 없다 — 이 포크는 **바이너리를 배포하지 않는다**.
# 그 게이트의 목적은 "배포된 .app 이 매 업그레이드마다 사용자 Keychain 승인을 깨지 않게" 하는 것인데,
# 사용자가 각자 로컬에서 빌드하면 서명은 그 사람 기계의 문제이고 릴리스와 무관하다.
# 바이너리 배포로 돌아간다면 게이트와 EXPECTED_LEAF 핀을 함께 되살려야 한다.

echo "▶ 3/8 VERSION 범프 $PREV → $VERSION (아직 미커밋)"
# 치환 정규식은 접미사까지 잡아야 한다. `[0-9.]+` 는 2.5.1 은 잡지만 2.5.1-hardened.1 은 못 잡아
# 조용히 no-op 이 되고, 그 상태로 빌드까지 간 뒤에야 버전 불일치로 죽는다(실측 2026-08-25).
perl -pi -e "s/VERSION=\"[0-9][^\"]*\"/VERSION=\"$VERSION\"/" scripts/build-app.sh
BUMPED=$(grep -oE 'VERSION="[^"]+"' scripts/build-app.sh | head -1 | sed -E 's/VERSION="([^"]+)"/\1/')
[[ "$BUMPED" == "$VERSION" ]] || { echo "✗ VERSION 치환 실패: build-app.sh 가 아직 $BUMPED — 정규식이 이 버전 형식을 못 잡았습니다"; git checkout scripts/build-app.sh; exit 1; }

echo "▶ 4/6 빌드 검증 (배포물 아님 — 태그가 실제로 빌드되는지 확인)"
# 설치는 하지 않는다. 확인용 빌드가 실행 중인 앱을 죽이고 /Applications 를 교체하면, 릴리스를
# 끊는 것만으로 사용자의 메뉴바 앱이 사라진다(실측). 검증은 build/ 안에서 끝낸다.
PTB_NO_INSTALL=1 ./scripts/build-app.sh >/dev/null
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PokeTokenBar.app/Contents/Info.plist)
[[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT (수동 복구: git checkout scripts/build-app.sh)"; exit 1; }
[[ -f build/PokeTokenBar.app/Contents/Resources/LICENSE ]] || { echo "✗ 번들에 LICENSE 가 없습니다 — MIT 고지 요구사항"; exit 1; }
echo "  ✓ $VERSION 빌드 성공"

echo "▶ 5/6 커밋 + push"
git add scripts/build-app.sh
# 이미 대상 버전이면 스테이지할 게 없다. `git commit` 은 그때 exit 1 이고 `set -e` 아래에서는
# **빌드는 끝났는데 태그는 안 만들어진** 중간 상태로 릴리스가 죽는다. 범프가 있을 때만 커밋한다.
if git diff --cached --quiet; then
  echo "  (VERSION 이 이미 $VERSION — 커밋할 범프 없음)"
else
  git commit -q -m "release: bump version to $VERSION

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
fi
git push -q origin main

echo "▶ 6/6 GitHub Release v$VERSION (태그 전용 — 첨부 바이너리 없음)"
# 바이너리를 붙이지 않는 이유: Apple Developer ID 가 없어 내려받은 .app 은 자체서명·미공증이고,
# 사용자가 Gatekeeper 를 손으로 우회해야 한다 — 이 포크가 업스트림 cask 에서 없앤 바로 그 패턴이다.
# 릴리스는 버전 표식 + 노트이고, 설치는 각자 소스에서 빌드한다(UpdateChecker 가 그 안내를 띄운다).
NOTES_FILE="${PTB_NOTES_FILE:-}"
if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  gh release create "v$VERSION" --repo "$REPO" --title "PokeTokenBar v$VERSION" --target main --notes-file "$NOTES_FILE"
else
  gh release create "v$VERSION" --repo "$REPO" --title "PokeTokenBar v$VERSION" --target main --notes "Release v$VERSION

Build from source to update:

    cd ~/Code/PokeTokenBar
    git pull
    ./scripts/build-app.sh

No binary is attached: without Apple notarisation a downloaded build is blocked by Gatekeeper. See INSTALL.md."
fi

echo "✓ v$VERSION 태그 릴리스 완료. 사용자는 git pull + ./scripts/build-app.sh 로 갱신합니다."

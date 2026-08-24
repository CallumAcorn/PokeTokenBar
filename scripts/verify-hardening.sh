#!/usr/bin/env bash
#
# verify-hardening.sh — 이 포크가 약속한 보안 속성이 **실제 빌드 산출물에** 붙어 있는지 검사한다.
#
# build-app.sh 와 달리 /Applications 에 설치하지 않는다. build/verify 안에서만 조립·서명하고 검사한 뒤
# 정리한다. CI 와 로컬 양쪽에서 돌릴 수 있고, 서명 옵션이 조용히 빠지는 회귀를 잡는 것이 목적이다.
#
# 사용:  ./scripts/verify-hardening.sh
#
# 주의: `set -e` 는 일부러 쓰지 않는다. 이 스크립트는 "실패하는 검사"가 정상 흐름이라,
#       -e 아래에서는 첫 미스매치에서 조용히 죽어 나머지 항목을 아예 보고하지 못한다.
#       `pipefail` 도 쓰지 않는다 — `cmd | grep -q` 는 매치 즉시 파이프를 닫아 앞 명령에 SIGPIPE 를
#       주고, pipefail 아래에서는 그 실패가 파이프라인 상태가 돼 **통과한 검사가 실패로** 보고된다.
set -u
cd "$(dirname "$0")/.."

APP="build/verify/PokeTokenBar.app"
fail=0

pass() { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1" >&2; fail=1; }

# expect <설명> <셸 표현식…>  — 표현식이 성공(0)해야 통과.
expect() { local d="$1"; shift; if eval "$*" >/dev/null 2>&1; then pass "$d"; else bad "$d"; fi; }
# refute <설명> <셸 표현식…>  — 표현식이 실패(≠0)해야 통과.
refute() { local d="$1"; shift; if eval "$*" >/dev/null 2>&1; then bad "$d"; else pass "$d"; fi; }

echo "==> release 빌드 + 번들 조립 (설치 없음)"
if ! swift build -c release >/dev/null; then echo "✗ release 빌드 실패" >&2; exit 1; fi
rm -rf build/verify
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp .build/release/PokeTokenBar "$APP/Contents/MacOS/PokeTokenBar"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# build-app.sh 가 만드는 것과 같은 plist 두 벌(내용 검사가 목적).
for variant in login autorestart; do
  keepalive=""
  [[ "$variant" == "autorestart" ]] && keepalive="<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>"
  cat > "$APP/Contents/Library/LaunchAgents/io.github.chattymin.poketokenbar.$variant.plist" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>Label</key><string>io.github.chattymin.poketokenbar.$variant</string>
<key>ProgramArguments</key><array><string>/Applications/PokeTokenBar.app/Contents/MacOS/PokeTokenBar</string></array>
<key>RunAtLoad</key><true/>$keepalive
</dict></plist>
AGENT
done

codesign --force --options runtime -s - "$APP" 2>/dev/null

echo "==> 서명 속성"
expect "서명 검증 통과" "codesign --verify --strict '$APP'"
expect "hardened runtime 플래그 (라이브러리 검증 활성)" "codesign -d --verbose=2 '$APP' 2>&1 | grep -q 'flags=.*runtime'"
refute "라이브러리 검증 비활성화 엔타이틀먼트 없음" "codesign -d --entitlements - '$APP' 2>&1 | grep -q 'disable-library-validation'"
refute "DYLD 환경변수 허용 엔타이틀먼트 없음" "codesign -d --entitlements - '$APP' 2>&1 | grep -q 'allow-dyld-environment-variables'"

echo "==> LaunchAgent"
refute "기본 로그인 에이전트에 KeepAlive 없음" "grep -q KeepAlive '$APP/Contents/Library/LaunchAgents/io.github.chattymin.poketokenbar.login.plist'"
expect "자동 재시작 에이전트에는 KeepAlive 있음" "grep -q KeepAlive '$APP/Contents/Library/LaunchAgents/io.github.chattymin.poketokenbar.autorestart.plist'"

echo "==> cask"
# 주석에 이 문자열들이 **설명으로** 등장하므로, 지시문만 잡도록 행 선두 기준으로 본다.
# (느슨한 grep 은 자기 문서를 위반으로 신고한다 — 실제로 그렇게 한 번 틀렸다.)
refute "cask 가 sha256 :no_check 를 쓰지 않음" "grep -qE '^[[:space:]]*sha256[[:space:]]+:no_check' packaging/Casks/*.rb"
refute "cask 가 quarantine 을 벗기지 않음(xattr 실행 없음)" "grep -qE '^[[:space:]]*(system_command|postflight|args:).*xattr' packaging/Casks/*.rb"
expect "cask 가 sha256 을 고정" "grep -qE '^[[:space:]]*sha256[[:space:]]+\"[0-9a-f]{64}\"' packaging/Casks/*.rb"

echo "==> 셸 함정 (pipefail + grep -q)"
# `set -o pipefail` 인 스크립트에서 `… | grep -q` 는 매치 즉시 파이프를 닫아 앞 명령에 SIGPIPE 를
# 주고, 그 실패가 파이프라인 종료코드가 된다 → **통과가 실패로 뒤집힌다.** build-app.sh 가 정확히
# 이걸로 하드닝 검사에 성공한 빌드를 실패로 보고하고 /Applications 설치를 건너뛰었다.
# 사람이 기억할 게 아니라 기계가 막아야 하는 부류라 여기서 전수 검사한다.
# 주석은 양쪽 판정에서 제외한다 — 이 파일 자체가 함정을 **설명**하느라 두 문자열을 다 담고 있어,
# 순진한 grep 은 자기 문서를 위반으로 신고한다(실제로 그렇게 한 번 틀렸다).
offenders=""
for f in scripts/*.sh; do
  grep -E '^[[:space:]]*set[[:space:]].*pipefail' "$f" >/dev/null 2>&1 || continue
  if grep -vE '^[[:space:]]*#' "$f" | grep -E '\|[[:space:]]*grep[^|]*[[:space:]]-[a-zA-Z]*q' >/dev/null 2>&1; then
    offenders="$offenders $f"
  fi
done
if [[ -z "$offenders" ]]; then
  pass "pipefail 스크립트에 'grep -q' 파이프 없음"
else
  bad "pipefail + grep -q 조합:$offenders (-q 를 빼고 >/dev/null 로 버리세요)"
fi

echo "==> 업데이트 출처 (이 포크여야 한다)"
# 업스트림 저장소를 업데이트 소스로 두면 "새 버전 있음" 배너의 Update 버튼이 **원본 프로젝트**를
# 설치한다 — 여기 있는 하드닝이 하나도 없는 다른 코드로 조용히 갈아치우는 것과 같다.
# cask 토큰도 마찬가지다: 업스트림과 같은 토큰이면 `brew upgrade --cask` 가 업스트림 설치를 잡는다.
refute "UpdateChecker 가 업스트림 저장소를 가리키지 않음" "grep -rn 'chattymin/PokeTokenBar' Sources/PokeTokenBar/Core/UpdateChecker.swift"
expect "UpdateChecker 가 이 포크를 가리킴" "grep -q 'CallumAcorn/PokeTokenBar' Sources/PokeTokenBar/Core/UpdateChecker.swift"
# 앱은 더 이상 brew 를 실행하지 않는다(태그 전용 릴리스 = 받을 바이너리가 없음).
# **주석 줄은 제외한다** — 왜 없앴는지 설명하는 주석에 그 문자열이 그대로 들어 있어서,
# 순진한 grep 은 자기 설명을 위반으로 신고한다(이 저장소에서 세 번째로 밟은 함정).
refute "앱이 brew 로 업그레이드를 실행하지 않음" "grep -rn 'upgrade --cask' Sources/ | grep -vE ':[[:space:]]*//'"
refute "cask 토큰이 업스트림과 겹치지 않음" "grep -qE '^[[:space:]]*cask \"poke-token-bar\"' packaging/Casks/*.rb"

echo "==> 라이선스 고지"
# MIT 는 "모든 사본"에 고지 포함을 요구한다. 소스만 배포할 땐 저장소의 LICENSE 로 충족되지만,
# .app 을 넘기는 순간 그 사본에는 고지가 없다. 번들에 들어가는지 기계로 확인한다.
expect "번들에 LICENSE 포함" "test -f '$APP/Contents/Resources/LICENSE'"
expect "build-app.sh 가 LICENSE 를 번들에 복사" "grep -q 'cp LICENSE' scripts/build-app.sh"

echo "==> 소스 불변식"
expect "build-app.sh 가 hardened runtime 으로 서명" "grep -q 'options runtime' scripts/build-app.sh"
# 이 포크는 태그 전용 릴리스만 낸다. 바이너리를 붙이는 순간 자체서명·미공증 .app 이 되어
# 사용자가 Gatekeeper 를 손으로 우회해야 한다 — 업스트림 cask 에서 없앤 바로 그 패턴이다.
# 바이너리 배포로 돌아간다면 SHA256SUMS·서명 게이트·EXPECTED_LEAF 핀을 함께 되살려야 한다.
refute "release.sh 가 릴리스에 바이너리를 첨부하지 않음" "grep -qE 'ditto -c -k|release (create|upload).*\.zip' scripts/release.sh"
refute "워크플로 액션이 전부 커밋 SHA 로 고정" "grep -rnE 'uses: .*@(v[0-9]+|main|master)\$' .github/workflows/"

rm -rf build/verify
echo
if [[ "$fail" -eq 0 ]]; then
  echo "✓ 하드닝 검사 전부 통과"
else
  echo "✗ 하드닝 검사 실패 — 위 항목을 확인하세요." >&2
  exit 1
fi

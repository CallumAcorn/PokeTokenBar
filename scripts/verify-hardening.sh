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
refute "cask 가 sha256 :no_check 를 쓰지 않음" "grep -qE '^[[:space:]]*sha256[[:space:]]+:no_check' packaging/Casks/poke-token-bar.rb"
refute "cask 가 quarantine 을 벗기지 않음(xattr 실행 없음)" "grep -qE '^[[:space:]]*(system_command|postflight|args:).*xattr' packaging/Casks/poke-token-bar.rb"
expect "cask 가 sha256 을 고정" "grep -qE '^[[:space:]]*sha256[[:space:]]+\"[0-9a-f]{64}\"' packaging/Casks/poke-token-bar.rb"

echo "==> 소스 불변식"
expect "build-app.sh 가 hardened runtime 으로 서명" "grep -q 'options runtime' scripts/build-app.sh"
expect "release.sh 가 SHA256 을 산출" "grep -q 'shasum -a 256' scripts/release.sh"
refute "워크플로 액션이 전부 커밋 SHA 로 고정" "grep -rnE 'uses: .*@(v[0-9]+|main|master)\$' .github/workflows/"

rm -rf build/verify
echo
if [[ "$fail" -eq 0 ]]; then
  echo "✓ 하드닝 검사 전부 통과"
else
  echo "✗ 하드닝 검사 실패 — 위 항목을 확인하세요." >&2
  exit 1
fi

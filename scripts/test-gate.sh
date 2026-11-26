#!/usr/bin/env bash
#
# test-gate.sh — 안정성 가드레일. 커밋/머지 전 수동 실행 (1인 로컬, CI 없음).
#
#   1) swift test 전체 통과
#   2) "로직 코어" 파일 집합의 라인 커버리지 >= THRESHOLD
#
# 로직 코어 = 결정적으로 단위 테스트 가능한 파일만 포함. ProcessRunner / PokeAPIClient /
# CcusageProvider / CodexRateLimitsProvider / OAuthLimitsProvider / UpdateChecker /
# BinaryLocator 는 실제 서브프로세스·네트워크·Keychain 의존이라 단위 커버리지 대상에서 제외
# (해당 부분은 파서/순수 헬퍼만 별도로 테스트됨).
#
# 사용:  ./scripts/test-gate.sh          # 게이트 실행
#        THRESHOLD=75 ./scripts/test-gate.sh   # 임계값 임시 상향
#
set -euo pipefail
cd "$(dirname "$0")/.."

THRESHOLD="${THRESHOLD:-75}"

LOGIC_CORE=(
  "Sources/PokeTokenBar/Core/CompanionModel.swift"
  "Sources/PokeTokenBar/Core/CompanionStore.swift"
  "Sources/PokeTokenBar/Core/PokemonForm.swift"
  "Sources/PokeTokenBar/Core/CollectionWeight.swift"
  "Sources/PokeTokenBar/Core/UsageStore.swift"
  "Sources/PokeTokenBar/Core/Models.swift"
  "Sources/PokeTokenBar/Core/TokenFormatter.swift"
  "Sources/PokeTokenBar/Core/UsageProvider.swift"
  "Sources/PokeTokenBar/Core/LocalUsageReader.swift"
  "Sources/PokeTokenBar/Core/LocalUsageCache.swift"
  "Sources/PokeTokenBar/Core/ModelPricing.swift"
  "Sources/PokeTokenBar/Core/CustomScanRoots.swift"
  "Sources/PokeTokenBar/Core/CompetitiveDex.swift"
  "Sources/PokeTokenBar/Core/DayCare.swift"
  "Sources/PokeTokenBar/Core/UsageRecap.swift"
)

echo "▶ swift test (--enable-code-coverage)"
swift test --enable-code-coverage

# Ask SwiftPM where this run's products are. `find .build ... | head -1` picked up binaries left
# behind by an older toolchain's layout (.build/arm64-apple-macosx/debug) after newer SwiftPM moved
# products to .build/out/Products, so the gate scored a months-old build (61% against a real 80%+).
CODECOV_JSON=$(swift test --show-codecov-path 2>/dev/null | tail -1)
PROF="$(dirname "$CODECOV_JSON")/default.profdata"
BIN_DIR=$(swift build --show-bin-path 2>/dev/null | tail -1)
BIN=""
# The test bundle is named after the package (older SwiftPM) or the test target (newer).
for name in PokeTokenBarPackageTests PokeTokenBarTests; do
  candidate="$BIN_DIR/$name.xctest/Contents/MacOS/$name"
  if [[ -f "$candidate" ]]; then BIN="$candidate"; break; fi
done
[[ -f "$PROF" ]] || PROF=""
if [[ -z "$PROF" || -z "$BIN" ]]; then
  echo "✗ 커버리지 산출물(profdata/binary)을 찾지 못했습니다." >&2
  exit 1
fi

echo
echo "▶ 로직 코어 커버리지 (임계값 ${THRESHOLD}%)"
# Line coverage is summed from llvm-cov's JSON export over exactly the logic-core files. The
# previous `llvm-cov report BIN <files>` relied on positional file filters, which newer llvm-cov
# ignores: it then reported every file (UI and tests included) and the gate compared an unrelated
# total. Matching by path suffix works whether the tool records absolute or relative paths.
COVER=$(xcrun llvm-cov export "$BIN" -instr-profile="$PROF" -summary-only 2>/dev/null \
  | python3 -c '
import json, sys
core = sys.argv[1:]
files = json.load(sys.stdin)["data"][0]["files"]
total = covered = 0
missing = []
for want in core:
    hit = [f for f in files if f["filename"] == want or f["filename"].endswith("/" + want)]
    if not hit:
        missing.append(want)
        continue
    lines = hit[0]["summary"]["lines"]
    total += lines["count"]; covered += lines["covered"]
    sys.stderr.write("  %6.2f%%  %s\n" % (lines["percent"], want))
# A core file absent from the data means a stale or wrong binary: refuse to produce a number.
if missing or total == 0:
    sys.stderr.write("missing from coverage data: %s\n" % ", ".join(missing))
    sys.exit(1)
print("%.2f" % (100.0 * covered / total))
' "${LOGIC_CORE[@]}") || COVER=""
if [[ -z "$COVER" ]]; then
  echo "✗ 커버리지 산출 실패 (binary: $BIN) — 로직 코어 파일이 커버리지 데이터에 없습니다." >&2
  exit 1
fi

echo
# 소수 비교는 awk 로 (bash 정수 비교 회피)
if awk "BEGIN { exit !($COVER >= $THRESHOLD) }"; then
  echo "✓ 게이트 통과 — 로직 코어 라인 커버리지 ${COVER}% >= ${THRESHOLD}%"
else
  echo "✗ 게이트 실패 — 로직 코어 라인 커버리지 ${COVER}% < ${THRESHOLD}%" >&2
  echo "  테스트를 보강하거나, 의도된 하락이면 THRESHOLD 를 조정하세요." >&2
  exit 1
fi

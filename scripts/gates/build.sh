# gates/build.sh — 빌드 아티팩트 존재 검증, Dockerfile 빌드 검증

# ─── artifact-check: 빌드 아티팩트 존재 + 크기 검증 ───

cmd_artifact_check() {
  echo "=== Artifact Check ==="
  require_jq

  local artifact_found=false
  local artifact_path=""
  local artifact_type=""

  # 프로젝트 유형별 아티팩트 확인
  if [[ -f "package.json" ]]; then
    artifact_type="web"
    for d in dist build .next out; do
      if [[ -d "$d" ]]; then
        # 빈 디렉토리 체크
        local file_count
        file_count=$(find "$d" -type f 2>/dev/null | head -5 | wc -l)
        if [[ "$file_count" -gt 0 ]]; then
          artifact_found=true
          artifact_path="$d"
          break
        fi
      fi
    done
  elif [[ -f "pubspec.yaml" ]]; then
    artifact_type="flutter"
    if [[ -d "build/app/outputs" ]]; then
      local file_count
      file_count=$(find "build/app/outputs" -type f 2>/dev/null | head -5 | wc -l)
      if [[ "$file_count" -gt 0 ]]; then
        artifact_found=true
        artifact_path="build/app/outputs"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    artifact_type="go"
    # Go 바이너리: go.mod의 module 이름으로 추정
    local mod_name
    mod_name=$(head -1 go.mod | awk '{print $2}' | xargs basename 2>/dev/null || echo "")
    if [[ -n "$mod_name" ]] && [[ -f "$mod_name" ]]; then
      artifact_found=true
      artifact_path="$mod_name"
    fi
  elif [[ -f "Cargo.toml" ]]; then
    artifact_type="rust"
    if [[ -d "target/release" ]] || [[ -d "target/debug" ]]; then
      artifact_found=true
      artifact_path="target/"
    fi
  fi

  # verification.json에 기록
  local ts
  ts=$(timestamp)
  local result
  if [[ "$artifact_found" == "true" ]]; then
    result="pass"
    echo "[artifact-check] PASS ($artifact_type: $artifact_path)"
  else
    result="soft_fail"
    if [[ -n "$artifact_type" ]]; then
      echo "[artifact-check] SOFT_FAIL ($artifact_type: no build artifact found)"
    else
      echo "[artifact-check] SKIP (unknown project type)"
      result="skip"
    fi
  fi

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --arg type "$artifact_type" --arg path "$artifact_path" --arg result "$result" \
      '.artifactCheck = {"timestamp": $ts, "projectType": $type, "artifactPath": $path, "result": $result}'
  else
    jq -n --arg ts "$ts" --arg type "$artifact_type" --arg path "$artifact_path" --arg result "$result" \
      '{"artifactCheck": {"timestamp": $ts, "projectType": $type, "artifactPath": $path, "result": $result}}' > "$VERIFICATION_FILE"
  fi

  echo "=== ARTIFACT CHECK: ${result^^} ==="
  if [[ "$result" == "soft_fail" ]]; then
    return 1
  fi
  return 0
}

# ─── docker-build-check: Dockerfile 빌드 검증 ───

cmd_docker_build_check() {
  echo "=== Docker Build Check ==="

  local dockerfile=""
  for candidate in "Dockerfile" "docker/Dockerfile" "Dockerfile.dev"; do
    [[ -f "$candidate" ]] && { dockerfile="$candidate"; break; }
  done

  if [[ -z "$dockerfile" ]]; then
    echo "[docker-build-check] SKIP (no Dockerfile found)"
    append_gate_history "docker-build-check" "skip" '{"reason":"no Dockerfile"}'
    return 0
  fi

  echo "[docker-build-check] Found: $dockerfile"

  # Dockerfile 기본 문법 검증 (FROM 존재)
  if ! grep -qE '^FROM\s+' "$dockerfile" 2>/dev/null; then
    echo "[docker-build-check] FAIL: no FROM instruction in $dockerfile"
    append_gate_history "docker-build-check" "fail" '{"reason":"no FROM instruction"}'
    echo "=== DOCKER BUILD CHECK: FAIL ==="
    return 1
  fi

  # docker 명령 존재 확인
  if ! command -v docker >/dev/null 2>&1; then
    echo "[docker-build-check] SKIP (docker not installed)"
    append_gate_history "docker-build-check" "skip" '{"reason":"docker not installed"}'
    return 0
  fi

  # .dockerignore 존재 확인
  if [[ ! -f ".dockerignore" ]]; then
    echo "[docker-build-check] WARN: .dockerignore not found — sensitive files (.env, keys) may be sent to build context"
  fi

  # 실제 빌드 시도 (타임아웃 120초)
  echo "[docker-build-check] Building $dockerfile..."
  local build_output build_exit
  build_output=$(timeout 120 docker build -f "$dockerfile" --no-cache --progress=plain . 2>&1) && build_exit=0 || build_exit=$?

  if [[ "$build_exit" -eq 0 ]]; then
    echo "[docker-build-check] Build successful"
    append_gate_history "docker-build-check" "pass" "$(jq -n --arg df "$dockerfile" '{"dockerfile":$df}')"
    echo "=== DOCKER BUILD CHECK: PASS ==="
    return 0
  elif [[ "$build_exit" -eq 124 ]]; then
    echo "[docker-build-check] Build timed out (120s)"
    echo "$build_output" | tail -20
    append_gate_history "docker-build-check" "fail" '{"reason":"timeout"}'
    echo "=== DOCKER BUILD CHECK: FAIL (timeout) ==="
    return 1
  else
    echo "[docker-build-check] Build failed (exit $build_exit)"
    echo "$build_output" | tail -30
    append_gate_history "docker-build-check" "fail" "{\"reason\":\"build error\",\"exitCode\":$build_exit}"
    echo "=== DOCKER BUILD CHECK: FAIL ==="
    return 1
  fi
}

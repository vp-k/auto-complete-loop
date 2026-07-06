# gates/checkpoint.sh — Git 체크포인트 생성/조회/롤백 제안

# ─── checkpoint: Git 체크포인트 생성/조회 ───

cmd_checkpoint() {
  local action="${1:?Usage: checkpoint create <name> | checkpoint list | checkpoint suggest-rollback}"
  shift

  case "$action" in
    create)
      local name="${1:?Usage: checkpoint create <name>}"
      # 태그명 안전화: 영숫자/하이픈/점만 허용, 선행/후행 점/하이픈 제거
      local safe_name
      safe_name=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/-/g; s/^[.-]*//; s/[.-]*$//' | head -c 50)
      [[ -z "$safe_name" ]] && safe_name="unnamed"
      local tag_name="auto-checkpoint-${safe_name}"

      # git 상태 확인
      if ! command -v git >/dev/null 2>&1; then
        echo "[checkpoint] SKIP (git not available)"
        return 0
      fi
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[checkpoint] SKIP (not a git repo)"
        return 0
      fi

      # git ref 규칙 검증
      if ! git check-ref-format "refs/tags/$tag_name" 2>/dev/null; then
        echo "[checkpoint] WARN: invalid tag name '$tag_name' — skipping"
        return 0
      fi

      # 커밋이 있어야 태그 가능
      local head_sha
      head_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
      if [[ -z "$head_sha" ]]; then
        echo "[checkpoint] SKIP (no commits yet)"
        return 0
      fi

      # 이미 같은 태그가 있으면 덮어쓰기
      if ! git tag -f "$tag_name" HEAD 2>&1; then
        echo "[checkpoint] WARN: git tag failed for '$tag_name'"
        return 0
      fi
      echo "OK: checkpoint '$tag_name' created at $head_sha"
      ;;

    list)
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[checkpoint] No git repo"
        return 0
      fi
      echo "=== Auto Checkpoints ==="
      git tag -l 'auto-checkpoint-*' --sort=-creatordate 2>/dev/null | head -20 || echo "(none)"
      ;;

    suggest-rollback)
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[checkpoint] No git repo"
        return 0
      fi
      local latest_tag
      latest_tag=$(git tag -l 'auto-checkpoint-*' --sort=-creatordate 2>/dev/null | head -1)
      if [[ -z "$latest_tag" ]]; then
        echo "[checkpoint] No checkpoints found — rollback not available"
        return 1
      fi
      local tag_sha
      tag_sha=$(git rev-parse "$latest_tag" 2>/dev/null)
      echo "=== Rollback Suggestion ==="
      echo "Latest checkpoint: $latest_tag ($tag_sha)"
      echo "Current HEAD:      $(git rev-parse --short HEAD)"
      echo ""
      echo "To rollback, run:  git reset --hard $latest_tag"
      echo "⚠ This is a destructive operation — confirm with user before proceeding."
      ;;

    *)
      die "checkpoint: unknown action '$action'. Use: create, list, suggest-rollback"
      ;;
  esac
}

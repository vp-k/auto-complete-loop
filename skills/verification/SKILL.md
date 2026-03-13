# Phase 4: Verification + Launch Readiness (순수 검증 로직)

이 스킬은 full-auto 오케스트레이터에서 Phase 4 진입 시 Read로 로드됩니다.
Ralph/progress/promise 코드 없음 — 오케스트레이터가 관리.

## 전제 조건

- Phase 3 완료 (코드 리뷰 통과)
- `shared-rules.md`가 이미 로드된 상태

## Phase 4 절차

Phase 4는 두 그룹으로 분할 가능:
- **Group A** (Step 4-1 ~ 4-4): 기술 검증 + 문서화
- **Group B** (Step 4-5 ~ 4-7): 폴리싱 + 최종 검증

### Step 4-1: 전체 빌드/테스트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

1. 전체 빌드 재실행 — 모든 모듈 빌드 성공 확인
2. 전체 테스트 재실행 — 모든 테스트 통과 확인
3. 린트/포맷 전체 검사 — 코드 스타일 일관성 확인

### Step 4-1.5: E2E 테스트 검증

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-progress.json
```

1. 기존 E2E 테스트 점검: 누락 시나리오 확인 -> 추가
2. E2E 실행
3. 프레임워크 미감지 시: E2E 설정 + 테스트 작성 후 재실행

### Step 4-2: 보안 검토

1. **시크릿 스캔**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh secret-scan
   ```

2. **codex 보안 리뷰**
   ```bash
   codex exec --skip-git-repo-check '## 보안 검토
   ### 프로젝트 구조
   [주요 파일 목록 — 직접 읽고 검토]
   ### 요청
   비판적 시각으로 보안 문제점을 탐색해주세요.
   - .env 파일 .gitignore 포함 여부
   - 하드코딩된 API 키, 비밀번호
   - 로그 민감 정보 출력
   - 의존성 취약점
   '
   ```

DoD 업데이트: `security_review`, `secret_scan`

### Step 4-3: 디버그 코드 제거 + 코드 정리

1. 디버그 코드 탐색:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh find-debug-code
   ```
2. console.log, print, debugger 등 제거
3. 주석 처리된 코드 정리
4. 미사용 import 제거
5. 불필요한 파일 정리

### Step 4-4: 문서화 확인 + Launch Readiness

#### 기본 문서화
1. **README 완성도**: 프로젝트 설명, 설치/실행 방법, 환경 변수 설명
2. **.env.example** 존재 여부 + 필수 환경 변수 목록
3. **API 문서** (해당 시)

#### 릴리즈 노트 자동 생성

git log 기반으로 릴리즈 노트를 생성합니다:

**`[auto]` 커밋 필터링 규칙:**
- `[auto]` prefix 커밋은 사용자용 changelog에서 제외
- `feat:`, `fix:`, `breaking:` 등 semantic commit만 포함
- `[auto]` 커밋은 "내부 자동화 N건" 1줄 요약으로 축약

**Fallback:**
- semantic commit이 0개인 경우, 파일 변경 기반 요약으로 fallback
- 디렉토리별 변경 파일 수 + 주요 변경 내용 AI 요약

릴리즈 노트 파일: `CHANGELOG.md` 또는 `RELEASE_NOTES.md`

#### (Flutter) 앱 스토어 메타데이터 템플릿

Flutter 프로젝트인 경우:
```markdown
## App Store Metadata
- 앱 이름: [프로젝트명]
- 한줄 설명: [80자 이내]
- 상세 설명: [4000자 이내]
- 카테고리: [App Store 카테고리]
- 키워드: [최대 100자]
- 스크린샷 가이드: [필요한 스크린샷 목록과 설명]
```

#### 배포 체크리스트

```markdown
## 배포 체크리스트
- [ ] 환경 변수 설정 완료
- [ ] 시크릿 관리 (vault/secrets manager)
- [ ] DNS/도메인 설정 (해당 시)
- [ ] SSL 인증서 (해당 시)
- [ ] 모니터링/알림 설정
- [ ] 백업 정책
- [ ] 롤백 계획
```

DoD 업데이트: `launch_ready.checked = true`, evidence에 "릴리즈 노트 + 배포 체크리스트 완료"

### Step 4-5: 디자인 폴리싱

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh design-polish-gate --progress-file .claude-full-auto-progress.json
```

WCAG 체크 + 스크린샷 캡처 (design-polish 플러그인 미설치 시 SKIP).
SOFT_FAIL: 개선 권장사항으로 처리 (차단하지 않음).

디자인 수정 + 품질 게이트 통과 후:
```bash
git add -A && git commit -m "[auto] Phase 4 디자인 폴리싱 완료"
```

### Step 4-6: 아티팩트/스모크 체크

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh artifact-check --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh smoke-check --progress-file .claude-full-auto-progress.json
```

### Step 4-7: 최종 검증

모든 정리/폴리싱 완료 후:

1. 빌드 재실행 -> 성공
2. 테스트 재실행 -> 전체 통과
3. 린트 재실행 -> 경고 없음
4. 결과를 `.claude-verification.json`에 기록
5. progress 파일의 dod 체크리스트 최종 업데이트

자동 커밋:
```bash
git add -A && git commit -m "[auto] 최종 검증 및 폴리싱 완료"
```

DoD 전체 checked 확인 후, Phase 전이는 오케스트레이터가 수행.

### Step 4-8: Version Bump + PR 생성 (Opt-in)

Phase 4 완료 후, 사용자에게 버전 업 + PR 생성을 제안합니다.

#### Version Bump 규칙

diff 크기 기반 자동 결정:
- **patch** (0.0.x): 변경 50줄 미만 (버그 수정, 소규모 변경)
- **minor** (0.x.0): 변경 50줄 이상 (새 기능, 개선)
- **major** (x.0.0): breaking change 감지 시 (API 변경, 삭제 등)

```bash
# diff 크기 측정 (POSIX 호환)
local base_branch="${BASE_BRANCH:-main}"
local diff_lines
diff_lines=$(git diff --stat "HEAD~$(git rev-list --count HEAD --not "$base_branch")" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1) ~ /insertion/) print $i}' || echo "0")

# breaking change 감지
local has_breaking
has_breaking=$(git log --oneline "$base_branch"..HEAD | grep -ciE 'breaking|BREAKING' || echo "0")
```

**Version 파일 업데이트** (프로젝트 유형별):
- `package.json`: `npm version <patch|minor|major> --no-git-tag-version`
- `pubspec.yaml`: `version:` 필드 직접 수정
- `Cargo.toml`: `version =` 필드 직접 수정
- `pyproject.toml`: `version =` 필드 직접 수정

#### PR 생성 (사용자 확인 후)

1. **사용자 확인**: "PR을 생성하시겠습니까?" (AskUserQuestion)
2. **승인 시**:
   ```bash
   # 변경 커밋
   git add -A && git commit -m "[auto] version bump to vX.Y.Z"

   # PR 생성 (gh CLI)
   gh pr create \
     --title "Release vX.Y.Z: [주요 변경 요약]" \
     --body "## Summary
   - [자동 생성된 변경 요약]

   ## Quality
   - Health Score: [점수]/100
   - Code Review: [라운드] rounds, CRITICAL/HIGH: 0
   - Tests: All passing

   ## Changelog
   [릴리즈 노트에서 발췌]"
   ```
3. **거부 시**: 버전 업만 로컬에 커밋, PR 생성 건너뜀

### Iteration 관리

- Group A (Step 4-1~4-4), Group B (Step 4-5~4-7)로 분할 가능
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료

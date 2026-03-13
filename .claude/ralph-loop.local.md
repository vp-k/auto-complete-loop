---
active: true
iteration: 1
max_iterations: 20
completion_promise: "REVIEW_LOOP_COMPLETE"
progress_file: ".claude-review-loop-progress.json"
started_at: "2026-03-13T16:29:01Z"
---

이전 작업을 이어서 진행합니다.
`.claude-review-loop-progress.json`을 읽고 상태를 확인하세요.
특히 `handoff` 필드를 먼저 읽어 이전 iteration의 맥락을 복구하세요.

1. completed 단계는 건너뛰세요
2. in_progress 단계가 있으면 해당 단계부터 재개
3. pending 단계가 있으면 다음 pending 단계 시작
4. 모든 단계가 completed이고 검증을 통과하면 <promise>REVIEW_LOOP_COMPLETE</promise> 출력

검증 규칙:
- .claude-review-loop-progress.json의 모든 단계/문서 status가 completed여야 함
- dod 체크리스트가 모두 checked여야 함
- 조건 미충족 시 절대 <promise> 태그를 출력하지 마세요

# 프로젝트 규모 판정 (중앙 기준)

모든 Phase/DoD/스킬에서 규모 조건이 필요할 때 이 기준을 참조합니다.

| 규모 | 기준 |
|------|------|
| Small | 기능 5개 미만 |
| Medium | 기능 5~15개 |
| Large | 기능 16개 이상, 또는 아래 중 1개 이상 충족: 기획 문서 8개+, 모듈/기능 그룹 4개+, 외부/타팀 이해관계자 3팀+ |

## 규모별 활성화 항목

아래 표가 **규모 분기의 단일 출처**입니다. 스킬·게이트·에이전트는 여기에 없는 규모 조건을 새로 만들지 않습니다.

### 기획 산출물 (Phase 0)

| 항목 | Small | Medium | Large |
|------|-------|--------|-------|
| MoSCoW 분류 | O | O | O |
| ICE 점수 | - | O | O |
| Kano 조정 | - | O | O |
| 핵심 사용자 플로우 | - | O | O |
| 이해관계자 맵 | - | - | O |
| 커뮤니케이션 계획 | - | - | O |

### 문서·검증 산출물 (Phase 1)

| 항목 | Small | Medium | Large | 스킵 시 증거 / 근거 |
|------|-------|--------|-------|------|
| 기획 문서 토론 루프 (Step 1-2) | O | O | O | — |
| 백엔드 표준 문서 3종<br>(logging-standard / error-policy / security-authn-authz) | - | O | O | Small은 **복사도 검증도 안 함**. 로깅·에러·인증 정책은 SPEC.md 해당 섹션에서 다룸 (템플릿 합계 486줄이 기능 5개 미만 기획을 압도) |
| `docs/DESIGN.md` (디자인 계약) | **hasFrontend 기준** | **hasFrontend 기준** | **hasFrontend 기준** | 규모 분기 없음 — `projectScope.hasFrontend=true`면 규모 무관 필수 |
| smoke 스크립트 (Step 1-7, `tests/*-smoke.*`) | O | O | O | 규모 분기 없음 |
| 인수 테스트 선작성 + 해시 동결 (Step 1-7.5) | O | O | O | 규모 분기 없음 — 완주의 하드 조건 |
| 아키텍처 리뷰 (Step 1-6)<br>roundtable(codex/dual/teams) 또는 architect(solo) | - | O | O | `phases.phase_1.outputs.roundtableArchReview`<br>(solo: `architectReview`) = `{"verdict":"SKIPPED_SMALL"}` |
| Test Plan / test-strategist (Step 1-8) | - | O | O | `phases.phase_1.outputs.testPlan = {"verdict":"SKIPPED_SMALL"}`<br>`spec-completeness`의 `test-plan.md` 존재 검사도 Small이면 skip |
| Phase 1 완료 게이트 5종<br>(provenance-gate / clarification-gate / doc-consistency / acceptance-freeze / 존재 검증) | O | O | O | 규모·모드 무관 — stop-hook fail-closed |

### Phase 0 검토

| 항목 | Small | Medium | Large | 스킵 시 증거 |
|------|-------|--------|-------|------|
| roundtable 기획 리뷰 (Step 0-7) | - | O | O | `roundtableConsensus`에 `SKIPPED_SMALL` |

## DoD 키 규모별 관리 (방식 A)
- Small/Medium에서는 Large 전용 DoD 키(`stakeholders_mapped`)를 **아예 생성하지 않음**
- stop-hook은 dod에 존재하는 키만 전부 `checked=true`이면 통과
- Phase 0 Step 0-9.5에서 2차 재판정 시 DoD 키 동적 추가/삭제

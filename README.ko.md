[English](README.md) | **한국어**

# plansmith

[Claude Code](https://docs.anthropic.com/en/docs/claude-code)용 연구 기반 계획 플러그인입니다. 구조화된 단계(이해, 탐색, 대안, 초안, 비판, 수정)를 거치며 각 단계마다 검증을 수행해 고품질 구현 계획서를 만들어냅니다.

[Ralph Loop](https://ghuntley.com/ralph/) 기법에 기반하되, 테스트 통과까지 코드를 반복하는 대신 **품질 게이트가 충족될 때까지 계획 단계를 반복**합니다.

## 왜 만들었나?

Claude Code로 복잡한 작업을 할 때 흔한 패턴이 있습니다: 바로 코드 작성에 뛰어들고, 중간에 방향을 잃고, 되돌리고, 처음부터 다시 시작. Plan mode를 쓰면 간단한 작업에서는 괜찮지만, 복잡한 작업일수록 계획에 빈틈이 생깁니다.

제 경험상, AI에게 "계획을 다시 검토해라"고 하면 빠진 엣지 케이스, 잘못된 단계 순서, 누락된 의존성 등이 발견됩니다. 문제는 **몇 번을 검토시켜도 수정할 부분이 계속 나온다**는 것입니다. 매번 검토할 때마다 일부 문제는 잡지만 다른 문제를 놓치거나 새로 만들어냅니다. "계획을 짜고 비판하고 수정하라"는 단일 프롬프트는 겉보기에 꼼꼼해 보이는 계획을 만들지만, 실제로 스트레스 테스트를 거친 것은 아닙니다.

연구도 이를 뒷받침합니다. [Self-Refine](https://arxiv.org/abs/2303.17651) (NeurIPS 2023)은 명시적인 생성 → 피드백 → 정제 루프가 한 번에 생성하는 것보다 ~20% 품질을 향상시킨다는 것을 보여주었습니다 — 단, 각 단계가 **구분된 역할**을 가질 때만입니다. [프롬프트 반복](https://arxiv.org/abs/2512.14982)은 약간의 도움이 될 수 있지만, 구조화된 역할 분리가 실질적인 품질 향상을 이끕니다. 더 최근에는 [LLMs Can Plan Only If We Tell Them](https://arxiv.org/abs/2501.13545) (ICLR 2025)이 LLM에게 잠재된 계획 능력이 있지만 구조화된 프롬프팅이 있어야 발휘된다는 것을 보여주었습니다 — 스스로는 잘 못하지만, 올바른 프레임워크를 주면 *잘 할 수 있습니다*.

해결책: **각 단계에서 근본적으로 다른 작업을 강제합니다.** 계획 전에 코드를 탐색하고, 비판 전에 초안을 쓰고, 수정 전에 비판합니다. 각 단계에는 **부정 검증**이 있어서 — 탐색 단계는 계획 헤딩을 거부하고, 비판 단계는 최종화 시도를 거부합니다. 이로써 모든 것을 한 번에 처리하는 것이 구조적으로 불가능해집니다. 이 접근 방식은 [test-time compute scaling](https://arxiv.org/abs/2408.03314) (ICLR 2025 Oral)과도 맞닿아 있습니다 — 구조화된 단계를 통해 추론 시간에 더 많은 계산을 쓰는 것이 더 큰 모델을 사용하는 것보다 효과적일 수 있습니다.

### 연구 기반

Plansmith의 단계 아키텍처는 동료 심사 논문에 근거합니다:

| 기법 | 논문 | 적용 방식 |
|------|------|-----------|
| **다중 반복 정제** | [Self-Refine](https://arxiv.org/abs/2303.17651) (NeurIPS 2023) | 기본 2회 비판-수정 사이클 (`--refine-iterations`) |
| **원칙 기반 비평** | [Constitutional AI](https://arxiv.org/abs/2212.08073) (Anthropic) | 12개 원칙 (P1-P12) PASS/FAIL 평가 |
| **세션 메모리** | [Reflexion](https://arxiv.org/abs/2303.11366) (NeurIPS 2023) | FAIL 항목이 세션 간 유지 |
| **단계 분해** | [Least-to-Most](https://arxiv.org/abs/2205.10625) (ICLR 2023) | 단계를 단순→복잡 순서로 의존성과 함께 정렬 |
| **구조화된 계획 활성화** | [LLMs Can Plan Only If We Tell Them](https://arxiv.org/abs/2501.13545) (ICLR 2025) | 단계 기반 프롬프팅으로 잠재된 계획 능력 활성화 |
| **추론 시간 연산 확장** | [Scaling Test-Time Compute](https://arxiv.org/abs/2408.03314) (ICLR 2025 Oral) | 다중 단계 추론이 더 큰 단일 모델보다 효과적 |
| **구조화된 자기 교정** | [SCoRe](https://arxiv.org/abs/2409.12917) (ICLR 2025 Oral) | 다중 턴 자기 교정으로 MATH에서 15.6% 향상 |

## 작동 방식

```
/plansmith:plan 인증 시스템 설계
```

기본 흐름: 8단계, 2회 비판-수정 사이클.

| 단계 | Claude가 하는 일 | 검증 내용 |
|------|-----------------|----------|
| **이해** | 문제 분석, 성공 기준/제약/가정 정의 | 번호 항목 3+, 이해 키워드 2+, 계획 헤딩 없어야 함 |
| **탐색** | 코드베이스를 읽고 파일/아키텍처/패턴을 나열. 이전 세션 학습 주입 (Reflexion). | 계획 헤딩(`## 목표` 등)이 없어야 함 |
| **대안** | 2~3가지 접근 방식 비교 후 하나 선택 | 옵션 2+, 추천 키워드, 장단점 키워드 필요 |
| **초안** | 7개 필수 섹션을 포함한 완전한 계획서 작성. 단계를 단순→복잡 순서로 정렬 (Least-to-Most). | 모든 섹션 헤딩이 존재해야 함 |
| **비판 (×2)** | 12개 원칙 (P1-P12)에 대해 PASS/FAIL 평가. 관점 회전: 기술적 → 유지보수성. | `<promise>` 태그 없어야 함. 번호 항목 3+, 원칙 참조 6+. |
| **수정 (×2)** | 모든 비판을 반영해 계획서 재작성 | Promise 태그 + 모든 섹션 = 완료 (마지막 라운드만) |

각 단계는 검증이 단계 합치기를 방지하기 때문에 진정으로 다른 출력을 만들어냅니다.

```
/plansmith:plan ─→ 이해 ─→ 탐색 ─→ 대안 ─→ 초안 ─→ 비판 ─→ 수정 ─→ 비판 ─→ 수정 ─→ 저장!
                    │        │        │        │        │        │        │        │
                 (실패?)   (실패?)   (실패?)   (실패?)  (실패?)  (실패?)  (실패?)  (실패?)
                    ↓        ↓        ↓        ↓        ↓        ↓        ↓        ↓
                  재시도    재시도    재시도    재시도   재시도    재시도   재시도    반복
```

완료되면 최종 계획서가 `.claude/plansmith-output.local.md`에 저장됩니다.

## 빠른 시작

```bash
# 계획 루프 시작 (기본: 8단계, 2회 비판-수정 사이클)
/plansmith:plan 인증 시스템 설계

# 간단한 작업에 적은 반복
/plansmith:plan 버그 수정 계획 --refine-iterations 1

# 이해+탐색 건너뛰기 (문제와 코드를 이미 알 때)
/plansmith:plan 리팩토링 계획 --skip-understand --skip-explore

# 원칙 기반 대신 자유 형식 비평 사용
/plansmith:plan 캐싱 설계 --open-critique

# 필요시 취소
/plansmith:cancel
```

`/plansmith:plan`을 실행하면 루프가 자동으로 진행됩니다 — 수동 개입이 필요 없습니다. Stop 훅이 각 응답을 가로채서 현재 단계의 규칙에 따라 검증하고, 다음 단계의 프롬프트를 주입합니다. 검증이 실패하면 Claude가 피드백과 함께 자동으로 재시도합니다.

## Ralph Loop과의 차이점

| | ralph-loop | plansmith |
|--|-----------|-----------------|
| **구조** | 같은 프롬프트 반복 | 다른 프롬프트를 가진 구별된 단계 |
| **검증** | 단일 promise 태그 | 단계별 검증 (긍정 + 부정) |
| **도구 차단** | 없음 (전체 접근) | 계획 중 Edit/Write/Bash 차단 |
| **자기 비판** | 선택 사항 | 12개 원칙 기반 전용 비판 단계 (건너뛸 수 없음) |
| **반복** | 테스트 통과까지 | 설정 가능한 비판-수정 사이클 (Self-Refine) |
| **메모리** | 없음 | 세션 간 메모리 유지 (Reflexion) |
| **출력** | 수정된 파일 | 저장된 계획 파일 (`.claude/plansmith-output.local.md`) |

## 커맨드

### `/plansmith:plan <PROMPT> [OPTIONS]`

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `--max-phases <n>` | 10 | 자동 중단까지 최대 단계 전환 수 |
| `--refine-iterations <n>` | 2 | 비판-수정 사이클 횟수, 1-4 (Self-Refine) |
| `--skip-understand` | (이해 ON) | 이해 단계 건너뛰기 |
| `--skip-explore` | (탐색 ON) | 탐색 단계 건너뛰기 |
| `--skip-alternatives` | (대안 ON) | 대안 비교 단계 건너뛰기 |
| `--open-critique` | (원칙 ON) | 원칙 기반 대신 자유 형식 비평 사용 |
| `--no-memory` | (메모리 ON) | 세션 메모리 비활성화 (Reflexion) |
| `--clear-memory` | — | 축적된 세션 메모리 초기화 |
| `--phases "a,b,c"` | (동적) | 커스텀 단계 시퀀스 (`--refine-iterations` 무시) |
| `--no-block-tools` | (차단 ON) | 도구 차단 비활성화 |
| `--required-sections "A,B,C"` | Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions | 필수 섹션 헤딩 |
| `--completion-promise <text>` | PLAN_OK | Promise 태그 값 |

### `/plansmith:cancel`

활성 계획 루프를 취소합니다.

### `/plansmith:help`

상세 도움말을 표시합니다.

## 품질 게이트

**수정** 단계에서 2단계 품질 게이트를 사용합니다:

1. **Promise 태그**: `<promise>PLAN_OK</promise>`가 존재해야 함
2. **필수 섹션**: 모든 섹션 헤딩이 존재해야 함

### 기본 필수 섹션

섹션 헤딩은 **영어와 한국어 모두** 인식됩니다 — 전체 계획서를 한국어로 작성해도 됩니다.

| 영어 | 한국어 |
|------|--------|
| `## Goal` | `## 목표` |
| `## Scope` | `## 범위` |
| `## Non-Scope` | `## 비범위` |
| `## Steps` | `## 단계별 계획` |
| `## Verification` | `## 검증` |
| `## Risks` | `## 리스크` |
| `## Open Questions` | `## 오픈 질문` |

## 도구 차단

활성화 시 (기본값):

| 도구 | 정책 |
|------|------|
| **Edit, Write, NotebookEdit** | 항상 차단 |
| **Bash** | 읽기 전용 단일 명령만 허용. 파이프, 세미콜론, 리다이렉트 차단. |
| **Read, Glob, Grep, WebSearch, WebFetch, Task** | 항상 허용 |

`--no-block-tools`로 비활성화할 수 있습니다.

## 사용 시기

**적합한 경우:**
- 코딩 전 아키텍처 계획이 필요한 복잡한 작업
- 의존성 분석이 필요한 다중 파일 변경
- Claude가 변경 전에 코드베이스를 탐색하게 하고 싶을 때
- "먼저 계획, 나중에 실행"으로 재작업을 줄이고 싶을 때

**적합하지 않은 경우:**
- 간단하고 명확한 작업 (바로 실행하세요)
- 탐색할 코드베이스가 없는 경우 (`--skip-explore` 사용)
- 이미 명확한 계획이 있는 경우

## 출력

루프 완료 시, `<promise>` 태그가 제거된 최종 계획서가 저장됩니다:

```
.claude/plansmith-output.local.md        — 최종 계획서
.claude/plansmith-memory.local.md        — 세션 메모리 (Reflexion, 세션 간 유지)
```

계획서 파일에는 메타데이터가 포함된 YAML frontmatter가 있습니다:

```yaml
---
generated_at: "2026-02-27T12:00:00Z"
exit_reason: "completed"        # 또는 "max_phases_reached"
---
```

`--max-phases`에 도달해서 완료되지 못한 경우에도 현재 출력이 `exit_reason: "max_phases_reached"`로 저장됩니다.

## 알려진 제한 사항

- **프롬프트에 `---` 포함**: YAML frontmatter 파싱이 깨질 수 있습니다. 프롬프트에서 `---`을 단독 줄로 사용하지 마세요.
- **도구 차단이 보수적**: Bash 인자의 `&`, `>`, `|`, `;`도 차단됩니다. 필요시 `--no-block-tools`를 사용하세요.
- **큰따옴표가 포함된 completion promise**: `--completion-promise` 값에 `"`를 사용하지 마세요.

## 호환성

공식 `ralph-loop` 플러그인과 별도의 상태 파일(`.claude/plansmith.local.md`)을 사용합니다. 두 플러그인을 동시에 설치할 수 있습니다.

## 요구 사항

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` (JSON 처리)
- `perl` (promise 태그 추출)

## 설치

마켓플레이스를 추가하고 설치합니다:

```shell
/plugin marketplace add gigagookbob/plansmith
/plugin install plansmith@plansmith-local
```

팀 프로젝트에 기본 포함하려면 프로젝트의 `.claude/settings.json`에 추가:

```json
{
  "extraKnownMarketplaces": {
    "plansmith-local": {
      "source": {
        "source": "github",
        "repo": "gigagookbob/plansmith"
      }
    }
  },
  "enabledPlugins": {
    "plansmith@plansmith-local": true
  }
}
```

## 라이선스

MIT 라이선스. 자세한 내용은 [LICENSE](LICENSE)를 참조하세요.

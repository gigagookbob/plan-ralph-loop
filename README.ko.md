[English](README.md) | **한국어**

# plansmith

[Claude Code](https://docs.anthropic.com/en/docs/claude-code)용 계획 중심 반복 루프 플러그인입니다. 구조화된 단계(탐색, 초안, 비판, 수정)를 거치며 각 단계마다 검증을 수행해 고품질 구현 계획서를 만들어냅니다.

[Ralph Loop](https://ghuntley.com/ralph/) 기법에 기반하되, 테스트 통과까지 코드를 반복하는 대신 **품질 게이트가 충족될 때까지 계획 단계를 반복**합니다.

## 왜 만들었나?

Claude Code로 복잡한 작업을 할 때 흔한 패턴이 있습니다: 바로 코드 작성에 뛰어들고, 중간에 방향을 잃고, 되돌리고, 처음부터 다시 시작. "먼저 계획을 세우자"는 당연해 보이지만, AI가 첫 시도에 정말 좋은 계획을 만들어내는 경우는 드뭅니다.

문제는 "더 반복하라"보다 깊은 곳에 있습니다. LLM에게 "계획을 계속 개선하라"고 하면, 매번 같은 수준의 출력을 내놓습니다 — 항상 한 번에 완전한 답을 쓰려 하기 때문입니다. 같은 프롬프트를 반복해도 도움이 되지 않습니다.

해결책: **각 단계에서 근본적으로 다른 작업을 강제합니다.** 계획 전에 코드를 탐색하고, 비판 전에 초안을 쓰고, 수정 전에 비판합니다. 각 단계에는 **부정 검증**이 있어서 — 탐색 단계는 계획 헤딩을 거부하고, 비판 단계는 최종화 시도를 거부합니다. 이로써 단계를 건너뛰는 것이 구조적으로 불가능해집니다.

## 작동 방식

```
/plansmith:plan 인증 시스템 설계 --max-phases 10
```

| 단계 | Claude가 하는 일 | 검증 내용 |
|------|-----------------|----------|
| **이해** | 문제 분석, 성공 기준/제약/가정 정의 | 번호 항목 3+, 이해 키워드 2+, 계획 헤딩 없어야 함 |
| **탐색** | 코드베이스를 읽고 파일/아키텍처/패턴을 나열 | 계획 헤딩(`## 목표` 등)이 없어야 함 |
| **대안** | 2~3가지 접근 방식 비교 후 하나 선택 | 옵션 2+, 추천 키워드, 장단점 키워드 필요 |
| **초안** | 7개 필수 섹션을 포함한 완전한 계획서 작성 | 모든 섹션 헤딩이 존재해야 함 |
| **비판** | 구체적인 번호 매긴 약점 나열 (3개 이상) | `<promise>` 태그가 없어야 함 |
| **수정** | 모든 비판을 반영해 계획서 재작성 | Promise 태그 + 모든 섹션 = 완료 |

각 단계는 검증이 단계 합치기를 방지하기 때문에 진정으로 다른 출력을 만들어냅니다.

## 빠른 시작

```bash
# 계획 루프 시작
/plansmith:plan 인증 시스템 설계 --max-phases 12

# 이해+탐색 건너뛰기 (문제와 코드를 이미 알 때)
/plansmith:plan 리팩토링 계획 --skip-understand --skip-explore

# 대안 비교 건너뛰기
/plansmith:plan 버그 수정 계획 --skip-alternatives

# 필요시 취소
/plansmith:cancel
```

`/plansmith:plan`을 실행하면 루프가 자동으로 진행됩니다 — 수동 개입이 필요 없습니다. Stop 훅이 각 응답을 가로채서 현재 단계의 규칙에 따라 검증하고, 다음 단계의 프롬프트를 주입합니다. 검증이 실패하면 Claude가 피드백과 함께 자동으로 재시도합니다.

```
/plansmith:plan ─→ 이해 ─→ 탐색 ─→ 대안 ─→ 초안 ─→ 비판 ─→ 수정 ─→ 저장!
                    │        │        │        │        │        │
                 (실패?)   (실패?)   (실패?)   (실패?)  (실패?)  (실패?)
                    ↓        ↓        ↓        ↓        ↓        ↓
                  재시도    재시도    재시도    재시도   재시도    반복
```

완료되면 최종 계획서가 `.claude/plansmith-output.local.md`에 저장됩니다.

## Ralph Loop과의 차이점

| | ralph-loop | plansmith |
|--|-----------|-----------------|
| **구조** | 같은 프롬프트 반복 | 다른 프롬프트를 가진 구별된 단계 |
| **검증** | 단일 promise 태그 | 단계별 검증 (긍정 + 부정) |
| **도구 차단** | 없음 (전체 접근) | 계획 중 Edit/Write/Bash 차단 |
| **자기 비판** | 선택 사항 | 전용 비판 단계 (건너뛸 수 없음) |
| **출력** | 수정된 파일 | 저장된 계획 파일 (`.claude/plansmith-output.local.md`) |

## 커맨드

### `/plansmith:plan <PROMPT> [OPTIONS]`

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `--max-phases <n>` | 10 | 자동 중단까지 최대 단계 전환 수 |
| `--skip-understand` | (이해 ON) | 이해 단계 건너뛰기 |
| `--skip-explore` | (탐색 ON) | 탐색 단계 건너뛰기 |
| `--skip-alternatives` | (대안 ON) | 대안 비교 단계 건너뛰기 |
| `--phases "a,b,c"` | understand,explore,alternatives,draft,critique,revise | 커스텀 단계 시퀀스 |
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
.claude/plansmith-output.local.md
```

파일에는 메타데이터가 포함된 YAML frontmatter가 있습니다:

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

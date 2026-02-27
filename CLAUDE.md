# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

plan-ralph-loop는 Claude Code용 플러그인으로, [Ralph Loop](https://ghuntley.com/ralph/) 기법을 기반으로 한 **계획 전용 반복 루프**이다. 코드를 반복 수정하는 대신, **계획(plan)**을 품질 게이트가 통과할 때까지 반복 개선한다.

## Architecture

플러그인은 3개의 핵심 메커니즘으로 구성된다:

1. **Commands** (`commands/`): Claude Code 슬래시 명령 정의 (YAML frontmatter + Markdown 프롬프트)
2. **Hooks** (`hooks/`): `hooks.json`에 등록된 Stop/PreToolUse 훅이 반복 제어 및 도구 차단 수행
3. **Scripts** (`scripts/`): Bash 스크립트가 상태 관리, 인자 파싱, 계획 저장 담당

### 실행 흐름

```
/plan-ralph → setup-plan-ralph.sh (상태 파일 생성)
  → Claude 계획 작성 (read-only)
  → stop-hook.sh (반복마다: promise tag + 필수 섹션 검증)
  → 품질 게이트 통과 시 → save-plan.sh → .claude/plan-output.local.md
```

### 상태 관리

- 상태 파일: `.claude/plan-ralph.local.md` (YAML frontmatter)
- 필드: `active`, `iteration`, `max_iterations`, `completion_promise`, `block_tools`, `required_sections`, `started_at`
- frontmatter 파싱은 `sed`로, 업데이트는 `sed_inplace()` 헬퍼로 수행 (macOS + Linux 호환)

### 품질 게이트 (stop-hook.sh)

2단계 검증:
1. `<promise>COMPLETION_PROMISE</promise>` 태그 존재 여부 (perl regex)
2. 필수 섹션 헤딩 존재 여부 (grep, 영어+한국어 이중 언어 지원)

최소 2회 반복 강제: 첫 번째 반복은 항상 드래프트로 취급하여 self-critique 유도.

### 도구 차단 (pretooluse-hook.sh)

- Edit/Write/NotebookEdit: 항상 차단
- Bash: 읽기 전용 명령만 허용 (allowlist 방식). 파이프/세미콜론/리다이렉트 포함 시 차단
- Read/Glob/Grep/WebSearch/WebFetch/Task: 항상 허용

## Scripting Conventions

- `#!/usr/bin/env bash` + `set -euo pipefail`
- macOS/Linux 호환 `sed`: `-i` 플래그 대신 임시 파일 + `mv` 사용 (`sed_inplace()`)
- 훅 출력은 `jq`로 JSON 생성하여 Claude Code에 전달
- 명령 정의는 YAML frontmatter (`allowed-tools`, `description`) + Markdown 본문

## Dependencies

시스템 도구만 사용 (npm/pip 없음):
- `jq`: 훅 입출력 JSON 처리 (필수)
- `perl`: promise 태그 추출 (필수)
- `bash`, `sed`, `grep`: 스크립트 기반

## Key Files

| 파일 | 역할 |
|------|------|
| `hooks/stop-hook.sh` | 반복 제어 + 품질 게이트 (핵심 로직) |
| `hooks/pretooluse-hook.sh` | 계획 중 도구 차단 |
| `scripts/setup-plan-ralph.sh` | CLI 인자 파싱 + 상태 파일 생성 |
| `scripts/save-plan.sh` | 최종 계획 저장 |
| `templates/plan-rubric.md` | 품질 루브릭 템플릿 |
| `hooks/hooks.json` | 훅 등록 설정 |

## Known Limitations

- 프롬프트에 `---`가 단독 줄로 포함되면 YAML frontmatter 파싱이 깨질 수 있음
- Bash allowlist가 보수적: 인자에 `&`, `>`, `|`, `;`가 포함되면 (예: `grep 'a&b'`) 차단됨
- `--completion-promise` 값에 쌍따옴표 포함 시 YAML 파싱 오류 가능

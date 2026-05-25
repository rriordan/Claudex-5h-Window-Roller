# Claudex-5h-Window-Roller — Claude Code Handoff Document

## 1. Project Overview

Windows 환경에서 **Claude Code**와 **Codex CLI**의 5 시간 사용 윈도우를 지속적으로 롤링하여, 작업 시작 시 바로 윈도우 내부를 활용할 수 있도록 합니다. PowerShell 단일 스크립트로 구현되며, Python 이나 외부 모듈 없이 Windows Scheduled Task 를 통해 분당 실행되어 쿼타 리셋을 관리합니다. 실패 시 토스트 알림을 제공하며, WSL 보다는 Windows CLI 를 우선적으로 사용합니다.

## 2. 기술 스택

| 계층 | 기술 |
|------|------|
| Language | PowerShell (추론: `claudex-roller.ps1` 파일 및 README 내용) |
| Framework | None (추론: 외부 모듈 없음, Native Windows API 사용) |
| OS | Windows (추론: Scheduled Task, `%USERPROFILE%` 경로 사용) |
| CLI Tools | Claude Code, Codex CLI (추론: README 의 설치/검증 명령어) |

## 3. 빌드 / 테스트

```powershell
# 설치 및 자동 등록
irm https://raw.githubusercontent.com/rriordan/Claudex-5h-Window-Roller/main/claudex-roller.ps1 | iex

# 상태 확인 (Verify)
& "$env:USERPROFILE\.claudex-5h-window-roller\claudex-roller.ps1" -Status
```

## 4. 코딩 컨벤션

### File Storage Rules
- 모든 문서와 아티팩트는 프로젝트 디렉토리 내부에 생성해야 함.
- `~/.claude/`, `~/.gemini/` 등 외부 경로 사용 금지.
- Plans: `docs/plans/`
- Reference docs: `docs/reference/`
- Prompts: `docs/prompts/`

### Documentation Rules
- 파일명: 2-4 토큰 (camelCase), 날짜 없이 안정적 이름 사용.
- Plan: `featureNamePlan.md` 또는 `featureNamePlan_YYYY-MM-DD.md`.
- Prompt: `docs/prompts/YYYY-MM-DD/short_name.md`.
- Metadata: 문서 상단 `type`, `status`, `updated_at` 포함.
- Status: `draft` → `in_progress` → `done` → `archived`.

### Coding Rules
- 언어: 사용자 사용 언어에 응답 (코드, 경로, 식별자는 원어 유지).
- 품질: 요청된 부분만 수정, 주변 코드 정리 금지.
- 에러 핸들링: 개발 중 침묵한 폴백 최소화.
- 테스트: 변경 후 기존 테스트 통과 확인, 새 로직은 단위 테스트 고려.

### Work Safety Rules
- 교체 전 동작 검증, 파괴적 작업 전 확인.
- 단일 경로 수정 (공유 상태 동시 변경 금지).

### Agent Behavior Rules
- 구현 전 계획 제시 및 승인 대기.
- 명령어는 동기 실행 (`&`, `nohup` 등 배경 실행 금지).
- 긴 스크립트는 진행 출력 추가.

## 5. 다음 우선순위

- 미정 (에이전트와 상의하여 채우세요)

---

> Auto-detected by tunaFlow. 내용을 검토하고 필요하면 수정하세요.
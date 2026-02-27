## Planning Quality Rubric

All criteria below must be satisfied for the plan to be considered complete.

### Required Sections

- [ ] **Goal / 목표**: Clear, measurable objective. What does "done" look like?
- [ ] **Scope / 범위**: What IS included in this work. Be explicit about boundaries.
- [ ] **Non-Scope / 비범위**: What is explicitly NOT included. Prevents scope creep.
- [ ] **Steps / 단계별 계획**: Ordered, concrete implementation steps. Each step should reference specific files, functions, or modules.
- [ ] **Verification / 검증**: How to verify correctness. Test commands, manual checks, acceptance criteria.
- [ ] **Risks / 리스크**: What could go wrong. Each risk needs a mitigation strategy.
- [ ] **Open Questions / 오픈 질문**: Uncertainties that need resolution. Who can answer them?

### Quality Criteria

- Steps reference actual code (file paths, function names, class names)
- No vague language ("improve", "optimize", "refactor" without specifics)
- Dependencies between steps are identified
- Breaking changes are called out explicitly
- Estimated effort per step (S/M/L)

### Self-Critique Checklist (review each iteration)

1. Would a new developer understand this plan without additional context?
2. Are there implicit assumptions that should be made explicit?
3. Are there edge cases or failure modes not addressed?
4. Is the verification plan actually testable?
5. Are the steps ordered correctly? Are dependencies clear?

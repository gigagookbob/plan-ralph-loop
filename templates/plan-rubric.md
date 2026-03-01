## Planning Process

This plan will be developed in phases:
1. **Understand**: Analyze the problem, define success criteria and constraints (no code reading yet)
2. **Explore**: Read the codebase and list findings (no plan yet)
3. **Alternatives**: Compare 2-3 approaches with pros/cons, choose one (no plan yet)
4. **Draft**: Write the initial plan with all required sections (Least-to-Most step ordering)
5. **Critique & Revise** (repeated): Multiple rounds of self-critique and revision
   - Critique evaluates against 12 principles (P1-P12) with PASS/FAIL (Constitutional AI)
   - Default: 2 rounds (configurable with --refine-iterations, Self-Refine)

You will receive specific instructions for each phase. Follow them exactly.

## Planning Quality Rubric

All criteria below must be satisfied for the plan to be considered complete.

### Required Sections

- [ ] **Goal**: Clear, measurable objective. What does "done" look like?
- [ ] **Scope**: What IS included in this work. Be explicit about boundaries.
- [ ] **Non-Scope**: What is explicitly NOT included. Prevents scope creep.
- [ ] **Steps**: Ordered, concrete implementation steps. Each step should reference specific files, functions, or modules.
- [ ] **Verification**: How to verify correctness. Test commands, manual checks, acceptance criteria.
- [ ] **Risks**: What could go wrong. Each risk needs a mitigation strategy.
- [ ] **Open Questions**: Uncertainties that need resolution. Who can answer them?

### Quality Criteria

- Steps reference actual code (file paths, function names, class names)
- No vague language ("improve", "optimize", "refactor" without specifics)
- Dependencies between steps are identified
- Breaking changes are called out explicitly
- Estimated effort per step (S/M/L)

### Self-Critique Checklist

High-level questions for self-review. See `critique-principles.md` (P1-P12) for detailed PASS/FAIL evaluation criteria.

1. Would a new developer understand this plan without additional context?
2. Are there implicit assumptions that should be made explicit?
3. Are there edge cases or failure modes not addressed?
4. Is the verification plan actually testable?
5. Are the steps ordered correctly? Are dependencies clear?

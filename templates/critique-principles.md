## Critique Principles

Evaluate the plan against EACH principle below. For each one, state **PASS** or **FAIL** with a specific explanation.

### Correctness

P1. **Step ordering**: Every step's dependencies are completed in earlier steps. No circular dependencies.
P2. **File references**: Every step references specific files that exist in the codebase. No phantom files.
P3. **Interface contracts**: When modifying APIs or interfaces, all callers/consumers are updated.
P4. **Error paths**: Each step that can fail has an explicit error handling or rollback strategy.

### Completeness

P5. **Edge cases**: At least 3 edge cases are identified per major component.
P6. **Verification runnable**: Every verification step is a concrete command that can be copy-pasted and run.
P7. **Breaking changes**: All backward-incompatible changes are identified with migration steps.
P8. **Scope boundaries**: Non-scope items are justified (why excluded, not just listed).

### Clarity

P9. **No vague language**: Zero instances of "improve", "optimize", "clean up", "refactor" without specific actions.
P10. **New developer test**: A developer unfamiliar with the codebase can follow the steps without asking questions.
P11. **Effort estimates**: Every step has an S/M/L estimate with justification.
P12. **Assumption surfacing**: All implicit assumptions are made explicit.

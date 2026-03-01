# Changelog

## [4.0.0] - 2026-03-01

### Removed

- **Reflexion memory**: Session FAIL accumulation/injection across planning sessions (`--no-memory`, `--clear-memory`, `.claude/plansmith-memory.local.md`)
- **CLI options**: `--phases`, `--skip-understand`, `--skip-explore`, `--skip-alternatives`, `--open-critique`, `--completion-promise`, `--required-sections`
- **Bilingual validation**: Korean section heading detection in validators
- **Perspective rotation**: Rotating critique perspectives (technical → maintainability → devil's advocate) replaced with static comprehensive perspective
- **Korean README**: `README.ko.md` removed

### Unchanged

- 6-phase machine (understand → explore → alternatives → draft → critique → revise)
- Tool blocking (Edit/Write/Bash restricted during planning)
- Constitutional AI principle-based critique (P1-P12 PASS/FAIL)
- Self-Refine iterative cycles (`--refine-iterations 1-4`, default 2)
- Remaining CLI options: `--max-phases`, `--max-iterations`, `--refine-iterations`, `--no-block-tools`

## [3.0.0] - 2026-02-28

Initial public release with 6-phase planning, Constitutional AI critique, Self-Refine iteration, Reflexion memory, and Least-to-Most step ordering.

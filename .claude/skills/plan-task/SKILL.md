---
name: plan-task
description: Generate structured implementation plans for complex tasks before coding. Explores the codebase, identifies critical files, designs an approach, and breaks work into concrete steps saved to .claude/plans/.
allowed-tools: Read, Glob, Grep, Write, Bash(git branch *), Bash(git log *)
---

# Plan Task Skill

Generate a structured implementation plan for a complex task before writing any code.

Usage: `/plan-task [description of the task]`

Steps:

1. Read the task description from $ARGUMENTS. If none provided, ask the user to describe the task.
2. Explore the codebase to understand the relevant context:
    - Identify the scripts, tests, and docs affected by this task.
    - Read key files to understand existing patterns and conventions.
    - Re-read the traps in CLAUDE.md — most constraints in this repo live there, not in the code.
3. Design the implementation approach:
    - Identify the entry point and affected layers (hook, notifier script, click handler, setup script, tests).
    - Honor the one rule: a hook must never break the user's session — every failure path exits 0 silently.
    - Consider platform differences (macOS vs Linux) and how the change will be tested without a real banner.
4. Break the work into concrete, ordered steps. Each step should be:
    - A single logical unit of work (one file or one concern)
    - Actionable (e.g. "Add tty matching to `open-session.sh` using `ps ax -o tty=,command=`")
    - Sized for ~1 commit
5. Save the plan to `.claude/plans/YYYY-MM-DD-[kebab-case-task-name].md` (create the
   directory if needed). Plans are personal working documents and are gitignored —
   only `git add` one when explicitly asked.
6. Use this structure:

```markdown
# Plan: [Task Title]

Date: [today's date]
Branch: [current branch if derivable]

## Goal

[1-2 sentence summary of what this achieves and why]

## Affected Files

- [list of files to create or modify]

## Implementation Steps

1. [Step description] — `path/to/file.sh`
2. ...

## Open Questions

- [Any ambiguities that need user input before coding starts]

## Out of Scope

- [Explicitly what this plan does NOT cover]
```

7. After saving the plan, display it to the user and ask:
    > "Plan saved to `.claude/plans/[YYYY-MM-DD]-[name].md`. Would you like me to start implementing it now?"

If the user says yes, begin executing the steps in order, marking each complete before moving to the next.
Do not write any implementation code until the plan is saved and the user confirms.

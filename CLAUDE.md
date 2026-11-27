@AGENTS.md

## Claude Code specifics

- Before every `git commit`, ask the maintainer for approval with AskUserQuestion (files plus message). Approval for one commit doesn't cover the next.
- Run the lint and test commands from AGENTS.md before proposing a commit, and report any failures as they are.
- When a fact about Ubuntu, ROS or Packer plugins might be stale (release names, URLs, plugin addresses), check it online instead of relying on memory.

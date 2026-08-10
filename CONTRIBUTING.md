# Contributing

Contributions are welcome, whether that's a bug report, a feature suggestion, or a pull request.

## Using AI tools

Using AI assistants (Claude, Copilot, ChatGPT, or anything else) to help write a contribution is fine. This project's own history includes AI-assisted work. What matters is the result, not how you got there.

That said, if you submit AI-assisted code:

- You are responsible for it. Read it, understand it, and be able to explain why it works and why it's the right approach, the same as you would for code you wrote by hand.
- Don't submit output you haven't verified. If you can't explain a design decision or a line of code in your own words, it isn't ready to submit.
- Be able to justify the technical choices, not just the fact that it runs. "The AI suggested it" is not a rationale a reviewer can act on.
- Test it. AI-generated GLua in particular tends to hallucinate functions, hooks, or realm boundaries that don't exist. Run it in-game before opening a PR. Pay special attention to permission checks (faction rank permissions vs. server staff usergroups are two separate systems here, see ARCHITECTURE.md) since a broken check is a security bug, not just a functional one.

## Submitting changes

1. Open an issue first for anything non-trivial, so the approach can be discussed before you put time into it.
2. Keep pull requests focused. One change, one PR.
3. Match the existing code style (no trailing comments explaining what code already says, consistent naming with the surrounding file, etc.).
4. Describe what changed and why in the PR description.

## Reporting bugs

Include repro steps, what you expected, what happened instead, and relevant console output.

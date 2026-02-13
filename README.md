# mittwald AI Developer Tools

This repository contains developer tools that help teams work faster with AI hosted by [mittwald](https://www.mittwald.de/mstudio/ai-hosting) in Germany.

mittwald AI hosting is especially useful for developer workflows that need:
- short feedback loops during coding
- reliable automation for continuous integration
- GDPR-aware, Germany-hosted infrastructure for AI-assisted development

## Generate Commit Messages

AI-powered, well-formed git commit message generation based on your staged changes.

### Why this helps

Good commit messages are important but easy to postpone. AI-assisted generation helps you:
- keep commit history understandable and review-friendly
- consistentely follow the [Conventional Commits](https://www.conventionalcommits.org/) format
- reduce time spent writing commit text
- improve consistency across contributors

### What the installer does

The installer script sets up and configures `cmai` so commit messages can be generated using mittwald AI.

### Quick install

```bash
curl -fsSL https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh | bash
```

### Typical workflow

1. Stage your changes (`git add ...`).
2. Commit your changes, ommitting the commit message (`git commit`).
3. `cmai` uses mittwald AI to generate a commit message.
4. Review and adjust the message if needed in your editor.
5. 🥳

## More tools coming soon

This repository is intended as a collection point for developer productivity tooling around mittwald AI hosting.

Check back later.

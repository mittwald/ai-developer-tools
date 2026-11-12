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
- consistently follow the [Conventional Commits](https://www.conventionalcommits.org/) format
- reduce time spent writing commit text
- improve consistency across contributors

### What the installer does

The installer script sets up and configures `cmai` so commit messages can be generated using mittwald AI.
See https://github.com/mrgoonie/cmai for more details.

The installer shows each change before it applies the change:

1. Installs the latest `cmai`, if `cmai` is missing or too old. The installer first checks the downloaded script for content that `cmai` has no need for, such as unknown hosts or encoded code, and asks before it installs a script with such content. This check is a heuristic, not a guarantee. The installer needs `sudo` only if it cannot write the link `/usr/local/bin/cmai` itself.
2. Asks for your mittwald AI API key, or takes the key from `MITTWALD_AI_API_KEY`. The key is stored in `~/.config/git-commit-ai/config`, readable only by you.
3. Configures `cmai` to use mittwald AI.
4. Installs a `prepare-commit-msg` hook into your git template directory (default `~/.git-templates`).
5. Optionally adds a snippet to your Vim config, so that `:q` aborts the commit.

Requirements: Linux, `bash`, `git`, `curl` and `jq`.

### Quick install

```bash
curl -fsSL https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh | bash
```

Make sure to run `git init` in your existing repository.

To read the script before you run it, download the script first:

```bash
curl -fsSLO https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh
less install-git-commit-ai.sh
bash install-git-commit-ai.sh
```

To install or update without prompts, for example from a script, pass `--non-interactive`. Every step then takes its default answer. The default answer keeps an existing `prepare-commit-msg` hook from another source and does not install a `cmai` script with unexpected content. In both cases the installer stops.

```bash
curl -fsSL https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh | bash -s -- --non-interactive
```

`git init` does not replace a hook that a repository already has. After an update of the installer, copy the new hook into such a repository:

```bash
cp ~/.git-templates/hooks/prepare-commit-msg "$(git rev-parse --git-path hooks)/"
```

### Typical workflow

1. Run `git init` in your existing repository, if not done already.
2. Stage your changes (`git add ...`).
3. Commit your changes, omitting the commit message (`git commit`).
4. `cmai` uses mittwald AI to generate a commit message.
5. Review and adjust the message if needed in your editor.
6. 🥳

### Good to know

- The hook sends the diff of your staged changes to mittwald AI. Do not stage secrets.
- The hook never blocks a commit. It tries up to 3 times, with time limits of 30, 45 and 68 seconds. If the generation fails, the hook prints the reason and your editor opens without a generated message.
- While you wait, the hook shows a status line such as `1/3 Reading between the hunks...`. The bold, fully colored part of the line grows with the elapsed share of the time limit. Set `NO_COLOR=1` for plain text.
- Press `Ctrl-C` to stop the generation and the commit.

## More tools coming soon

This repository is intended as a collection point for developer productivity tooling around mittwald AI hosting.

Check back later.

## Feedback

Please use this project's [issue tracker](https://github.com/mittwald/ai-developer-tools/issues) to report specific suggestions or issues.

For security-related issues, please refrain from using the public issue tracker or discussion board. Have a look at the [security policy](./SECURITY.md), instead.

Also, please note that the issue tracker is not a support channel for mittwald's hosting products. Please use our regular [support options](https://www.mittwald.de/impressum) to receive product support.

## Contributing

We are happy to accept external contributions to our documentation. See the [Contribution guide](./CONTRIBUTING.md) for more information.

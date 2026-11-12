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

1. Installs the latest `cmai`, if `cmai` is missing or too old. If this installer or the install script of `cmai` installed `cmai`, a newer version replaces it: `cmai` has no version number, so the installer compares the installed script with the latest one. The installer first checks the downloaded script for content that `cmai` has no need for, such as unknown hosts or encoded code, and asks before it installs a script with such content. A newer version with such content does not replace the installed `cmai`, and a failed download keeps it. This check is a heuristic, not a guarantee. The installer needs `sudo` only if it cannot write the link `/usr/local/bin/cmai` itself.
2. Asks for your mittwald AI API key, or takes the key from `MITTWALD_AI_API_KEY`, and stores the key (see [Where the API key is stored](#where-the-api-key-is-stored)).
3. Configures `cmai` to use mittwald AI.
4. Installs a `prepare-commit-msg` hook into your git template directory (default `~/.git-templates`). On Linux and macOS, the hook is in `~/git-commit-ai/prepare-commit-msg` and the template directory has a link to it. `git init` and `git clone` copy this link into a repository, so that an update of the hook reaches every repository.
5. Replaces copies of the hook from this installer with links, in the repository of the current directory and in the repositories below each directory of `--repos` (see [Update the hook in your repositories](#update-the-hook-in-your-repositories)). On Windows, it updates these copies instead.
6. Optionally adds a snippet to your Vim config, so that `:q` aborts the commit.

### Supported systems

| System | Requirements |
| --- | --- |
| Linux | `bash`, `git`, `curl`, `jq` |
| macOS | `git`, `curl` and the `bash` of macOS; `jq` for example from `brew install jq` |
| Windows | [Git for Windows](https://git-scm.com/download/win); `jq` for example from `winget install jqlang.jq` |

On Windows, run the installer in Git Bash. The hook then works for every commit, also from PowerShell or an IDE. The installer puts `cmai` into `~/bin`, which Git Bash has on its `PATH`.

### Where the API key is stored

The installer stores the API key in the keychain of your system, if both of these are true:

- Your system has a keychain that the installer can use: the macOS Keychain, the Windows Credential Manager, or on Linux a keyring with the `secret-tool` command (GNOME Keyring, KWallet).
- Your `cmai` can take the API key from the environment variable `CMAI_API_KEY`. The hook reads the key from the keychain and passes it to `cmai` this way, so that the key is never in a file.

Otherwise the key is in `~/.config/git-commit-ai/config`, which only you can read. When you run the installer again and the two conditions are true, the installer moves the key from that file into the keychain.

To run `cmai` yourself with a key from the keychain, pass the key in the same way, for example on Linux:

```bash
CMAI_API_KEY="$(secret-tool lookup service git-commit-ai account api-key)" cmai
```

### Quick install

```bash
curl -fsSL https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh | bash
```

On Windows, run this command in Git Bash.

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

### Update the hook in your repositories

`git init` does not replace a hook that a repository already has. A repository with a copy of the hook from an older installer keeps that copy. To replace these copies with links to the hook, pass the directories with your repositories to `--repos`:

```bash
curl -fsSL https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh | bash -s -- --repos ~/workspace
```

The installer looks for repositories up to 5 levels below each directory. It changes only hooks from this installer. A repository without the hook, with a hook from another source, or with its own `core.hooksPath` stays as it is.

To link the hook in one repository, run this command in the repository:

```bash
ln -sf ~/git-commit-ai/prepare-commit-msg "$(git rev-parse --git-path hooks)/prepare-commit-msg"
```

On Windows, copy the hook instead:

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
- While you wait, the hook shows a status line such as `1/3 Reading between the hunks...`. The bold, fully colored part of the line grows with the elapsed share of the time limit. When the message is ready, the line becomes `Reading between the hunks... Read it all.`. Set `NO_COLOR=1` for plain text.
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

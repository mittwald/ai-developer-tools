#!/bin/bash
#
# Stand-in for cmai in the tests of install-git-commit-ai.sh. It takes the
# options that the installer, the hook and the git branch-ai command use and
# makes no network request.
# FAKE_CMAI_MODE selects what `--message-only` and `--branch-name-only` do: ok,
# fail or hang. For a branch name, there are also the modes quoted (a name in
# quotes after an empty line) and invalid (text that is no branch name).

CONFIG_DIR="$HOME/.config/git-commit-ai"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# The key from CMAI_API_KEY, or else the key in the key file.
api_key() {
    if [ -n "${CMAI_API_KEY:-}" ]; then
        printf '%s\n' "$CMAI_API_KEY"
    elif [ -f "$CONFIG_DIR/config" ]; then
        cat "$CONFIG_DIR/config"
    fi
}

MESSAGE_ONLY=false
BRANCH_NAME_ONLY=false
# What the branch name is generated from: staged, unstaged or the diff.
BRANCH_SOURCE=staged
while [ "$#" -gt 0 ]; do
    case "$1" in
    --message-only)
        MESSAGE_ONLY=true
        shift
        ;;
    --branch-name-only)
        BRANCH_NAME_ONLY=true
        shift
        ;;
    --unstaged)
        BRANCH_SOURCE=unstaged
        shift
        ;;
    --diff)
        BRANCH_SOURCE="diff-$2"
        shift 2
        ;;
    --clear-model-options)
        rm -f "$CONFIG_DIR/temperature" "$CONFIG_DIR/extra_body"
        shift
        ;;
    --use-custom)
        printf '%s\n' "$2" >"$CONFIG_DIR/base_url"
        shift 2
        ;;
    --model)
        printf '%s\n' "$2" >"$CONFIG_DIR/model"
        shift 2
        ;;
    --temperature)
        printf '%s\n' "$2" >"$CONFIG_DIR/temperature"
        shift 2
        ;;
    --extra-body)
        printf '%s\n' "$2" >"$CONFIG_DIR/extra_body"
        shift 2
        ;;
    --max-output-tokens)
        shift 2
        ;;
    --top-p | --presence-penalty)
        shift 2
        ;;
    --print-config)
        echo "Current configuration:"
        echo "  Base URL:  $(cat "$CONFIG_DIR/base_url" 2>/dev/null)"
        echo "  Model:     $(cat "$CONFIG_DIR/model" 2>/dev/null)"
        if [ -n "$(api_key)" ]; then
            echo "  API Key:   ****"
        else
            echo "  API Key:   Not set"
        fi
        exit 0
        ;;
    *)
        echo "Error: Unknown argument $1"
        exit 1
        ;;
    esac
done

if [ "$MESSAGE_ONLY" = false ] && [ "$BRANCH_NAME_ONLY" = false ]; then
    echo "Error: the stand-in for cmai supports only --message-only and --branch-name-only" 1>&2
    exit 1
fi

case "${FAKE_CMAI_MODE:-ok}" in
ok)
    if [ "$BRANCH_NAME_ONLY" = true ]; then
        echo "feat/generated-from-$BRANCH_SOURCE"
    else
        echo "feat(test): generated message"
        echo
        echo "api-key=$(api_key)"
    fi
    ;;
quoted)
    echo
    echo "  \`feat/quoted-name\`  "
    ;;
invalid)
    echo "Sure! Here is a branch name: feat/x"
    ;;
fail)
    echo "Error: API request failed (HTTP 401): invalid key" 1>&2
    exit 1
    ;;
hang)
    # The loop is a child process, as curl is for cmai. It stops only if the
    # hook stops the whole process group.
    (
        while :; do
            echo beat >>"$FAKE_CMAI_HEARTBEAT"
            sleep 0.2
        done
    )
    ;;
esac

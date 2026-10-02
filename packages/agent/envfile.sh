# Helpers for writing the agent's .env safely. Sourced by install.sh.
#
# HUB_URL and HUB_TOKEN may arrive from the environment (the Escanor app hands out a one-line command that sets them), so
# they are untrusted input. They are validated against strict patterns and written without sed or any shell interpretation:
# `sed -i "s|^HUB_URL=.*|HUB_URL=$HUB_URL|"` turns a value containing `|`, `&` or `\` into a corrupt file, and (GNU sed) a
# value like `x|e;...` into command execution. Bash's own [[ =~ ]] matches the whole string, so a newline cannot hide a second
# setting behind a valid first line.

valid_hub_url()   { [[ ${1-} =~ ^wss?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%/-]*)?$ ]]; }
valid_hub_token() { [[ ${1-} =~ ^[A-Za-z0-9._~+/=-]{16,512}$ ]]; }
valid_vm_name()   { [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]]; }
valid_api_key()   { [[ ${1-} =~ ^[A-Za-z0-9._-]{0,512}$ ]]; }
valid_path()      { [[ -n ${1-} && ${1-} != *[[:cntrl:]]* ]]; }

# set_env_var FILE KEY VALUE -- replace KEY's line (or append it), verbatim, keeping the file owner-only.
set_env_var() {
  local file=$1 key=$2 value=$3 tmp line found=0
  tmp=$(umask 077; mktemp "$file.XXXXXX")
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line == "$key="* ]]; then
      printf '%s=%s\n' "$key" "$value"
      found=1
    else
      printf '%s\n' "$line"
    fi
  done < "$file" > "$tmp"
  if [ "$found" = 0 ]; then printf '%s=%s\n' "$key" "$value" >> "$tmp"; fi
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

# need DESCRIPTION VALIDATOR VALUE -- exit with a clear message when the value is not acceptable.
need() {
  if ! "$2" "$3"; then
    echo "Invalid $1. Refusing to write it into $ENV_FILE." >&2
    exit 1
  fi
}

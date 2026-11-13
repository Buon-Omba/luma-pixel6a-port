# source ./env.sh — local host tools for the port (no sudo needed)
_LUMA_HT="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)/hosttools"
export PATH="$_LUMA_HT/platform-tools:$_LUMA_HT/mkbootimg:$_LUMA_HT/avb:$_LUMA_HT/local/bin:$PATH"

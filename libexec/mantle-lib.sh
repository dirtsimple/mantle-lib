## The Mantle Extension Library for doco

# For caching reasons, this file uses `include` instead of `mdsh-source`
# to load these files.

source ./.envrc

realpath.location "$BASH_SOURCE"; set -- "$REPLY"

include "$1/mantle-api.md"
include "$1/mantle-cli.md"
include "$1/mantle-policies.md"
include "$1/mantle-tags.md"
include "$1/mantle-wp.md"



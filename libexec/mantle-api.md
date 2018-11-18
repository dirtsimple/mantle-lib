## Mantle Core API

### Service Definition

#### `SERVICE`

```shell
SERVICE() {
	# Ensure a service target exists
	target "$1" declare-service

	# parse and save the normalized URL
	parse-url "$2" || return; set -- "$1" "$REPLY" "${@:3}"

	# prep now, run later
	if-not-in defined_services "$1" \
		event on "finalize project" define-service "$@"

	event has "finalize project" define-service "$@" ||
		fail "service '$1' has already been declared with a different URL and/or tags"
}

```
#### Tag Registration and Application

```shell
before-tag() { event on "before tag $1" "${@:2}"; }
after-tag()  { event on  "after tag $1" "${@:2}"; }

tag-exists() { fn-exists "tag.$1" || event has "before tag $1" || event has "after tag $1"; }
apply-tags() { for REPLY; do if-new-in-array SERVICE_TAGS "$REPLY" __apply_tag "$REPLY"; done; }

__apply_tag() {
	tag-exists "$1" ||
		fail "Undefined tag '$1' for '$SERVICE'${tag_chain:+ (via $tag_chain)}" || return
	local tag_chain=${tag_chain:+$tag_chain, }$1
	event emit "before tag $1"; ! fn-exists "tag.$1" || "tag.$1"; event emit "after tag $1"
}

```

#### Handling Newly-Created Services

```shell
deploy-service() {
	[[ -d deploy ]] || mkdir deploy || exit
	.env -f "$DEPLOY_ENV" puts "# $SERVICE environment"

	# don't allow config changes during "deploy service" event
	eval "${env[@]@A}; ${env_files[@]@A}"  # locally clone so we can add DEPLOY_ENV later
	readonly image env labels volumes env_files

	event emit "deploy service" "$SERVICE"
	event emit "deploy service $SERVICE"
}

```

### Service Definition

```shell
define-service() {
	SERVICES "$1"
	local -r SERVICE=$1 SERVICE_URL=$2 DEPLOY_ENV="./deploy/$1.env"
	local SERVICE_TAGS=()
	local service_namespace image env_files=() volumes=(); local -A env labels
	FILTER "( . "; APPLY . SERVICE SERVICE_URL

	env-file -q ./deploy/@all.env
	event emit "define service" "$SERVICE"
	event emit "define service $SERVICE"

	apply-tags "${@:3}"
	! fn-exists "${service_namespace:-service}.$SERVICE" || "${service_namespace:-service}.$SERVICE"

	event emit "defined service $SERVICE"
	event emit "defined service" "$SERVICE"

	[[ -f "$DEPLOY_ENV" ]] || deploy-service "$@"
	env-file "$DEPLOY_ENV"

	FILTER '( .services[$SERVICE] |= ( .'
	put-string image       ${image+"$image"}
	put-map    environment env
	put-map    labels      labels
	put-list   volumes     "${volumes[@]}"
	FILTER ". )))"
}

put-map()    {                       JSON-MAP "$2";      put-struct "$1" "$REPLY"; }
put-list()   { (($#>1)) || return 0; JSON-LIST "${@:2}"; put-struct "$1" "$REPLY"; }
put-string() { (($#>1)) || return 0; JSON-QUOTE "$2";    put-struct "$1" "$REPLY"; }
put-struct() { FILTER ".$1 |= jqmd_data($2 | mantle::uninterpolate)"; }

expose() { for REPLY; do [[ ! ${!REPLY+_} ]] || env["$REPLY"]=${!REPLY}; done; }

env-file() {
	local q='' f; [[ ${1-} != -q ]] || { q=y; shift; }
	for f; do
		[[ $f != *%s.env ]] || f=${f/%"%s.env"/"$SERVICE.env"}
		if [[ -f "$f" ]]; then
			if-new-in-array env_files "$f" load-env "$f"
		elif [[ ! $q ]]; then
			fail ".env file $f does not exist" || return
		fi
	done
}

load-env() {
	! .env -f "$1" parse ||
		for REPLY in "${REPLY[@]}"; do env["${REPLY%%=*}"]="${REPLY#*=}"; done
}
```

### Misc. Configuration

```shell
fn-exists .env || source dotenv

doco-target::is-created() {
	project-name "$TARGET_NAME"; [[ "$(docker ps -aqf name="$REPLY")" ]]
}
doco-target::is-started() {
	project-name "$TARGET_NAME"; [[ "$(docker ps -qf name="$REPLY")" ]]
}

include-if-exists() { while (($#)); do [[ ! -f "$1" ]] || include "$1"; shift; done; }

if-not-in() { local -n v=$1; [[ ${v-} != *"<$2>"* ]] || return 0; v+="<$2>"; "${@:3}"; }

in-array() { local -n __inarray=$1; [[ "< ${__inarray[*]/%/ ><} " == *"< $2 >"* ]]; }

if-new-in-array() {
	if in-array "$1" "$2"; then return; fi
	local -n __inarray=$1; __inarray+=("$2"); "${@:3}"
}
```

### URL Parsing

The `parse-url` function parses an absolute URL in `$1` and sets `REPLY` to an array containing:

* The URL normalized to include a trailing `/`
* The URL scheme
* The URL host
* The URL port (or an empty string)
* The URL path (or an empty string if no non-`/` path was included)

```shell
parse-url() {
	[[ $1 =~ ([^:]+)://([^/:]+)(:[0-9]+)?(/.*)$ ]] || loco_error "Invalid site URL: $1"
	REPLY=("${BASH_REMATCH%/}/" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]#:}"  "${BASH_REMATCH[4]%/}")
}
```

### jq functions

```coffeescript +DEFINE
# This code is actually jq, not coffeescript, but github and my editor don't speak jq :(
def mantle::uninterpolate:
	# escape '$' to prevent interpolation
    if type == "string" then
        . / "$" | map (. + "$$") | add | .[:-2]
    elif type == "array" then
        map(mantle::uninterpolate)
    elif type == "object" then
        to_entries | map( .value |= mantle::uninterpolate ) | from_entries
    else .
    end
;
```


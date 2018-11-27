## Policies

Policies are singletons that control required aspects of a mantle project, such as database administration, credential assignment, and routing.  For each policy type, there is a variable indicating which policy is actually in use, and it becomes read-only once the policy is selected, which happens at project finalization if the policy isn't used before that point.

```shell
event on "finalize project" event resolve "select policies"

policy() {
	policy-type-exists "$1" || fail "Policy type '$1' doesn't exist" || return
	"policy.$@"
}

policy-type-exists() { fn-exists "policy.$1"; }

policy-type() {
	! policy-type-exists "$1" || fail "policy type '$1' already defined" || return
	event quote "$@"
	eval "policy.$1() { select-policy $REPLY && policy.$1 \"\$@\"; }"
	event on "select policies" select-policy "$@"
}

select-policy() {
	policy-type-exists "$1" || fail "policy type '$1' doesn't exist" || return
	local -n selected=$2; [[ ${selected+_} ]] || selected=$3
	fn-exists "$1.$selected" || fail "$1 policy '$selected' does not exist" || return
	readonly "$2"; eval "policy.$1() { $1.$selected \"\$@\"; }"
	"$1.$selected" init  # initialize the policy
}
```

### The Policy Base Class

`policy` is the base class for all policies, providing default implementations of the methods shared by all policy types.  In particular, policies have:

* an `init` that's called when the policy is selected
* a `project-config` that's called by the default `init`
* `define-service` and `defined-service` methods that get called before and after each linked service definition
* a `deploy-service` that's called when a linked service's deployment `.env` is created

```shell
policy::init() {
	event on "finalize project" "$this" finalize-config
	this project-config
}

policy::link-service() {
	event on "define service $1"  "$this" define-service
	event on "defined service $1" "$this" defined-service
	event on "deploy service $1"  "$this" deploy-service
}

policy::project-config() { :; }
policy::finalize-config() { :; }
policy::define-service() { :; }
policy::defined-service() { :; }
policy::deploy-service() { :; }
```

## Database Administration

The DBA policy is set using the `DBA_POLICY` variable, and it defaults to the `project-db` policy.  The base class is `dba-policy`, which understands how to create and drop users and generate database passwords.

```shell
doco.dba() {
	if (($#)); then
		if have-services ==1; then
			target "${DOCO_SERVICES[0]}" with-env policy dba "$@"
		elif require-services 1 dba; then
			with-targets "${REPLY[@]}" -- doco foreach dba "$@"
		fi
	else
		policy dba cli mysql
	fi
}

policy-type dba DBA_POLICY project-db

gen-dbpass() { openssl rand -base64 18; }
sql-escape() { set -- "${@//\\/\\\\}"; set -- "${@//\'/\\\'}"; REPLY=("$@"); }

dba-policy::deploy-service() {
	.env -f "${DEPLOY_ENV}" generate DB_PASSWORD gen-dbpass
	event on "before commands" target "$SERVICE" with-env policy dba mkuser
}

dba-policy::mkuser() {
	sql-escape "$DB_USER" "$DB_PASSWORD"
	printf \
		"GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'%%' IDENTIFIED BY '%s'; FLUSH PRIVILEGES;" \
		"$DB_NAME" "${REPLY[0]}" "${REPLY[1]}" | this cli mysql
}

dba-policy::drop() {
	sql-escape "$DB_USER"
	printf "DROP DATABASE IF EXISTS \`%s\`; DROP USER '%s'@'%%'; FLUSH PRIVILEGES;" \
		"$DB_NAME" "$REPLY" | this cli mysql
}

dba-policy::dba-command() { fail "policy '$DBA_POLICY' needs a dba-command method"; }

dba-policy::cli() { this dba-command mysql "${1-${DB_NAME-mysql}}"; }
dba-policy::dump() { this dba-command mysqldump --single-transaction "$@" "$DB_NAME"; }
```

### The external-db policy

The `external-db` policy uses a database host that is not part of the project.  It requires that `DB_HOST` and `DBA_LOGIN_PATH` (a `--login-path` for the mysql CLI) be set, in order to set up databases.  The user and database names for a site are set using the site's `SERVICE_URL`, to ensure uniqueness.

```shell
dba.external-db() { local this=$FUNCNAME __mro__=(external-db dba-policy policy); this "$@"; }

external-db::project-config() {
	for REPLY in DB_HOST DBA_LOGIN_PATH; do
		[[ ${!REPLY+_} ]] || fail "$REPLY must be set to use external-db policy" 78 || exit
	done
}

external-db::dba-command() { "$1" --login-path="$DBA_LOGIN_PATH" "${@:2}"; }

external-db::deploy-service() {
	project-name "$SERVICE"; local dbu=mantle-${REPLY%_1}
	parse-url "$SERVICE_URL"; local dbn="mantle${REPLY[1]#http}-${REPLY[2]}"
	dbn+="${REPLY[3]:+:${REPLY[3]}}${REPLY[4]:+-${REPLY[4]//\/^}}"
	.env -f "$DEPLOY_ENV" set +DB_USER="$dbu" +DB_NAME="${dbn//./_}" +DB_HOST="$DB_HOST"
	dba-policy::deploy-service "$@"
}
```

### The project-db policy

The `project-db` dba policy implements a project-local mysql service, making each site depend on it.  A newly generated database's name and user ID are the site's service name.

```shell
dba.project-db() { local this=$FUNCNAME __mro__=(project-db dba-policy policy); this "$@"; }

project-db::finalize-config() {
	# Make sure we have a root password
	this .env generate MYSQL_ROOT_PASSWORD gen-dbpass
}

project-db::.env() { .env -f ./deploy/mysql.env "$@"; }

project-db::up() {
	! target mysql is-started || return 0

	if target mysql is-created; then
		doco -- mysql start
	else
		doco -- mysql up -d
		while [[ ! -f deploy/db/client-key.pem ]]; do sleep .1; done
		while read -r -t 2; do :; done < <(doco -- mysql tail)
	fi

	this .env parse MYSQL_ROOT_PASSWORD ||
		fail "./deploy/mysql.env is missing its password" || return
	local "${REPLY[@]}"  # read password

	doco -- mysql exec -T mysql_config_editor set --skip-warn -G mantle \
		-h localhost -u root -p <<<"$MYSQL_ROOT_PASSWORD" 2>/dev/null
}

project-db::dba-command() {
	this up; REPLY=; [[ -t 0 && -t 1 ]] || REPLY=-T   # don't use pty unless interactive
	doco -- mysql exec $REPLY "$1" --login-path=mantle "${@:2}"
}

project-db::deploy-service() {
	.env -f "$DEPLOY_ENV" set +DB_USER="$SERVICE" +DB_NAME="$SERVICE" +DB_HOST=mysql
	dba-policy::deploy-service "$@"
}
```

The database is implemented as an auto-restarting service named `mysql`, with its data stored in `./deploy/db`:

```yaml @func project-db::project-config
# project-db::project-config
services:
  mysql:
    image: mysql
    restart: always
    env_file: ./deploy/mysql.env
    volumes:
      - ./deploy/db:/var/lib/mysql
```

Each linked service is marked as dependent on the mysql service, so it will start if they start.

```yaml @func project-db::define-service
# project-db::define-service
services:
  \($SERVICE):
    depends_on: [ mysql ]
```


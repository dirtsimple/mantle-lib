# Mantle CLI

## Developer Commands

These commands execute their arguments inside exactly one service container, as the developer user.  If no services are specified, the default is to run against the `dev` container.

### asdev

Run the specified command line inside the container using the `as-developer` tool.

```shell
doco.asdev() {
	require-services 1 asdev exec || return
	local target=$REPLY
	target "$target" is-started || doco up -d
	set -- as-developer "$@"
	[[ -t 1 ]] || set -- -T "$@"
	doco "$target" exec "$@"
}
```

### wp

```shell
doco.wp() { doco asdev env PAGER='less' LESS=R wp "$@"; }
```

### db

```shell
doco.db() { doco wp db "$@"; }
```

### composer

```shell
doco.composer() { doco asdev composer "$@"; }
```

### imposer

```shell
doco.imposer() { doco asdev imposer "$@"; }
```


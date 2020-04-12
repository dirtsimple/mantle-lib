## Wordpress Sites

```shell
SITE() { WORDPRESS "$@"; }   # backward-compatibility, for now

WORDPRESS() {
	# Make the service part of the sites and wp groups
	GROUP --sites --wp += "$1"
	SERVICE "$1" "$2" mantle-site "${@:3}"
	event on "define service $1" mantle-wp "$@"
	policy dba link-service "$1"
}

mantle-wp() {
	env[WP_ENV]=$3
	env[WP_HOME]=$SERVICE_URL
	env[WP_ADMIN_EMAIL]=${WP_ADMIN_EMAIL:-$USER@$HOSTNAME}
	expose WP_ADMIN_USER WP_ADMIN_PASS
	image="dirtsimple/mantle-site:latest"
	service_namespace=site
	event on "deploy service $SERVICE" generate-wp-keys
}

# Generate Wordpress salts and keys when a site is deployed
generate-wp-keys() {
	set -- AUTH SECURE_AUTH LOGGED_IN NONCE
	.env -f "$DEPLOY_ENV"
	while (($#)); do
		.env generate "$1_KEY"  openssl rand -base64 48
		.env generate "$1_SALT" openssl rand -base64 48
		shift
	done
}

```


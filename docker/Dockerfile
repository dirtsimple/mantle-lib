FROM dirtsimple/php-server:1.4.2

RUN EXTRA_APKS="less nano bind-tools mysql-client py2-pygments git-perl colordiff" install-extras \
    && composer-global psy/psysh:@stable wp-cli/wp-cli-bundle dirtsimple/imposer:dev-master dirtsimple/postmark:dev-master

COPY mantle-startup /usr/bin/

ENV RUN_SCRIPTS    "/usr/bin/mantle-startup"
ENV PHP_CONTROLLER "true"
ENV PHP_MEM_LIMIT  "256"

ENV PUBLIC_DIR "public"

ENV NGINX_OWNED    "public/ext/uploads"
ENV NGINX_WRITABLE "public/ext/uploads"
ENV NGINX_READABLE "public vendor"
ENV NGINX_NO_WRITE "."
ENV EXCLUDE_PHP    "/ext/uploads"

# wp-cli needs these for proper paging
ENV PAGER "less"
ENV LESS  "R"

ENV IMPOSER_THEMES   "public/ext/themes"
ENV IMPOSER_PLUGINS  "public/ext/plugins"
ENV IMPOSER_VENDOR   "vendor"
ENV IMPOSER_PACKAGES "/home/developer/.wp-cli/packages/vendor"
ENV IMPOSER_GLOBALS  "/composer/vendor"

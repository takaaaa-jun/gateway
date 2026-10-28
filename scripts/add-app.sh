#!/bin/sh
# Generate an Nginx location configuration without overwriting existing files.
set -eu

if [ "$#" -gt 1 ]; then
    printf 'Usage: sh scripts/add-app.sh [app-name]\n' >&2
    exit 1
fi

app_name=${1-}
if [ "$#" -eq 0 ]; then
    printf 'App name: '
    read -r app_name
fi

case "$app_name" in
    ''|*[!a-z0-9_-]*|[!a-z0-9]*)
        printf 'Use lowercase letters, digits, hyphens or underscores; start with a letter or digit.\n' >&2
        exit 1
        ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output="$script_dir/../conf.d/$app_name.conf"

# noclobber also prevents accidental overwrites when two commands run together.
if ! (set -C; cat > "$output" <<EOF
# Generated for $app_name. Both services must join shared-gateway-net.
location = /$app_name {
    set \$upstream_app http://$app_name-frontend:80;
    proxy_pass \$upstream_app;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Prefix /$app_name;
}

location = /$app_name/api {
    return 308 /$app_name/api/\$is_args\$args;
}

location /$app_name/api/ {
    set \$upstream_api http://$app_name-backend:8000;
    rewrite ^/$app_name/api/(.*)\$ /api/\$1 break;
    proxy_pass \$upstream_api;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}

location /$app_name/ {
    set \$upstream_app http://$app_name-frontend:80;
    proxy_pass \$upstream_app;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Prefix /$app_name;
}
EOF
); then
    printf 'Could not create %s. Check whether the file already exists or is writable.\n' "$output" >&2
    exit 1
fi

printf 'Created conf.d/%s.conf\n' "$app_name"

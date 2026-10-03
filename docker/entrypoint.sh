#!/bin/sh
set -eu

/app/bin/eventbus eval "Eventbus.Release.migrate()"
exec env PHX_SERVER=true /app/bin/eventbus start

#!/bin/sh
set -e
command -v python3 >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq python3 >/dev/null; }
exec python3 -m unittest discover -s sondpkg/tests -v

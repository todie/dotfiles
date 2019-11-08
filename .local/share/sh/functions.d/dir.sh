#!/bin/sh
function lsp { ls -lah --color=always "$@" | less -R; }

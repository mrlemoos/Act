#!/bin/zsh
set -eu
cd "${0:A:h}/.."
bun CLI/contract.ts --check
bun build --compile --minify --outfile .build/act CLI/src/main.ts

#!/bin/sh

set -eux

func="$(cat func-tmp.txt)"
url="https://us-central1-prisma-e2e-tests-265911.cloudfunctions.net/$func"
prisma_version="$(cat ../../.github/prisma-version.txt)"

if [ "$PRISMA_CLIENT_ENGINE_TYPE" == "binary" ]; then
  files=',"files":["edge.d.ts","edge.js","index-browser.js","index.d.ts","index.js","package.json","query-engine-debian-openssl-1.1.x","schema.prisma"]'
else
  files=',"files":["edge.d.ts","edge.js","index-browser.js","index.d.ts","index.js","libquery_engine-debian-openssl-1.1.x.so.node","package.json","schema.prisma"]'
fi

expected='{"version":"'$prisma_version'","createUser":{"id":"12345","email":"alice@prisma.io","name":"Alice"},"updateUser":{"id":"12345","email":"bob@prisma.io","name":"Bob"},"users":{"id":"12345","email":"bob@prisma.io","name":"Bob"},"deleteManyUsers":{"count":1}'${files}'}'
actual=$(curl "$url")

if [ "$expected" != "$actual" ]; then
  echo "expected '$expected'"
  echo " but got '$actual'"
  exit 1
fi

echo "result: $actual"

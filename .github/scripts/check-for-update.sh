#!/bin/bash

set -eu
shopt -s inherit_errexit || true

cd .github/slack/
yarn install
cd ../..

npm i -g json

branch="$1"

no_negatives() {
  echo "$(($1 < 0 ? 0 : $1))"
}

run_sync() {
  dir="$1"
  branch="$2"
  cd "$dir"
  bash .github/scripts/sync.sh "$branch"
  echo "synced, exit."
  exit 0
}

echo ""
echo "=========================="
echo "setting up ssh repo"

mkdir -p ~/.ssh
echo "$SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh-keyscan github.com >> ~/.ssh/known_hosts

git config --global user.email "prismabots@gmail.com"
git config --global user.name "Prismo"

git remote add github "git@github.com:$GITHUB_REPOSITORY.git"
git fetch github "$branch"
git reset --hard "github/$branch"
git checkout "github/$branch"

# prepare script: read package.json but ignore workspace package.json files, redwood "web" package.json file
pkg="var pkg=require('./package.json'); if (pkg.workspaces || pkg.name == '.prisma/client' || pkg.name == 'web') { process.exit(0); }"

# since GH actions are limited to 5 minute cron jobs, just run this continuously for 5 minutes
minutes=5   # cron job runs each x minutes
interval=10 # run each x seconds
i=0
count=$(((minutes * 60) / interval))
echo ""
echo "=========================="
echo "running loop $count times"
while [ $i -le $count ]; do
  # increment to prevent forgetting incrementing, and also prevent overlapping with the next 5-minute job
  i=$((i + 1))
  echo ""
  echo "=========================="
  echo "run $i"

  start=$(date "+%s")

  dir=$(pwd)

  echo "=========================="
  echo "updating git checkout"
  git fetch github "$branch"
  git reset --hard "github/$branch"

  echo "=========================="
  echo "getting package version:"
  v=$(bash .github/scripts/prisma-version.sh "$branch")
  echo "$v (via Npm)"
  
  packages=$(find . -not -path "*/node_modules/*" -type f -name "package.json")
  echo "$packages" | tr ' ' '\n' | while read -r item; do
    echo "=========================="
    echo "checking $item"

    case "$item" in
    *".github"* | *"functions/generated/client"*)
      echo "ignoring $item"
      continue
      ;;
    esac

    cd "$(dirname "$item")/"

    hasResolutions="$(node -e "$pkg;console.log(!!pkg.resolutions)")"

    if [ "$hasResolutions" = "true" ]; then
      echo "note: project uses `resolutions`"
      vCLI="$(node -e "$pkg;console.log(pkg.resolutions['@prisma/cli'])")"

      if [ "$vCLI" != "" ]; then
        if [ "$v" != "$vCLI" ]; then
          if [ "$branch" != "dev" ]; then
            run_sync "$dir" "$branch"
          fi

          echo "$item: @prisma/cli expected $v, actual $vCLI"
          json -I -f package.json -e "this.resolutions['@prisma/cli']='$v'"
        fi

        vPrismaClient="$(node -e "$pkg;console.log(pkg.resolutions['@prisma/client'])")"

        if [ "$v" != "$vPrismaClient" ]; then
          if [ "$branch" != "dev" ]; then
            run_sync "$dir" "$branch"
          fi

          echo "$item: @prisma/client expected $v, actual $vPrismaClient"
          json -I -f package.json -e "this.resolutions['@prisma/client']='$v'"
        fi
      fi
    else
      vCLI="$(node -e "$pkg;console.log(pkg.devDependencies['@prisma/cli'])")"

      if [ "$vCLI" != "" ]; then
        if [ "$v" != "$vCLI" ]; then
          if [ "$branch" != "dev" ]; then
            run_sync "$dir" "$branch"
          fi

          echo "$item: @prisma/cli expected $v, actual $vCLI"
          yarn add "@prisma/cli@$v" --dev
        fi

        vPrismaClient="$(node -e "$pkg;console.log(pkg.dependencies['@prisma/client'])")"

        if [ "$v" != "$vPrismaClient" ]; then
          if [ "$branch" != "dev" ]; then
            run_sync "$dir" "$branch"
          fi

          echo "$item: @prisma/client expected $v, actual $vPrismaClient"
          yarn add "@prisma/client@$v"
        fi
      else
        echo "Dependency not found"
      fi
    fi

    cd "$dir"
  done

  echo ""
  echo "=========================="
  echo "after upgrade:"
  git status

  if [ -z "$(git status -s)" ]; then
    echo "no changes"
    end=$(date "+%s")
    diff=$(echo "$end - $start" | bc)
    remaining=$((interval - 1 - diff))
    echo "took $diff seconds, sleeping for $remaining seconds"
    sleep "$(no_negatives $remaining)"

    continue
  fi

  echo ""
  echo "=========================="
  echo "changes, upgrading..."
  echo "$v" > .github/prisma-version.txt

  git commit -am "chore(packages): bump @prisma/cli to $v"

  git pull github "$branch" --rebase

  set +e
  git push github "HEAD:refs/heads/$branch"
  code=$?
  set -e
  echo "pushed commit"

  if [ $code -eq 0 ]; then
    export webhook="$SLACK_WEBHOOK_URL"
    node .github/slack/notify.js "Prisma version $v released (via $branch)"
    export webhook="$SLACK_WEBHOOK_URL_FAILING"
    node .github/slack/notify.js "Prisma version $v released (via $branch)"
  fi

  end=$(date "+%s")
  diff=$(echo "$end - $start" | bc)
  remaining=$((interval - 1 - diff))
  # upgrading usually takes longer than a few individual loop runs, so skip test runs which would have passed by now
  skip=$((remaining / interval))
  i=$((i - skip))
  echo "took $diff seconds, skipping $skip x $interval second runs"
done

echo "done"

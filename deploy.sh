#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

set -o errexit -o nounset

rev=$(git rev-parse --short HEAD)

# Deploys the contents of public/ to the master branch
cd public/

git init
git config user.name "Engineering Blog Builder"
git config user.email "noreply@sendence.com"

echo -e "Fetching upstream..."

git remote add upstream "https://$GH_TOKEN@github.com/sendence/engineering.sendence.com"
git fetch upstream
git reset upstream/master

touch .

echo -e "Committing and pushing to upstream..."

git add -A .
git commit -m "rebuild website from revision ${rev} of source branch"
git push -q upstream HEAD:master

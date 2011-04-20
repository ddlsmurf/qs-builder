#!/bin/bash
if [[ -d .git ]]; then
  current_head=`cat .git/HEAD`
  if [[ "$current_head" != "ref: refs/heads/master" ]]; then
    echo "Run from master branch please"
    exit
  fi
  master_commit=`cat .git/refs/heads/master`
  git stash
  rdoc
  mv doc new_doc || exit
  git checkout gh-pages || exit
  rm -rf doc
  mv new_doc doc
  git add -A doc
  git commit -m "Doc update from source at commit $master_commit"
  git checkout master
  echo "You might want to git stash pop and/or git push origin gh-pages"
else
  echo "Run from the root of the repository !"
fi

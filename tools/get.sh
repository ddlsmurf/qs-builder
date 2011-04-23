#!/bin/bash
if [[ -d .git ]]; then
  ruby -rubygems <<RUBY > data/plugin_reference.txt
  require 'media_wiki'
  puts MediaWiki::Gateway.new("http://qsapp.com/w/api.php").get("Plugin_Reference")
RUBY
  curl 'https://gist.github.com/raw/938822/a15edd6aa81459a32dfb525fc6651b8e826e2215/gistfile1.txt' > data/repo_locations.txt
else
  echo "Run from the root of the repository !"
fi

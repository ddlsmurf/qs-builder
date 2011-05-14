#!/bin/bash
if [[ -d .git ]]; then
  ruby -rubygems <<RUBY
  require 'media_wiki'
  def get(page)
    @gw ||= MediaWiki::Gateway.new("http://qsapp.com/w/api.php")
    text = @gw.get(page)
    File.open("data/#{page.gsub(" ", "_")}.txt", "w") { |file| file.write(text) }
    text
  end
  ref = get("Plugin_Reference")
  ref.scan(/\[\[([^\]]+)\]\]/).map(&:first).uniq.sort.each {|f| get(f) }
RUBY
  curl 'https://gist.github.com/raw/938822/a15edd6aa81459a32dfb525fc6651b8e826e2215/gistfile1.txt' > data/repo_locations.txt
else
  echo "Run from the root of the repository !"
fi

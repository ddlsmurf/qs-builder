#!/bin/bash
if [[ -d .git ]]; then
#   ruby -rubygems <<RUBY
#   require 'media_wiki'
#   def get(page)
#     @gw ||= MediaWiki::Gateway.new("http://qsapp.com/w/api.php")
#     text = (@gw.get(page) || "").strip
#     if text.length > 0
#       File.open("data/#{page.gsub(" ", "_")}.txt", "w") { |file| file.write(text) }
#     end
#     text
#   end
#   ref = get("Plugin_Reference")
#   ref.scan(/\[\[([^\]]+)\]\]/).map(&:first).uniq.sort.each {|f| get(f) }
# RUBY
  curl 'http://qsapp.com/plugins/' -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/534.36 (KHTML, like Gecko) Chrome/13.0.766.0 Safari/534.36' > data/qsapp_com_plugins.html
  curl 'https://gist.github.com/raw/938822/a15edd6aa81459a32dfb525fc6651b8e826e2215/gistfile1.txt' > data/repo_locations.txt
else
  echo "Run from the root of the repository !"
fi

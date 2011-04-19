## QuickSilver plugin plist template tool ##

### Synopsis ###

Searches a list of folders containing `*.qsplugin/Contents/Info.plist`, applies matching overrides,
run a template with the data for each entry.

Base use case is generating wiki pages for documenting QuickSilver plugins.

### Examples ###

`./bundle_reader.rb -o overrides/ -t basic -p plugins/ --wiki-prefix Auto/ '*'`

Runs the template in basic/init.rb into out/

### Templates ###

Template engine is handled by [Tilt](https://github.com/rtomayko/tilt/blob/master/TEMPLATES.md),
so you can use Markdown, haml and what not.

Partials are relative to the template path provided with the `-t basic` flag, so the partial
for `item` is in `basic/partials/_item.erb`.

Upon loading a template, it's `init.rb` file is required. That's all that happens, so make it count.
Templates can access the App instance through `App.shared`.

The template has all the bundle information available as methods of self
(though this was a bad idea in retrospect). Brackets are very important or Ruby thinks we're talking about
a constant (many keys have capital first letters).

### Override mechanism ###

Use `-o path` to add a path of override files.

For every bundle loaded, the tool looks in any override paths provided for a file named `bundle.id.plist`
(or `bundle.id.yaml`, eg: `overrides/com.blacktree.Quicksilver.QSCorePlugIn.yaml`). Each one is loaded,
and the resulting hash table is 'merged into' the bundle's info plist. The data is then available to
the templates.

Additionally, a key `QSModifiedDate` with the date of last modification of the `.qsbundle`'s folder in the
strftime format `%Y-%m-%d %H:%M:%S %z` is added to the root.

#### Localisations ####

When one or more languages are specified (with `--language en,fr,de,it`), for each override folder specified,
a file is loaded from `language_code/bundle.id.{plist,yaml}`.

Note: No, thats not a good solution for the template text...

### Requirements ###

`sudo gem install plist tilt OptionParser mediawiki-gateway`

## wikirobot.rb ##

A very unpolished method of synchronising the FS with a media wiki. Don't use.

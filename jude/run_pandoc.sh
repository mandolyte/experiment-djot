#!/bin/sh

pandoc -f ../src/djot-reader.lua \
	--css=styles.css \
	--metadata title="Jude" \
	-s \
	-o jude.html \
	jude.djot

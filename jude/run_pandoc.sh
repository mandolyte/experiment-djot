#!/bin/sh

pandoc -f ../src/djot-reader.lua \
	-o jude.html \
	jude.djot

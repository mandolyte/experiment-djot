# experiment-djot
Experiments with the Djot Package

**Using ChromeOS**

*Had to install latest of several things:*

*pandoc*
- Version from Debian not current
- Used https://github.com/jgm/pandoc/releases/tag/2.19 to retrieve the "deb" file and let the debian package installer take it from there

*lua*
- just followed the installation instructions given with luarocks below.
- had to specify on the "configure" step that --with-lua-version=5.4

*luarocks*
- Had to install luarocks to install djot (again debian not current)
- Used https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix


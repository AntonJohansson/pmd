#!/bin/bash

[[ -d ship-linux ]] && rm -r ship-linux
zig build -Doptimize=Debug
mkdir ship-linux
cp zig-out/bin/* ship-linux/
cp zig-out/lib/* ship-linux/
cp -r res ship-linux/
zip -r ship-linux ship-linux

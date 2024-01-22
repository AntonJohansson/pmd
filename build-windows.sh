#!/bin/bash

[[ -d ship-windows ]] && rm -r ship-windows
zig build -Dtarget=x86_64-windows -Doptimize=Debug
mkdir ship-windows
cp zig-out/bin/* ship-windows/
cp zig-out/lib/* ship-windows/
cp -r res ship-windows/
zip -r ship-windows ship-windows

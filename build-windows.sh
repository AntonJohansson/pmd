#!/bin/bash

[[ -d ship ]] && rm -r ship
zig build -Dtarget=x86_64-windows -Doptimize=Debug
mkdir ship
cp zig-out/bin/client.* ship/
cp -r res ship/
zip -r ship ship

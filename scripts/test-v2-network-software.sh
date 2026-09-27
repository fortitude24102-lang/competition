#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v2-network-software
mkdir -p "$out"
flags=(-std=c11 -O2 -Wall -Wextra -Werror -fsanitize=address,undefined
       -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2)
gcc "${flags[@]}" -DGPU_TEST_BACKEND sw/efinix_gpu/tests/test_network_assets.c \
    sw/efinix_gpu/src/network_assets.c sw/efinix_gpu/src/asset_dma.c \
    sw/efinix_gpu/src/asset_protocol.c -o "$out/test_network_assets"
"$out/test_network_assets"
gcc "${flags[@]}" sw/efinix_gpu/tests/test_v2_assets.c \
    sw/efinix_gpu/src/net_asset_server.c sw/efinix_gpu/src/asset_protocol.c \
    sw/efinix_gpu/src/asset_cache.c -o "$out/test_v2_assets"
"$out/test_v2_assets"
gcc -std=c11 -O2 -Wall -Wextra -Werror -Isw/efinix_gpu/include \
    sw/efinix_gpu/tools/asset_server/asset_server.c sw/efinix_gpu/src/asset_protocol.c \
    sw/efinix_gpu/src/net_asset_server.c -o "$out/asset_server"
python3 sw/efinix_gpu/tests/test_asset_server_udp.py "$out/asset_server"

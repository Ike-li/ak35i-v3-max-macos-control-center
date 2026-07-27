#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
output_dir=${AK35I_OUTPUT_DIR:-"${project_dir}/dist"}
app_path="${output_dir}/AK35i Control Center.app"
dmg_path="${output_dir}/AK35i-Control-Center-0.1.0-arm64.dmg"

"${script_dir}/build-app.sh"

if [[ -e "${dmg_path}" ]]; then
    mv "${dmg_path}" "${dmg_path}.previous-$(date +%Y%m%d-%H%M%S)"
fi

hdiutil create \
    -volname "AK35i Control Center" \
    -srcfolder "${app_path}" \
    -format UDZO \
    -ov \
    "${dmg_path}"

print "已生成未公证的本地 DMG：${dmg_path}"

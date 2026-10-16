#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
output_dir=${AK35I_OUTPUT_DIR:-"${project_dir}/dist"}
app_path="${output_dir}/AK35i Control Center.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${project_dir}/Packaging/Info.plist")
dmg_name="AK35i-Control-Center-${version}-universal.dmg"
dmg_path="${output_dir}/${dmg_name}"

AK35I_ARCHS="arm64 x86_64" "${script_dir}/build-app.sh"

archs=$(lipo -archs "${app_path}/Contents/MacOS/ak35i")
if [[ " ${archs} " != *" arm64 "* || " ${archs} " != *" x86_64 "* ]]; then
    print -u2 "打包失败：应用不是通用二进制（${archs}）。"
    exit 1
fi

if [[ -e "${dmg_path}" ]]; then
    mv "${dmg_path}" "${dmg_path}.previous-$(date +%Y%m%d-%H%M%S)"
fi

# The volume shows the app next to an Applications link for drag-and-drop installs.
staging=$(mktemp -d)
trap 'rm -rf "${staging}"' EXIT
ditto "${app_path}" "${staging}/AK35i Control Center.app"
ln -s /Applications "${staging}/Applications"

hdiutil create \
    -volname "AK35i Control Center" \
    -srcfolder "${staging}" \
    -format UDZO \
    -ov \
    "${dmg_path}"

(cd "${output_dir}" && shasum -a 256 "${dmg_name}" > "${dmg_name}.sha256")

print "已生成未公证的通用 DMG：${dmg_path}"

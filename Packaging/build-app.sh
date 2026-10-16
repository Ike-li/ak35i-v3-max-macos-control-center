#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
output_dir=${AK35I_OUTPUT_DIR:-"${project_dir}/dist"}
app_name="AK35i Control Center.app"
app_path="${output_dir}/${app_name}"
staging_path="${output_dir}/.${app_name}.${$}.staging"
timestamp=$(date +%Y%m%d-%H%M%S)

if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# AK35I_ARCHS="arm64 x86_64" builds a universal binary; unset builds for this Mac only.
arch_flags=()
for arch in ${=AK35I_ARCHS:-}; do
    arch_flags+=(--arch "${arch}")
done

cd "${project_dir}"
swift build -c release --disable-sandbox "${arch_flags[@]}"
bin_path=$(swift build -c release --disable-sandbox "${arch_flags[@]}" --show-bin-path)

mkdir -p "${staging_path}/Contents/MacOS"
install -m 644 "${project_dir}/Packaging/Info.plist" "${staging_path}/Contents/Info.plist"
install -m 755 "${bin_path}/ak35i" "${staging_path}/Contents/MacOS/ak35i"

# Finder metadata invalidates an ad-hoc signature. Clear it before signing so
# the bundle can be launched normally from Finder or Launch Services.
xattr -cr "${staging_path}"
codesign --force --deep --sign - "${staging_path}"
codesign --verify --deep --strict --verbose=2 "${staging_path}"
plutil -lint "${staging_path}/Contents/Info.plist"

if xattr -p com.apple.FinderInfo "${staging_path}" >/dev/null 2>&1; then
    print -u2 "打包失败：应用仍带有 Finder 元数据，未替换现有版本。"
    exit 1
fi

mkdir -p "${output_dir}"
if [[ -e "${app_path}" ]]; then
    mv "${app_path}" "${output_dir}/${app_name}.previous-${timestamp}"
fi
mv "${staging_path}" "${app_path}"
cp "${bin_path}/ak35i" "${output_dir}/ak35i"

print "已生成：${app_path}"
print "打开方式：open \"${app_path}\""

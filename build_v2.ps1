# Build libbcn_layer.so (v2-equivalent: upstream + Copy2 + FormatProperties2).
# Follows the proven v1/v2 rebuild pipeline from project memory.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot   # no CJK literals: PS5 reads BOM-less .ps1 as ANSI
$ndk  = 'G:\AndroidSDK\ndk\27.1.12297006'
$glslc = Join-Path $ndk 'shader-tools\windows-x86_64\glslc.exe'
$clang = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe'
$strip = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe'
$nm    = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe'
$python = (Get-Command python -EA SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -EA SilentlyContinue).Source }
if (-not $python) { throw 'python not found' }
"python: $python"

Set-Location $root

# --- 1. compile 8 compute shaders ---
$comps = @('s3tc','s3tc_iv','rgtc','rgtc_iv','bc6','bc6_iv','bc7','bc7_iv')
foreach ($c in $comps) {
  & $glslc "src\$c.comp" -o "src\$c.spv"
  if ($LASTEXITCODE -ne 0) { throw "glslc failed for $c" }
}
"glslc: 8 shaders OK"

# --- 2. xxd -i equivalent -> src/%_spv.h ---
$py = @'
import sys, os
for name in ["s3tc","s3tc_iv","rgtc","rgtc_iv","bc6","bc6_iv","bc7","bc7_iv"]:
    src = os.path.join("src", name + ".spv")
    data = open(src, "rb").read()
    var = name + "_spv"
    with open(os.path.join("src", var + ".h"), "w") as f:
        f.write("unsigned char %s[] = {" % var)
        for i, b in enumerate(data):
            if i % 12 == 0:
                f.write("\n  ")
            f.write("0x%02x," % b)
        f.write("\n};\n")
        f.write("unsigned int %s_len = %d;\n" % (var, len(data)))
    print(var, len(data))
'@
$py | & $python -
if ($LASTEXITCODE -ne 0) { throw 'spv header generation failed' }
"spv headers: 8 OK"

# --- 3. link ---
$sources = Get-ChildItem "$root\src\*.cpp" | ForEach-Object { $_.FullName }
& $clang --target=aarch64-linux-android28 -std=c++17 -O2 -fPIC -Isrc -shared $sources -o "$root\libbcn_layer.so"
if ($LASTEXITCODE -ne 0) { throw 'clang++ link failed' }
"link OK"

# --- 4. strip + verify exports ---
& $strip -o "$root\libbcn_layer_stripped.so" "$root\libbcn_layer.so"
$so = "$root\libbcn_layer_stripped.so"
"size: $((Get-Item $so).Length)"
& $nm -D --undefined-only $so | Out-Null
$exports = & $nm -D --defined-only $so
foreach ($sym in @('BCnLayer_CmdCopyBufferToImage2','BCnLayer_GetPhysicalDeviceFormatProperties2','BCnLayer_CmdCopyBufferToImage','BCnLayer_GetPhysicalDeviceFormatProperties','BCnLayer_CreateInstance','BCnLayer_CreateDevice')) {
  $hit = $exports | Select-String $sym
  "export $sym : $(if ($hit) {'OK'} else {'MISSING'})"
}
"md5: $((Get-FileHash $so -Algorithm MD5).Hash.ToLower())"
"BUILT"

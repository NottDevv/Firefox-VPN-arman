# Prepare generated Flutter Windows plugin files for the Windows 7 SP1 build.
# Run after "flutter pub get": Flutter regenerates these files from plugin metadata.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cmake = Join-Path $root 'app\windows\flutter\generated_plugins.cmake'
$registrant = Join-Path $root 'app\windows\flutter\generated_plugin_registrant.cc'

if (-not (Test-Path $cmake) -or -not (Test-Path $registrant)) {
    throw 'Flutter Windows plugin registration files are missing; run flutter pub get first.'
}

$cmakeText = [IO.File]::ReadAllText($cmake)
$cmakeUpdated = $cmakeText -replace '(?m)^\s*webview_windows\s*\r?\n', ''
if ($cmakeUpdated -eq $cmakeText -and $cmakeText -match '(?m)^\s*webview_windows\s*$') {
    throw 'Could not remove webview_windows from generated_plugins.cmake.'
}
[IO.File]::WriteAllText($cmake, $cmakeUpdated, [Text.UTF8Encoding]::new($false))

$registrantText = [IO.File]::ReadAllText($registrant)
$registrantUpdated = $registrantText -replace '(?m)^#include <webview_windows/webview_windows_plugin\.h>\r?\n', ''
$registrantUpdated = $registrantUpdated -replace '(?ms)^\s*WebviewWindowsPluginRegisterWithRegistrar\(\r?\n\s*registry->GetRegistrarForPlugin\("WebviewWindowsPlugin"\)\);\r?\n', ''
if ($registrantUpdated -match 'webview_windows|WebviewWindowsPlugin') {
    throw 'Could not remove WebView2 registration from generated_plugin_registrant.cc.'
}
[IO.File]::WriteAllText($registrant, $registrantUpdated, [Text.UTF8Encoding]::new($false))

Write-Host 'Windows 7 legacy plugin registration prepared: WebView2 is excluded.'

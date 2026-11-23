<#
.SYNOPSIS
  OCR an image file with the built-in Windows OCR engine (no network, no extra deps).

.DESCRIPTION
  Uses Windows.Media.Ocr via WinRT. Useful to read on-screen text (e.g. another
  app's window) without shipping a screenshot into a vision model.

.PARAMETER Path
  Image file (png/jpg/bmp) to recognise.

.PARAMETER Lang
  BCP-47 tag, e.g. zh-Hans-CN / en-US. Default: user profile languages.

.EXAMPLE
  powershell -NoProfile -File bin\ocr.ps1 -Path shot.png
#>
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [string]$Lang = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($op, $type) {
  $task = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
  $task.Wait(-1) | Out-Null
  $task.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$full = (Resolve-Path $Path).Path
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($full)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

if ($Lang) {
  $l = New-Object Windows.Globalization.Language($Lang)
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($l)
} else {
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
}
if (-not $engine) { throw 'no OCR engine available for that language' }

$result = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
foreach ($line in $result.Lines) { $line.Text }

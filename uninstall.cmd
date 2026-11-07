@echo off
rem git-remote-boxdrive アンインストーラ（ダブルクリックで実行）
rem   install.cmd で入れたファイルと Path の登録を取り除く。Box 上のファイルや手元のリポジトリには触らない。
chcp 65001 >nul
setlocal
set "DEST=%LOCALAPPDATA%\Programs\git-remote-boxdrive"

echo git-remote-boxdrive をアンインストールします。
echo.

if exist "%DEST%" rmdir /s /q "%DEST%"
if exist "%DEST%" (
  echo [エラー] フォルダを削除できませんでした: %DEST%
  goto :fail
)
echo [1/2] ファイルを削除しました。

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = $env:DEST.TrimEnd('\');" ^
  "$k = Get-Item 'HKCU:\Environment';" ^
  "$p = $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);" ^
  "$parts = @($p -split ';' | Where-Object { $_ });" ^
  "$keep = @($parts | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ine $d });" ^
  "if ($keep.Count -eq $parts.Count) { exit 2 }" ^
  "Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value ($keep -join ';') -Type $(if ($k.GetValueNames() -contains 'Path') { $k.GetValueKind('Path') } else { 'ExpandString' });" ^
  "[Environment]::SetEnvironmentVariable('GIT_REMOTE_BOXDRIVE_NOTIFY', $null, 'User')"
if errorlevel 3 goto :fail
if errorlevel 2 (
  echo [2/2] Path には登録されていませんでした。
) else if errorlevel 1 (
  goto :fail
) else (
  echo [2/2] Path から削除しました。
)
echo.
echo アンインストールが完了しました。
pause
exit /b 0

:fail
echo.
echo アンインストールできませんでした。
pause
exit /b 1

@echo off
rem git-remote-boxdrive インストーラ（ダブルクリックで実行）
rem   - %LOCALAPPDATA%\Programs\git-remote-boxdrive にコピー
rem   - そのフォルダをユーザー環境変数 Path に追加（管理者権限不要・既存の Path は消さない）
rem   - 更新するときも、もう一度これを実行すればよい
chcp 65001 >nul
setlocal
set "SRC=%~dp0git-remote-boxdrive"
set "DEST=%LOCALAPPDATA%\Programs\git-remote-boxdrive"

echo git-remote-boxdrive をインストールします。
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [エラー] Git for Windows が見つかりません。
  echo https://gitforwindows.org/ からインストールしてから、もう一度実行してください。
  goto :fail
)
if not exist "%SRC%" (
  echo [エラー] この install.cmd と同じフォルダに git-remote-boxdrive が見つかりません。
  echo ZIP でダウンロードした場合は、すべて展開してから実行してください。
  goto :fail
)

if not exist "%DEST%" mkdir "%DEST%"
copy /y "%SRC%" "%DEST%\git-remote-boxdrive" >nul
if errorlevel 1 (
  echo [エラー] ファイルのコピーに失敗しました: %DEST%
  goto :fail
)
echo [1/3] ファイルをコピーしました: %DEST%

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = $env:DEST.TrimEnd('\');" ^
  "$k = Get-Item 'HKCU:\Environment';" ^
  "$p = $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);" ^
  "$parts = @($p -split ';' | Where-Object { $_ });" ^
  "if ($parts | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $d }) { exit 2 }" ^
  "Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value (($parts + $d) -join ';') -Type $(if ($k.GetValueNames() -contains 'Path') { $k.GetValueKind('Path') } else { 'ExpandString' });" ^
  "[Environment]::SetEnvironmentVariable('GIT_REMOTE_BOXDRIVE_NOTIFY', $null, 'User')"
if errorlevel 3 goto :path_fail
if errorlevel 2 (
  echo [2/3] Path にはすでに登録されています。
) else if errorlevel 1 (
  goto :path_fail
) else (
  echo [2/3] Path に追加しました。
)

rem 動作確認: 一時フォルダで実際に git から呼び出せるか試す
set "CHK=%TEMP%\git-remote-boxdrive-check-%RANDOM%"
mkdir "%CHK%\repo" "%CHK%\box"
set "PATH=%DEST%;%PATH%"
pushd "%CHK%\repo"
git init -q && git ls-remote "boxdrive::%CHK%\box" >nul 2>&1
set "RC=%errorlevel%"
popd
rmdir /s /q "%CHK%" 2>nul
if not "%RC%"=="0" (
  echo [エラー] 動作確認に失敗しました。git-remote-boxdrive ファイルが壊れていないか確認してください。
  goto :fail
)
echo [3/3] 動作確認 OK
echo.
echo インストールが完了しました。
echo Git を使うアプリ（コマンドプロンプト、VS Code など）を開いている場合は、
echo いったん閉じて開き直してください。
echo.
pause
exit /b 0

:path_fail
echo [エラー] Path への追加に失敗しました。
:fail
echo.
echo インストールできませんでした。
pause
exit /b 1

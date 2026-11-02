@echo off
chcp 936 >nul 2>&1
title 影之刃零 伤害飘字 MOD v0.5.0 - 卸载
cd /d "%~dp0"
cls
echo.
echo   ============================================================
echo          影之刃零   伤害飘字优化 MOD   v0.5.0
echo                        卸  载  程  序
echo   ============================================================
echo.
echo   正在启动，请稍等几秒...
echo.

echo "%~dp0" | find /i "\AppData\Local\Temp\" >nul && goto :inzip
echo "%~dp0" | find /i "Temp\Rar$" >nul && goto :inzip
echo "%~dp0" | find /i "Temp\7z" >nul && goto :inzip

if not exist "%~dp0_uninstall.ps1" goto :missing

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_uninstall.ps1"
if errorlevel 1 goto :fail
exit /b 0

:inzip
echo   ============================================================
echo    请先解压，不要在压缩包里直接双击！
echo   ============================================================
echo.
echo   正确做法：
echo     1. 右键这个压缩包 -^> 全部解压缩
echo     2. 进入解压出来的文件夹
echo     3. 再双击 "一键卸载.bat"
echo.
pause
exit /b 1

:missing
echo   ============================================================
echo    缺少文件 _uninstall.ps1
echo   ============================================================
echo.
echo   请重新解压整个压缩包。
echo.
pause
exit /b 1

:fail
echo.
echo   ============================================================
echo    卸载程序异常退出
echo   ============================================================
echo.
echo   请把这个窗口截图发给作者。
echo.
pause
exit /b 1

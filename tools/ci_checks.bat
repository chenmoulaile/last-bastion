@echo off
REM ============================================================
REM wp11-tests-ci: local CI chain (Windows, run from repo root)
REM
REM Usage:
REM     tools\ci_checks.bat
REM     set GODOT_EXE=D:\path\to\Godot_v4.7.2-stable_win64_console.exe && tools\ci_checks.bat
REM
REM Steps:
REM   1. smoke        headless res://tests/smoke.tscn
REM   2. narrative    headless res://tests/narrative.tscn
REM      (wp11: now also asserts wp6-level-story lengths/events/maxgap/dialogues
REM       and wp5 buffed zombie/boss .tres values)
REM   3. integration  headless res://tests/integration.tscn
REM      (wp8 crash-chain regression + interior full-flow + wp1 door entry
REM       scenarios A/B + wp4 interior walkthrough (5 themes) + wp7 boss
REM       rework (static cfg + 5 live boss fights) + wp5 pacing assertions)
REM   4. py -3.14 tools\assert_no_baked_weapons.py  (character frames must not bake weapons)
REM   5. py -3.14 tools\assert_weapon_clean.py      (weapon sprite stray-dot assertion)
REM   6. py -3.14 tools\assert_no_stray_dots.py     (wp10: characters+weapons full stray-dot assertion)
REM
REM Every step's stdout/stderr is kept in build\ci_logs\<step>.log.
REM Godot steps are additionally scanned for "SCRIPT ERROR" - any hit fails the step.
REM Exit code: 0 = all green, 1 = any failure, 2 = Godot not found.
REM ============================================================
setlocal enabledelayedexpansion

if "%GODOT_EXE%"=="" set "GODOT_EXE=D:\DevTools\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT_EXE%" (
    echo [CI] Godot not found: %GODOT_EXE% ^(set GODOT_EXE to override^)
    exit /b 2
)

set "LOGDIR=build\ci_logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set /a FAILURES=0

echo [CI] [1/6] smoke ...
"%GODOT_EXE%" --headless --path . res://tests/smoke.tscn > "%LOGDIR%\1_smoke.log" 2>&1
if errorlevel 1 (
    echo [CI] FAIL 1_smoke ^(log: %LOGDIR%\1_smoke.log^)
    set /a FAILURES+=1
) else (
    call :scan_log 1_smoke.log
)

echo [CI] [2/6] narrative ...
"%GODOT_EXE%" --headless --path . res://tests/narrative.tscn > "%LOGDIR%\2_narrative.log" 2>&1
if errorlevel 1 (
    echo [CI] FAIL 2_narrative ^(log: %LOGDIR%\2_narrative.log^)
    set /a FAILURES+=1
) else (
    call :scan_log 2_narrative.log
)

echo [CI] [3/6] integration ...
"%GODOT_EXE%" --headless --path . res://tests/integration.tscn > "%LOGDIR%\3_integration.log" 2>&1
if errorlevel 1 (
    echo [CI] FAIL 3_integration ^(log: %LOGDIR%\3_integration.log^)
    set /a FAILURES+=1
) else (
    call :scan_log 3_integration.log
)

echo [CI] [4/6] assert_no_baked_weapons ...
py -3.14 tools\assert_no_baked_weapons.py > "%LOGDIR%\4_no_baked_weapons.log" 2>&1
if errorlevel 1 (
    echo [CI] FAIL 4_no_baked_weapons ^(log: %LOGDIR%\4_no_baked_weapons.log^)
    set /a FAILURES+=1
) else (
    echo [CI] PASS 4_no_baked_weapons
)

echo [CI] [5/6] assert_weapon_clean ...
py -3.14 tools\assert_weapon_clean.py > "%LOGDIR%\5_weapon_clean.log" 2>&1
if errorlevel 1 (
    echo [CI] FAIL 5_weapon_clean ^(log: %LOGDIR%\5_weapon_clean.log^)
    set /a FAILURES+=1
) else (
    echo [CI] PASS 5_weapon_clean
)

echo [CI] [6/6] assert_no_stray_dots ...
py -3.14 tools\assert_no_stray_dots.py > "%LOGDIR%\6_no_stray_dots.log" 2>&1
if errorlevel 1 (
    echo [CI] FAIL 6_no_stray_dots ^(log: %LOGDIR%\6_no_stray_dots.log^)
    set /a FAILURES+=1
) else (
    echo [CI] PASS 6_no_stray_dots
)

echo.
if %FAILURES% GTR 0 (
    echo [CI] RESULT: FAIL ^(%FAILURES% step^(s^) failed^). Logs: %LOGDIR%\
    exit /b 1
)
echo [CI] RESULT: PASS. Logs: %LOGDIR%\
exit /b 0

REM --- scan a Godot step log for SCRIPT ERROR; PASS/FAIL echo + counter ---
:scan_log
findstr /C:"SCRIPT ERROR" "%LOGDIR%\%~1" >nul 2>&1
if errorlevel 1 (
    echo [CI] PASS %~1
) else (
    echo [CI] FAIL %~1 contains SCRIPT ERROR
    set /a FAILURES+=1
)
exit /b 0

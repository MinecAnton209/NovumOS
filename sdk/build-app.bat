@echo off
:: NovumOS SDK - Application Builder
:: Usage: build-app.bat <source.c> <output.elf>

if "%~1"=="" (
    echo Usage: %0 ^<source.c^> ^<output.elf^>
    echo Example: %0 main.c app.elf
    exit /b 1
)

if "%~2"=="" (
    echo Usage: %0 ^<source.c^> ^<output.elf^>
    echo Example: %0 main.c app.elf
    exit /b 1
)

set SOURCE=%~1
set OUTPUT=%~2
set TEMP_OBJ=%~n1.o

echo Building %SOURCE% -^> %OUTPUT%...

:: Compile
zig cc -target x86-freestanding -O2 -I libnovum\include -c %SOURCE% -o %TEMP_OBJ%
if %errorlevel% neq 0 (
    echo Compilation failed!
    exit /b 1
)

:: Link
zig ld.lld -T linker_app.ld %TEMP_OBJ% libnovum.a -o %OUTPUT% --entry main
if %errorlevel% neq 0 (
    echo Linking failed!
    del %TEMP_OBJ%
    exit /b 1
)

del %TEMP_OBJ%
echo Success! Created %OUTPUT%

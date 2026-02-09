@echo off
if not exist build mkdir build

echo Building Hello World...
zig cc -target x86-freestanding -O2 ^
    -I sdk\libnovum\include ^
    -I sdk\examples\hello_world ^
    -c sdk\examples\hello_world\main.c -o build\hello.o
if errorlevel 1 goto error

echo Linking Hello World...
zig ld.lld -T sdk\linker_app.ld ^
    build\hello.o sdk\libnovum.a ^
    -o build\hello.elf --entry main
if errorlevel 1 goto error

echo Success! build\hello.elf created.
exit /b 0

:error
echo Build failed!
exit /b 1

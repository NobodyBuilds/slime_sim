@echo off

REM --- Force working directory to this script's folder ---
cd /d "%~dp0"

REM --- Ensure build directory exists ---
if not exist build mkdir build

REM --- CUDA path (optional, kept as you had it) ---
set CUDA_PATH="C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"

REM --- Compile CUDA to object in build folder ---
nvcc -c cuda.cu -o cuda.obj ^
-gencode arch=compute_75,code=sm_75 ^
-gencode arch=compute_80,code=sm_80 ^
-gencode arch=compute_86,code=sm_86 ^
-gencode arch=compute_89,code=sm_89 ^
-gencode arch=compute_90,code=sm_90 ^
-gencode arch=compute_75,code=compute_75 ^
--std=c++17 -O3 -Xptxas=-O3 ^
-Xcompiler="/MD /O2 /Zc:preprocessor /permissive-" ^
-I"D:\visual_studio\fluid_sim\glad\include" ^
-I"D:\visual_studio\fluid_sim\glfw-3.4.bin.WIN64\include"
REM --- Create static library from object ---
lib /OUT:build\compute.lib cuda.obj

echo CUDA library built: build\compute.lib
pause
 
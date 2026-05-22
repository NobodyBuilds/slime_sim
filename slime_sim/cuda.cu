#include <cuda_runtime.h>
#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <cuda_gl_interop.h>

#include <cuda_runtime_api.h>
#include <device_launch_parameters.h>
#include <iostream>
#include <math_constants.h>
#include <math_functions.h>
#include "cuda.h"
#include"param.h"
#include<vector>
#define CUDA_CHECK(call) \
    do { \
        cudaError_t err = (call); \
        if (err != cudaSuccess) \
            printf("[CUDA ERROR] %s:%d — %s: %s\n", __FILE__, __LINE__, #call, cudaGetErrorString(err)); \
    } while(0)
#define BLOCKS(n) ((n + 255) / 256)
#define THREADS 256

float2* pos = nullptr;
float* angle = nullptr;
float* trailmap[2];

int ping = 0;
int pong = 1;
extern "C" void initcuda() {

	cudaMalloc(&pos, settings.n * sizeof(float2));
	cudaMalloc(&angle, settings.n * sizeof(float));
	cudaMalloc(&trailmap[0], (settings.w * settings.h) * sizeof(float));
	cudaMalloc(&trailmap[1], (settings.w * settings.h) * sizeof(float));

	cudaError_t a = cudaGetLastError();
	if (a) printf("memory allocation error : %s\n", cudaGetErrorString(a));
}
extern "C" void freecuda() {
	
	cudaFree(pos);
	cudaFree(angle);
	cudaFree(trailmap[0]);
	cudaFree(trailmap[1]);

	pos = nullptr;
	angle = nullptr;
	trailmap[0] = nullptr;
	trailmap[1] = nullptr;
	cudaError_t a = cudaGetLastError();
	if (a) printf("memory free error : %s \n", cudaGetErrorString(a));
}

static cudaGraphicsResource* d_tex = nullptr;

extern "C" void registerBuffer(unsigned int texId) {

	cudaError_t err = cudaGraphicsGLRegisterImage(&d_tex, texId, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsWriteDiscard);
	if (err != cudaSuccess) {
		std::cerr << "Failed to register OpenGL texture with CUDA: " << cudaGetErrorString(err) << std::endl;
	}
	
}

extern "C" void unregisterbuffer() {
	if (d_tex) {
		cudaGraphicsUnregisterResource(d_tex);
		d_tex = nullptr;
		
	}
}

__global__ void fillKernel(cudaSurfaceObject_t surf, int w, int h,float* color) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
	float val = color[y * w + x];
    surf2Dwrite(val, surf, x * sizeof(float), y);
}

extern "C" void updateframe() {



	cudaGraphicsMapResources(1, &d_tex);

	cudaArray_t arr;
	cudaGraphicsSubResourceGetMappedArray(&arr, d_tex, 0, 0);

	cudaResourceDesc desc{};
	desc.resType = cudaResourceTypeArray;
	desc.res.array.array = arr;

	cudaSurfaceObject_t surf;
	cudaCreateSurfaceObject(&surf, &desc);

	dim3 block(16, 16);
	dim3 grid((settings.w + 15) / 16, (settings.h + 15) / 16);
	fillKernel << <grid, block >> > (surf, settings.w, settings.h,trailmap[ping]);

	cudaDestroySurfaceObject(surf);
	cudaGraphicsUnmapResources(1, &d_tex);
	
}
////
//physics
// constant data for simulation parameters, copied from host to device at the start of the simulation

__constant__ data params;
data h_params;
extern "C" void copyparams() {


	h_params.tilesize = settings.tilesize;

	h_params.dt = settings.fdt;
	h_params.w = settings.w;
	h_params.h = settings.h;
	h_params.n = settings.n;
	h_params.decayFactor = settings.decayFactor;
	h_params.depositAmount = settings.depositAmount;
	h_params.sensorAngle = settings.sensorAngle;
	h_params.sensorDistance = settings.sensorDistance;
	h_params.stepSize = settings.stepSize;
	h_params.turnSpeed = settings.turnSpeed;


	cudaMemcpyToSymbol(params, &h_params, sizeof(data));
	cudaError_t a = cudaGetLastError();
	if (a)printf("copy parameters arros: %s\n ", cudaGetErrorString(a));
	else printf("params copied\n");

}
__device__ float sampleTrail(float* trail, float x, float y, int W, int H)
{
	int px = max(0, min(W - 1, (int)x));
	int py = max(0, min(H - 1, (int)y));
	return trail[py * W + px];
}


__device__ unsigned int hash(unsigned int state)
{
	state ^= 2747636419u;
	state *= 2654435769u;
	state ^= state >> 16;
	state *= 2654435769u;
	state ^= state >> 16;
	state *= 2654435769u;
	return state;
}


__global__ void agentKernel(
	float2* positions,  
	float* angles,     
	float* trailMap  ,unsigned int time 
	)
{
	int id = blockIdx.x * blockDim.x + threadIdx.x;
	if (id >= params.n) return;

	float2 pos = positions[id];
	float  angle = angles[id];

	
	//choose dir
	float angleFL = angle + params.sensorAngle;
	float angleFR = angle - params.sensorAngle;

	float2 sF = { pos.x + cosf(angle) *  params.sensorDistance,
				   pos.y + sinf(angle) * params.sensorDistance };

	float2 sFL = { pos.x + cosf(angleFL) * params.sensorDistance,
				   pos.y + sinf(angleFL) * params.sensorDistance };

	float2 sFR = { pos.x + cosf(angleFR) * params.sensorDistance,
				   pos.y + sinf(angleFR) * params.sensorDistance };

	float vF = sampleTrail(trailMap, sF.x, sF.y, params.w, params.h);
	float vFL = sampleTrail(trailMap, sFL.x, sFL.y, params.w, params.h);
	float vFR = sampleTrail(trailMap, sFR.x, sFR.y, params.w, params.h);

	
	unsigned int  rng = hash((unsigned int)id + time * 1000u);
	float randSign = (rng & 1u) ? 1.0f : -1.0f; 

	if (vF > vFL && vF > vFR) {
	}
	else if (vFL > vFR) {
		angle += params.turnSpeed;          
	}
	else if (vFR > vFL) {
		angle -= params.turnSpeed;          
	}
	else {
		angle += randSign * params.turnSpeed;
	}
	//intigate
	pos.x += cosf(angle) * params.stepSize;
	pos.y += sinf(angle) * params.stepSize;

	pos.x = fmodf(pos.x + (float)params.w, (float)params.w);
	pos.y = fmodf(pos.y + (float)params.h, (float)params.h);

	int px = max(0, min(params.w - 1, (int)pos.x));
	int py = max(0, min(params.h - 1, (int)pos.y));
	atomicAdd(&trailMap[py * params.w + px], params.depositAmount);

	positions[id] = pos;
	angles[id] = angle;
}

__global__ void diffuseDecayKernel(
	float* trailIn,   
	float* trailOut)
{
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	if (x >= params.w || y >= params.h) return;

	//blur
	float sum = 0.0f;
	float count = 0.0f;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			int nx = x + dx;
			int ny = y + dy;
			if (nx >= 0 && nx < params.w && ny >= 0 && ny < params.h) {
				sum += trailIn[ny * params.w + nx];
				count += 1.0f;
			}
		}
	}
	float blurred = sum / count;

	float original = trailIn[y * params.w + x];
	float diffused = original + (blurred - original) * params.diffusionweight;

	trailOut[y * params.w + x] = fminf(diffused * params.decayFactor, 1.0f);
}


extern "C" void updatephysics() {
	
		
	
	int n = settings.w * settings.h;
	int threads = 256;
	int blocks = (settings.n + threads - 1) / threads;

	

	agentKernel << <blocks, threads >> > (pos, angle, trailmap[ping],settings.time);

	dim3 block(16, 16);
	dim3 grid((settings.w + 15) / 16, (settings.h + 15) / 16);

	diffuseDecayKernel << <grid, block >> > (trailmap[ping], trailmap[pong]);
	
	ping = 1 - ping; pong = 1 - pong;
	settings.time++;

}


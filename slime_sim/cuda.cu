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

float4* data1 = nullptr; //posx,posy,sensor_angle,sensor_dist
float4* data2 = nullptr;//angle,turn speed,movespeed,trail weight
float4* data3 = nullptr;//poison sense,aggression,energy,energy threshold(for reproduce)
float4* data4 = nullptr;//foodA,foodB,foodC,foodD
float4* trailmap[2];//r,g,b,trail

int ping = 0;
int pong = 1;
extern "C" void initcuda() {

	cudaMalloc(&data1, settings.n * sizeof(float4));
	cudaMalloc(&data2, settings.n * sizeof(float4));
	cudaMalloc(&data3, settings.n * sizeof(float4));
	cudaMalloc(&data4, settings.n * sizeof(float4));
	cudaMalloc(&trailmap[0], (settings.w * settings.h) * sizeof(float4));
	cudaMalloc(&trailmap[1], (settings.w * settings.h) * sizeof(float4));

	cudaError_t a = cudaGetLastError();
	if (a) printf("memory allocation error : %s\n", cudaGetErrorString(a));
}
extern "C" void freecuda() {
	
	cudaFree(data1);
	cudaFree(data2);
	cudaFree(data3);
	cudaFree(data4);
	cudaFree(trailmap[0]);
	cudaFree(trailmap[1]);

	data1 = nullptr;
	data2 = nullptr;
	data3 = nullptr;
	data4 = nullptr;
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

__global__ void fillKernel(cudaSurfaceObject_t surf, int w, int h,float4* color) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
	float4 val = color[y * w + x];
	surf2Dwrite(val, surf, x * sizeof(float4), y);
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
__device__ float randf(uint32_t seed, float mn, float mx)
{
	seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
	return mn + (seed >> 8) * (1.0f / 16777216.0f) * (mx - mn);
}
__global__ void initAgents(float4* data1, float4* data2, float4* data3, float4* data4, int n,float samax,float sdmax,float tsmax,float damax,float msmax) {
	int id = blockIdx.x * blockDim.x + threadIdx.x;
	if (id >= n) return;
	uint32_t s = hash((unsigned int)id);
	float sensorangle = randf(s+1,params.sensorAngle,samax);
	float sensordist = randf(s+2, params.sensorDistance, sdmax);
	float turnspeed = randf(s+3, params.turnSpeed, tsmax);
	float depositammount = randf(s+4, params.depositAmount, damax);
	float movespeed = randf(s+5, params.stepSize, msmax);

	float poisonsense = randf(s+6, 0.0f, 1.0f);
	float aggression = randf(s+7, 0.0f, 1.0f);
	float threshold = randf(s+8, 0.0f, 40.0f);
	float foodA = randf(s+9, 0.0f, 1.0f);
	float foodB = randf(s+10, 0.0f, 1.0f);
	float foodC = randf(s+11, 0.0f, 1.0f);
	float foodD = randf(s+12, 0.0f, 1.0f);
	float px = randf(s+13, 0.0f, (float)params.w);
	float py = randf(s+14, 0.0f, (float)params.h);
	float angle = randf(s+15, 0.0f, 6.2831f);


	data1[id] = { px, py, sensorangle, sensordist }; 
	data2[id] = { angle, turnspeed, movespeed, depositammount }; 
	data3[id] = { poisonsense, aggression, 30.0f, threshold }; 
	data4[id] = { foodA, foodB, foodC, foodD }; 
}

extern "C" void writegenomes() {

	int threads = 256;
	int blocks = (settings.n + threads - 1) / threads;
	initAgents << <blocks, threads >> > (data1, data2, data3, data4, settings.n,settings.sensorAngleMax,settings.sensorDistanceMax,settings.turnSpeedMax,settings.depositAmountMax,settings.stepSizeMax);

}
__global__ void updategkernel(float4* data,float min,float max,int var) {

	int id = blockIdx.x * blockDim.x + threadIdx.x;
	if (id >= params.n) return;

	float val = randf(0.0f, min, max);

	if (var == 1) {
		data[id].x = val;
	}
	else if (var == 2) { data[id].y = val; }
	else if (var == 3) { data[id].z = val; }
	else if (var == 4) { data[id].w = val; }
}
extern "C" void updategenome(int type,int var,float min,float max) {


	int threads = 256;
	int blocks = (settings.n + threads - 1) / threads;

	
	

	if(type==1){updategkernel<<<blocks,threads>>>(data1, min, max, var); }
	if(type==2){updategkernel<<<blocks,threads>>>(data2, min, max, var); }
	if(type==3){updategkernel<<<blocks,threads>>>(data3, min, max, var); }
	if(type==4){updategkernel<<<blocks,threads>>>(data4, min, max, var); }

}

__device__ float clamp(float val, float min, float max) {
	if (val < min) val = min;
	if (val > max) val = max;
	return val;

}
__device__ float sampleTrail(float4* trail, float x, float y, int W, int H)
{
	int px = max(0, min(W - 1, (int)x));
	int py = max(0, min(H - 1, (int)y));
	return trail[py * W + px].w;
}
__device__ float3 genomeToColor(float4 d4) {

	float r = d4.x;
	float g = d4.y;
	float b = d4.z;

	return make_float3(r, g, b);
}
__global__ void agentKernel(
	    
	float4* trailMap, unsigned int time, float4* data1, float4* data2, float4* data3, float4* data4
	){
	int id = blockIdx.x * blockDim.x + threadIdx.x;
	if (id >= params.n) return;
	
	float2 pos = { data1[id].x, data1[id].y };
	float  angle = data2[id].x;

	float sensorAngle = __ldg(&data1[id].z);
	float sensorDist = __ldg(&data1[id].w);
	float turnSpeed = __ldg(&data2[id].y);
	float stepsize = __ldg(&data2[id].z);
	float depositAmount = __ldg(&data2[id].w);
	
	float angleFL = angle + sensorAngle;
	float angleFR = angle - sensorAngle;
	float2 sF = { pos.x + cosf(angle) * sensorDist,
				   pos.y + sinf(angle) * sensorDist };

	float2 sFL = { pos.x + cosf(angleFL) *sensorDist,
				   pos.y + sinf(angleFL) * sensorDist };

	float2 sFR = { pos.x + cosf(angleFR) * sensorDist,
				   pos.y + sinf(angleFR) * sensorDist };
	float vF = sampleTrail(trailMap, sF.x, sF.y, params.w, params.h);
	float vFL = sampleTrail(trailMap, sFL.x, sFL.y, params.w, params.h);
	float vFR = sampleTrail(trailMap, sFR.x, sFR.y, params.w, params.h);

	
	unsigned int  rng = hash((unsigned int)id + time * 1000u);
	float randSign = (rng & 1u) ? 1.0f : -1.0f; 

	if (vF > vFL && vF > vFR) {
	}
	else if (vFL > vFR) {
		angle += turnSpeed;          
	}
	else if (vFR > vFL) {
		angle -= turnSpeed;          
	}
	else {
		angle += randSign * turnSpeed;
	}
	pos.x += cosf(angle) * stepsize;
	pos.y += sinf(angle) * stepsize;

	pos.x = fmodf(pos.x + (float)params.w, (float)params.w);
	pos.y = fmodf(pos.y + (float)params.h, (float)params.h);

	int px = max(0, min(params.w - 1, (int)pos.x));
	int py = max(0, min(params.h - 1, (int)pos.y));
	float3 col = genomeToColor(data4[id]);

	
	atomicAdd(&trailMap[py * params.w + px].x, col.x* depositAmount);
	atomicAdd(&trailMap[py * params.w + px].y, col.y* depositAmount);
	atomicAdd(&trailMap[py * params.w + px].z, col.z* depositAmount);
	atomicAdd(&trailMap[py * params.w + px].w,  depositAmount);

	data1[id].x = pos.x;
	data1[id].y = pos.y;
	data2[id].x = angle;
}

__global__ void diffuseDecayKernel(
	float4* trailIn,   
	float4* trailOut)
{
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	if (x >= params.w || y >= params.h) return;

	//blur
	
	
	float4 sum = { 0.0f, 0.0f, 0.0f, 0.0f };
	
	float count = 0.0f;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			int nx = x + dx;
			int ny = y + dy;
			if (nx >= 0 && nx < params.w && ny >= 0 && ny < params.h) {
				sum.x += trailIn[ny * params.w + nx].x;
				sum.y += trailIn[ny * params.w + nx].y;
				sum.z += trailIn[ny * params.w + nx].z;
				sum.w += trailIn[ny * params.w + nx].w;
				count += 1.0f;
			}
		}
	}
	float4 diffused = { 0.0f,0.0f,0.0f,0.0f };
	
	float4 blurred = { 0.0f,0.0f,0.0f,0.0f };
	blurred.x = sum.x / count;
	blurred.y = sum.y / count;
	blurred.z = sum.z / count;
	blurred.w = sum.w / count;

	float4 original = trailIn[y * params.w + x];
	diffused.x = original.x + (blurred.x - original.x) * params.diffusionweight;
	diffused.y = original.y + (blurred.y - original.y) * params.diffusionweight;
	diffused.z = original.z + (blurred.z - original.z) * params.diffusionweight;
	diffused.w = original.w + (blurred.w - original.w) * params.diffusionweight;

	


	trailOut[y * params.w + x].x = fminf(diffused.x * params.decayFactor, 1.0f);
	trailOut[y * params.w + x].y = fminf(diffused.y * params.decayFactor, 1.0f);
	trailOut[y * params.w + x].z = fminf(diffused.z * params.decayFactor, 1.0f);
	trailOut[y * params.w + x].w = fminf(diffused.w * params.decayFactor, 1.0f);
}


extern "C" void updatephysics() {
	
		
	
	int n = settings.w * settings.h;
	int threads = 256;
	int blocks = (settings.n + threads - 1) / threads;

	

	agentKernel << <blocks, threads >> > (trailmap[ping],settings.time,data1,data2,data3,data4);

	dim3 block(16, 16);
	dim3 grid((settings.w + 15) / 16, (settings.h + 15) / 16);

	diffuseDecayKernel << <grid, block >> > (trailmap[ping], trailmap[pong]);
	
	ping = 1 - ping; pong = 1 - pong;
	settings.time++;

}


#pragma once
struct param {
	float fps = 0.0f;
	float fdt = 1.0f / 120.0f;
	float fpsTimer = 0.0f;
	float maxFps = 0.0f;
	float minFps = 0.0f;
	float avgFps = 0.0f;
	float fuc_ms = 0.0f;
	float tilesize = 5.0f;
	float radius = 50.0f;
	float	sensorAngle = 0.4f;
	float	sensorDistance = 9.0f;
	float	turnSpeed = 0.3f;
	float	stepSize = 1.5f;
	float	decayFactor = 0.96f;
	float	depositAmount = 5.0f;
	float diffusionweight = 0.2f;

	unsigned int time;
	int n = 100;
	int ncopy = 100;
	int fpsCount = 0;
	int w = 0, h = 0;
	int cells = w * h;
};
extern param settings;

struct data {
	float tilesize;
	float dt;
	float	sensorAngle ;
	float	sensorDistance ;
	float	turnSpeed ;
	float	stepSize ;
	float	decayFactor ;
	float	depositAmount ;
	float diffusionweight;
	unsigned int time;
	int w;
	int h;
	int n;
};
extern data Data;
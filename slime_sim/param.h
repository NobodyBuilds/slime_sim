#pragma once
struct param {
	float fps = 0.0f;
	float fdt = 1.0f / 120.0f;
	float fpsTimer = 0.0f;
	float maxFps = 0.0f;
	float minFps = 0.0f;
	float avgFps = 0.0f;
	float fuc_ms = 0.0f;
	float tilesize = 1.0f;
	float radius = 50.0f;
	float	sensorAngle = 0.36f;
	float	sensorAngleMax = 0.45f;
	float	sensorDistance = 8.60f;
	float	sensorDistanceMax = 9.40f;
	float	turnSpeed = 0.27f;
	float	turnSpeedMax = 0.34f;
	float	stepSize = 1.4f;
	float	stepSizeMax = 1.64f;
	float	decayFactor = 0.96f;
	float	depositAmount = 4.95f;
	float	depositAmountMax = 5.0f;
	float diffusionweight = 0.2f;

	unsigned int time;
	int n = 100000;
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
#pragma once

class FrameLimiter
{
	public:
		static void Init();
		static void SetCap(uint32_t maxFPS);
};

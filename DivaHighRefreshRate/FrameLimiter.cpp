// https://github.com/michael-fadely/sadx-frame-limit/blob/11a231c76d053027bab29fe1df042b0b660878ab/sadx-frame-limit/mod.cpp

#include "FrameLimiter.h"

constexpr int NVAPI_OK = 0;

struct NV_SET_SLEEP_MODE_PARAMS
{
	int version;
	uint8_t bLowLatencyMode;
	uint8_t bLowLatencyBoost;
	uint32_t minimumIntervalUs;
	uint8_t bUseMarkersToOptimize;
	uint8_t bUseMinQueueTime;
	uint8_t reserved[30];
};

constexpr int NV_SLEEP_PARAMS_VER =
	static_cast<int>(sizeof(NV_SET_SLEEP_MODE_PARAMS) | (1 << 16));

using NvAPI_QueryInterface = void*(__cdecl*)(int);
using NvAPI_Initialize = int(__cdecl*)();
using NvAPI_D3D_SetSleepMode =
	int(__cdecl*)(IUnknown*, NV_SET_SLEEP_MODE_PARAMS*);
using NvAPI_D3D_Sleep = int(__cdecl*)(IUnknown*);

constexpr int ID_NvAPI_Initialize = 0x0150E828;
constexpr int ID_NvAPI_D3D_SetSleepMode = static_cast<int>(0xAC1CA9E0u);
constexpr int ID_NvAPI_D3D_Sleep = static_cast<int>(0x852CD1D2u);

static NvAPI_D3D_SetSleepMode nvapi_set_sleep_mode = nullptr;
static NvAPI_D3D_Sleep nvapi_sleep = nullptr;
static IUnknown* d3d_device = nullptr;
static bool enable_frame_limit = false;

static bool ResolveNvAPI()
{
#ifdef _WIN64
	HMODULE nvapi = GetModuleHandleW(L"nvapi64.dll");
	if (!nvapi)
		nvapi = LoadLibraryW(L"nvapi64.dll");
#else
	HMODULE nvapi = GetModuleHandleW(L"nvapi.dll");
	if (!nvapi)
		nvapi = LoadLibraryW(L"nvapi.dll");
#endif

	if (!nvapi)
		return false;

	auto queryInterface = reinterpret_cast<NvAPI_QueryInterface>(
		GetProcAddress(nvapi, "nvapi_QueryInterface"));
	if (!queryInterface)
		return false;

	auto initialize = reinterpret_cast<NvAPI_Initialize>(
		queryInterface(ID_NvAPI_Initialize));
	if (!initialize || initialize() != NVAPI_OK)
		return false;

	nvapi_set_sleep_mode = reinterpret_cast<NvAPI_D3D_SetSleepMode>(
		queryInterface(ID_NvAPI_D3D_SetSleepMode));
	nvapi_sleep = reinterpret_cast<NvAPI_D3D_Sleep>(
		queryInterface(ID_NvAPI_D3D_Sleep));

	return nvapi_set_sleep_mode && nvapi_sleep;
}

static void UpdateSleepMode(uint32_t minimumIntervalUs)
{
	if (!d3d_device || !nvapi_set_sleep_mode)
		return;

	NV_SET_SLEEP_MODE_PARAMS params = {};
	params.version = NV_SLEEP_PARAMS_VER;
	if (enable_frame_limit)
	{
		params.bLowLatencyMode = 1;
		params.minimumIntervalUs = minimumIntervalUs;
	}

	__try
	{
		nvapi_set_sleep_mode(d3d_device, &params);
	}
	__except (EXCEPTION_EXECUTE_HANDLER)
	{
	}
}

SIG_SCAN
(
	sigFrameLimiter,
	0x1402B6DC0,
	"\x40\x53\x48\x83\xEC\x50\x80\x3D\x00\x00\x00\x00\x00",
	"xxxxxxxx?????"
);

HOOK(void, __fastcall, _FrameLimiter, sigFrameLimiter())
{
	if (!enable_frame_limit || !d3d_device || !nvapi_sleep)
		return;

	__try
	{
		nvapi_sleep(d3d_device);
	}
	__except (EXCEPTION_EXECUTE_HANDLER)
	{
	}
}

HOOK(HRESULT, WINAPI, D3D11CreateDeviceAndSwapChain, PROC_ADDRESS("d3d11.dll", "D3D11CreateDeviceAndSwapChain"),
	IDXGIAdapter* pAdapter,
	D3D_DRIVER_TYPE DriverType,
	HMODULE Software,
	UINT Flags,
	const D3D_FEATURE_LEVEL* pFeatureLevels,
	UINT FeatureLevels,
	UINT SDKVersion,
	const DXGI_SWAP_CHAIN_DESC* pSwapChainDesc,
	IDXGISwapChain** ppSwapChain,
	ID3D11Device** ppDevice,
	D3D_FEATURE_LEVEL* pFeatureLevel,
	ID3D11DeviceContext** ppImmediateContext)
{
	printf("[%s] D3D11CreateDeviceAndSwapChain called.\n", MOD_NAME);

	const HRESULT result = originalD3D11CreateDeviceAndSwapChain(
		pAdapter,
		DriverType,
		Software,
		Flags,
		pFeatureLevels,
		FeatureLevels,
		SDKVersion,
		pSwapChainDesc,
		ppSwapChain,
		ppDevice,
		pFeatureLevel,
		ppImmediateContext);

	if (SUCCEEDED(result) && ppDevice && *ppDevice)
	{
		d3d_device = *ppDevice;
	}

	return result;
}

void FrameLimiter::SetCap(uint32_t maxFPS)
{
	enable_frame_limit = maxFPS > 0;
	const uint32_t minimumIntervalUs = enable_frame_limit
		? static_cast<uint32_t>((1000000 + maxFPS / 2) / maxFPS)
		: 0;

	UpdateSleepMode(minimumIntervalUs);
}

void FrameLimiter::Init()
{
	if (!ResolveNvAPI())
	{
		printf("[%s] NVAPI initialization failed.\n", MOD_NAME);
		return;
	}

	INSTALL_HOOK(D3D11CreateDeviceAndSwapChain);
	INSTALL_HOOK(_FrameLimiter);
}

#include "BL2SDK/BL2SDK.h"
#include "BL2SDK/CSimpleDetour.h"
#include "BL2SDK/Logging.h"
#include "BL2SDK/CSigScan.h"
#include "BL2SDK/CrashRptHelper.h"
#include "BL2SDK/GameHooks.h"
#include "BL2SDK/Settings.h"
#include "BL2SDK/Util.h"
#include "Commands/ConCmdManager.h"
#include "GUI/D3D9Hook.h"
#include "LuaInterface/LuaManager.h"
#include "BL2SDK/Exceptions.h"
#include "BL2SDK/AntiDebug.h"
#include "GUI/GwenManager.h"

namespace BL2SDK
{
	bool injectedCallNext = false;
	bool logAllProcessEvent = false;
	bool logAllUnrealScriptCalls = false;

	unsigned long pGObjects;
	unsigned long pGNames;
	unsigned long pGObjHash;
	tProcessEvent pProcessEvent;
	tCallFunction pCallFunction;
	tFrameStep pFrameStep;
	tProcessDeferredMessage pProcessDeferredMessage;
	tViewportResize pViewportResize;
	void* pGwenDestructor;

	int EngineVersion = -1;
	int ChangelistNumber = -1;

	void __stdcall hkProcessEvent(UFunction* function, void* parms, void* result)
	{
		// Get "this"
		UObject* caller;
		_asm mov caller, ecx;

		if(injectedCallNext)
		{
			injectedCallNext = false;
			pProcessEvent(caller, function, parms, result);
			return;
		}

		if(logAllProcessEvent)
		{
			std::string callerName = caller->GetFullName();
			std::string functionName = function->GetFullName();

			Logging::LogF("===== ProcessEvent called =====\npCaller Name = %s\npFunction Name = %s\n", callerName.c_str(), functionName.c_str());
		}
		
		if(!GameHooks::ProcessEngineHooks(caller, function, parms, result))
		{
			// The engine hook manager told us not to pass this function to the engine
			return;
		}
		
		pProcessEvent(caller, function, parms, result);
	}

	void __stdcall hkCallFunction(FFrame& stack, void* const result, UFunction* function)
	{
		// Get "this"
		UObject* caller;
		_asm mov caller, ecx;

		if(logAllUnrealScriptCalls)
		{
			std::string callerName = caller->GetFullName();
			std::string functionName = function->GetFullName();

			Logging::LogF("===== CallFunction called =====\npCaller Name = %s\npFunction Name = %s\n", callerName.c_str(), functionName.c_str());
		}

		if(!GameHooks::ProcessUnrealScriptHooks(caller, stack, result, function))
		{
			// UnrealScript hook manager already took care of it
			return;
		}

		pCallFunction(caller, stack, result, function);
	}

	void InjectedCallNext()
	{
		injectedCallNext = true;
	}

	void LogAllProcessEventCalls(bool enabled)
	{
		logAllProcessEvent = enabled;
	}

	void LogAllUnrealScriptCalls(bool enabled)
	{
		logAllUnrealScriptCalls = enabled;
	}

	int UnrealExceptionHandler(unsigned int code, struct _EXCEPTION_POINTERS* ep)
	{
		if(CrashRptHelper::GenerateReport(code, ep))
		{
			Util::CloseGame();
		}
		else
		{
			// TODO: Maybe have it call the original Engine func here
		}

		return EXCEPTION_EXECUTE_HANDLER;
	}

	bool GetGameVersion(std::wstring& appVersion)
	{
		const wchar_t* filename = L"Borderlands2.exe";

		// Allocate a block of memory for the version info
		DWORD dummy;
		DWORD size = GetFileVersionInfoSize(filename, &dummy);
		if(size == 0)
		{
			Logging::LogF("[BL2SDK] ERROR: GetFileVersionInfoSize failed with error %d\n", GetLastError());
			return false;
		}
		
		LPBYTE versionInfo = new BYTE[size];

		// Load the version info
		if(!GetFileVersionInfo(filename, NULL, size, &versionInfo[0]))
		{
			Logging::LogF("[BL2SDK] ERROR: GetFileVersionInfo failed with error %d\n", GetLastError());
			return false;
		}

		// Get the version strings
		VS_FIXEDFILEINFO* ffi;
		unsigned int productVersionLen = 0;

		if(!VerQueryValue(&versionInfo[0], L"\\", (LPVOID*)&ffi, &productVersionLen))
		{
			Logging::Log("[BL2SDK] ERROR: Can't obtain FixedFileInfo from resources\n");
			return false;
		}

		DWORD fileVersionMS = ffi->dwFileVersionMS;
		DWORD fileVersionLS = ffi->dwFileVersionLS;

		delete[] versionInfo;

		appVersion = Util::Format(L"%d.%d.%d.%d", 
			HIWORD(fileVersionMS),
			LOWORD(fileVersionMS),
			HIWORD(fileVersionLS),
			LOWORD(fileVersionLS));

		return true;
	}

	// TODO: Make less shit
	void HookGame()
	{
		CSigScan sigscan(L"Borderlands2.exe");

		// Sigscan for GOBjects
		pGObjects = *(unsigned long*)sigscan.Scan((unsigned char*)GObjects_Pattern, GObjects_Mask);
		Logging::LogF("[Internal] GObjects = 0x%X\n", pGObjects);

		// Sigscan for GNames
		pGNames = *(unsigned long*)sigscan.Scan((unsigned char*)GNames_Pattern, GNames_Mask);
		Logging::LogF("[Internal] GNames = 0x%X\n", pGNames);

		// Sigscan for UObject::ProcessEvent which will be used for pretty much everything
		pProcessEvent = reinterpret_cast<tProcessEvent>(sigscan.Scan((unsigned char*)ProcessEvent_Pattern, ProcessEvent_Mask));
		Logging::LogF("[Internal] UObject::ProcessEvent() = 0x%X\n", pProcessEvent);

		// Sigscan for UObject::GObjHash
		pGObjHash = *(unsigned long*)sigscan.Scan((unsigned char*)GObjHash_Pattern, GObjHash_Mask);
		Logging::LogF("[Internal] GObjHash = 0x%X\n", pGObjHash);

		// Sigscan for Unreal exception handler
		void* addrUnrealEH = sigscan.Scan((unsigned char*)CrashHandler_Pattern, CrashHandler_Mask);
		Logging::LogF("[Internal] Unreal Crash handler = 0x%X\n", addrUnrealEH);

		// Sigscan for UObject::CallFunction
		pCallFunction = reinterpret_cast<tCallFunction>(sigscan.Scan((unsigned char*)CallFunction_Pattern, CallFunction_Mask));
		Logging::LogF("[Internal] UObject::CallFunction() = 0x%X\n", pCallFunction);

		// Sigscan for FFrame::Step
		pFrameStep = reinterpret_cast<tFrameStep>(sigscan.Scan((unsigned char*)FrameStep_Pattern, FrameStep_Mask));
		Logging::LogF("[Internal] FFrame::Step() = 0x%X\n", pFrameStep);

		// Sigscan for FWindowsViewport::ProcessDeferredMessage
		pProcessDeferredMessage = reinterpret_cast<tProcessDeferredMessage>(sigscan.Scan((unsigned char*)ProcessDeferredMessage_Pattern, ProcessDeferredMessage_Mask));
		Logging::LogF("[Internal] FWindowsViewport::ProcessDeferredMessage() = 0x%X\n", pProcessDeferredMessage);

		// Sigscan for FWindowsViewport::Resize
		pViewportResize = reinterpret_cast<tViewportResize>(sigscan.Scan((unsigned char*)ViewportResize_Pattern, ViewportResize_Mask));
		Logging::LogF("[Internal] FWindowsViewport::Resize() = 0x%X\n", pViewportResize);

		// Sigscan for Gwen::Controls::Base::~Base()
		CSigScan sdkSigscan(L"BL2SDKDLL.dll");

		pGwenDestructor = reinterpret_cast<void*>(sdkSigscan.Scan((unsigned char*)GwenDestructor_Pattern, GwenDestructor_Mask));
		Logging::LogF("[Internal] Gwen::Controls::Base::~Base() = 0x%X\n", pGwenDestructor);

		// Detour UObject::ProcessEvent()
		SETUP_SIMPLE_DETOUR(detProcessEvent, pProcessEvent, hkProcessEvent);
		detProcessEvent.Attach();

		// Detour Unreal exception handler
		SETUP_SIMPLE_DETOUR(detUnrealEH, addrUnrealEH, UnrealExceptionHandler);
		detUnrealEH.Attach();

		// Detour UObject::CallFunction()
		SETUP_SIMPLE_DETOUR(detCallFunction, pCallFunction, hkCallFunction);
		detCallFunction.Attach();
	}

	// This function is used to get the dimensions of the game window for Gwen's renderer
	bool GetCanvasPostRender(UObject* caller, UFunction* function, void* parms, void* result)
	{
		UGameViewportClient_eventPostRender_Parms* realParms = reinterpret_cast<UGameViewportClient_eventPostRender_Parms*>(parms);
		UCanvas* canvas = realParms->Canvas;

		GwenManager::UpdateCanvas(canvas->SizeX, canvas->SizeY);

		GameHooks::EngineHookManager->RemoveStaticHook(function, "GetCanvas");
		return true;
	}

	void InitializeGameVersions()
	{
		UObject* obj = UObject::StaticClass(); // Any UObject* will do
		EngineVersion = obj->GetEngineVersion();
		ChangelistNumber = obj->GetBuildChangelistNumber();

		CrashRptHelper::AddProperty(L"EngineVersion", Util::Format(L"%d", EngineVersion));
		CrashRptHelper::AddProperty(L"ChangelistNumber", Util::Format(L"%d", ChangelistNumber));

		Logging::LogF("[Internal] Engine Version = %d, Build Changelist = %d\n", EngineVersion, ChangelistNumber);
	}

	// This function is used to ensure that everything gets called in the game thread once the game itself has loaded
	bool GameReady(UObject* caller, UFunction* function, void* parms, void* result) 
	{
		Logging::LogF("[GameReady] Thread: %i\n", GetCurrentThreadId());

		Logging::InitializeExtern();
		Logging::InitializeGameConsole();
		Logging::PrintLogHeader();

		InitializeGameVersions();

		LuaManager::Initialize();

		ConCmdManager::Initialize();

		GameHooks::EngineHookManager->RemoveStaticHook(function, "StartupSDK");

		GameHooks::EngineHookManager->Register("Function WillowGame.WillowGameViewportClient.PostRender", "GetCanvas", &GetCanvasPostRender);
		return true;
	}

	void Initialize(LauncherStruct* args)
	{
		Settings::Initialize(args);

		Logging::InitializeFile(Settings::GetLogFilePath());
		Logging::Log("[Internal] Launching SDK...\n");

		if(!args->DisableCrashRpt)
		{
			CrashRptHelper::Initialize();
		}

		if(args->DisableAntiDebug)
		{
			HookAntiDebug();
		}

		GameHooks::Initialize();

		HookGame();

		LogAllProcessEventCalls(args->LogAllProcessEventCalls);
		LogAllUnrealScriptCalls(args->LogAllUnrealScriptCalls);

		D3D9Hook::Initialize();

		GameHooks::EngineHookManager->Register("Function WillowGame.WillowGameInfo.InitGame", "StartupSDK", &GameReady);	
	}

	// This is called when the process is closing
	// TODO: Other things might need cleaning up
	void Cleanup()
	{
		Logging::Cleanup();
		GameHooks::Cleanup();
	}

	extern "C" __declspec(dllexport) void LUAFUNC_LogAllProcessEventCalls(bool enabled)
	{
		LogAllProcessEventCalls(enabled);
	}

	extern "C" __declspec(dllexport) void LUAFUNC_LogAllUnrealScriptCalls(bool enabled)
	{
		LogAllUnrealScriptCalls(enabled);
	}

	extern "C" __declspec(dllexport) char* LUAFUNC_UObjectGetFullName(UObject* obj)
	{
		return obj->GetFullName();
	}
}
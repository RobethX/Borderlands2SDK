#include "Detours/DetourManager.h"
#include "BL2SDK/BL2SDK.h"
#include "Logging/Logging.h"

namespace DetourManager
{
	#define UObject_ProcessEvent 0x0065C820

	tProcessEvent pProcessEvent = reinterpret_cast<tProcessEvent>(UObject_ProcessEvent);

	//typedef HCURSOR (APIENTRY* tSetCursor) (HCURSOR);
	//tSetCursor pSetCursor = SetCursor;

	//typedef HRESULT (APIENTRY* tEndScene) (IDirect3DDevice9*);
	//tEndScene pEndScene = NULL;

	//SETUP_SIMPLE_DETOUR(ProcessEvent_Detour, pProcessEvent, BL2SDK::hkRawProcessEvent);
	//SETUP_SIMPLE_DETOUR(SetCursor_Detour, pSetCursor, BL2SDK::hkSetCursor);
	//SETUP_SIMPLE_DETOUR(EndScene_Detour, pEndScene, BL2SDK::hkEndScene);

	void AttachProcessEvent()
	{
		DetourTransactionBegin();
		DetourUpdateThread(GetCurrentThread());
		DetourAttach(&(PVOID&)pProcessEvent, BL2SDK::hkRawProcessEvent);
		if(DetourTransactionCommit() == NO_ERROR)
			Logging::Log("ProcessEvent Detoured successfully, 0x%X\n", pProcessEvent);
	}
}
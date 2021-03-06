/*
#############################################################################################
# Borderlands 2 (1.0.35.4705) SDK
# Generated with TheFeckless UE3 SDK Generator v1.4_Beta-Rev.51
# Credits: uNrEaL, Tamimego, SystemFiles, R00T88, _silencer, the1domo, K@N@VEL
# Thanks: HOOAH07, lowHertz
# Forums: www.uc-forum.com, www.gamedeception.net
#############################################################################################
*/
#include "GameSDK/GameSDK.h"

#ifdef _MSC_VER
	#pragma pack ( push, 0x4 )
#endif

/*
# ========================================================================================= #
# Global Static Class Pointers
# ========================================================================================= #
*/

UClass* APlayerController::pClassPointer = NULL;

/*
# ========================================================================================= #
# Functions
# ========================================================================================= #
*/

// Function Engine.Console.OutputText
// [0x00020802] ( FUNC_Event )
// Parameters infos:
// struct FString                 Text                           ( CPF_Parm | CPF_CoerceParm | CPF_NeedCtorLink )

void UConsole::eventOutputText ( struct FString Text )
{
	static UFunction* pFnOutputText = NULL;

	if ( ! pFnOutputText )
		pFnOutputText = UObject::FindObject<UFunction>("Function Engine.Console:OutputText");

	UConsole_eventOutputText_Parms OutputText_Parms;
	memcpy ( &OutputText_Parms.Text, &Text, 0xC );

	this->ProcessEvent ( pFnOutputText, &OutputText_Parms, NULL );
};

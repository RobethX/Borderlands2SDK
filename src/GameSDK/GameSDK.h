#ifndef GAMESDK_H
#define GAMESDK_H

#define GObjects_Pattern		"\x00\x00\x00\x00\x8B\x04\xB1\x8B\x40\x08"
#define GObjects_Mask			"????xxxxxx"

#define GNames_Pattern			"\x00\x00\x00\x00\x83\x3C\x81\x00\x74\x5C"
#define GNames_Mask				"????xxxxxx"

#define ProcessEvent_Pattern	"\x55\x8B\xEC\x6A\xFF\x68\x00\x00\x00\x00\x64\xA1\x00\x00\x00\x00\x50\x83\xEC\x50\xA1\x00\x00\x00\x00\x33\xC5\x89\x45\xF0\x53\x56\x57\x50\x8D\x45\xF4\x64\xA3\x00\x00\x00\x00\x8B\xF1\x89\x75\xEC"
#define ProcessEvent_Mask		"xxxxxx????xx????xxxxx????xxxxxxxxxxxxxx????xxxxx"

#define CrashHandler_Pattern	"\x55\x8B\xEC\x6A\xFF\x68\x00\x00\x00\x00\x64\xA1\x00\x00\x00\x00\x50\x81\xEC\x00\x00\x00\x00\xA1\x00\x00\x00\x00\x33\xC5\x89\x45\xF0\x53\x56\x57\x50\x8D\x45\xF4\x64\xA3\x00\x00\x00\x00\x83\x3D\x00\x00\x00\x00\x00\x8B\x7D\x0C"
#define CrashHandler_Mask		"xxxxxx????xx????xxx????x????xxxxxxxxxxxxxx????xx?????xxx"

#define GObjHash_Pattern		"\x00\x00\x00\x00\x8B\x4E\x30\x8B\x46\x2C\x8B\x7E\x28"
#define GObjHash_Mask			"????xxxxxxxxx"

namespace BL2SDK
{
	unsigned long GNames();
	unsigned long GObjects();
	unsigned long addrProcessEvent();
	unsigned long GObjHash();
}

#include "GameSDK/GameDefines.h"
#include "GameSDK/Core_structs.h"
#include "GameSDK/Core_classes.h"
#include "GameSDK/Core_f_structs.h"
#include "GameSDK/Engine_structs.h"
#include "GameSDK/Engine_classes.h"
#include "GameSDK/Engine_f_structs.h"
#include "GameSDK/GameFramework_structs.h"
#include "GameSDK/GameFramework_classes.h"
#include "GameSDK/GameFramework_f_structs.h"

#endif
#ifndef CHOOKMANAGER_H
#define CHOOKMANAGER_H

#include "BL2SDK/BL2SDK.h"
#include <string>
#include <map>

class CHookManager
{
public:
	typedef std::map<std::string, void*> tHookMap;
	typedef std::pair<std::string, void*> tFuncNameHookPair;
	typedef tHookMap::iterator tiHookMap;
	typedef std::map<std::string, tHookMap>::iterator tiVirtualHooks;
	typedef std::map<UFunction*, tHookMap>::iterator tiStaticHooks;

private:
	tHookMap* GetVirtualHookTable(const std::string& funcName);
	tHookMap* GetStaticHookTable(UFunction* pFunction);
	bool RemoveFromTable(tHookMap& hookTable, const std::string& funcName, const std::string& hookName);

public:
	std::map<std::string, tHookMap> VirtualHooks;
	std::map<UFunction*, tHookMap> StaticHooks;

	void Register(const std::string& funcName, const std::string& hookName, void* funcHook);
	bool Remove(const std::string& funcName, const std::string& hookName);
	void AddVirtualHook(const std::string& funcName, const tFuncNameHookPair& hookPair);
	void AddStaticHook(UFunction* pFunction, const tFuncNameHookPair& hookPair);
	bool RemoveStaticHook(UFunction* pFunction, const std::string& hookName);
	bool RemoveVirtualHook(const std::string& funcName, const std::string& hookName);
	void ResolveVirtualHooks(UFunction* pFunction);
};

#endif
local ffi = require("ffi")

local FILE_HEADER = [[
-- ###################################
-- # Borderlands 2 SDK
-- # Package: %s
-- # File Contents: %s
-- ###################################

]]

SDKGen = { Package = {}, Errors = {}, PackageOrder = {} }

function SDKGen.SortProperty(propA, propB)
	-- Note that propA and propB should already be UProperty*

	-- First check if they are booleans and share the same offset. Compare bitmasks if so.
	-- Otherwise just compare their offset in the struct.
	if 	propA.UProperty.Offset == propB.UProperty.Offset
		and propA:IsA(engine.Classes.UBoolProperty)
		and propB:IsA(engine.Classes.UBoolProperty)
	then
		propA = ffi.cast("struct UBoolProperty*", propA)
		propB = ffi.cast("struct UBoolProperty*", propB)

		return propA.UBoolProperty.BitMask < propB.UBoolProperty.BitMask
	else
		return propA.UProperty.Offset < propB.UProperty.Offset
	end
end

local types = {
	ByteProperty = { c = "unsigned char" },
	ByteAttributeProperty = { c = "unsigned char" },
	IntProperty = { c = "int" },
	IntAttributeProperty = { c = "int" },
	FloatProperty = { c = "float" },
	FloatAttributeProperty = { c = "float" },
	BoolProperty = { c = "bool" }, -- bool is added by LuaJIT's implementation
	StrProperty = { c = "struct FString" },
	NameProperty = { c = "struct FName" },
	DelegateProperty = { c = "struct FScriptDelegate" },
	ObjectProperty = { c = "struct %s*", size = 4, generated = true },
	ClassProperty = { c = "struct %s*", size = 4, generated = true },
	ComponentProperty = { c = "struct %s*", size = 4, generated = true },
	InterfaceProperty = { c = "struct FScriptInterface" },
	StructProperty = { c = "struct %s", generated = true },
	ArrayProperty = { c = "struct TArray_%s_", size = 12, generated = true }
	--MapProperty = ...
}

function SDKGen.GetPropertyTypeData(prop)
	local propType = types[prop.UObject.Class:GetName()]
	if not propType then
		SDKGen.AddError(string.format("Property type (%s) for %s in %s not found",
			prop.UObject.Class:GetName(),
			prop:GetName(),
			prop.UObject.Outer:GetName()
		))
		return false 
	end

	return propType
end

function SDKGen.GetPropertyType(prop)
	local propType = types[prop.UObject.Class:GetName()]
	if not propType then
		SDKGen.AddError(string.format("Property type (%s) for %s in %s not found",
			prop.UObject.Class:GetName(),
			prop:GetName(),
			prop.UObject.Outer:GetName()
		))
		return false 
	end

	propType = propType.c

	if prop:IsA(engine.Classes.UClassProperty) then
		prop = ffi.cast("struct UClassProperty*", prop)
		propType = string.format(propType, prop.UClassProperty.MetaClass:GetCName())
	elseif prop:IsA(engine.Classes.UObjectProperty) then -- Covers UComponentProp too
		prop = ffi.cast("struct UObjectProperty*", prop)
		propType = string.format(propType, prop.UObjectProperty.PropertyClass:GetCName())
	elseif prop:IsA(engine.Classes.UStructProperty) then
		prop = ffi.cast("struct UStructProperty*", prop)
		propType = string.format(propType, prop.UStructProperty.Struct:GetCName())
	elseif prop:IsA(engine.Classes.UArrayProperty) then
		prop = ffi.cast("struct UArrayProperty*", prop)
		propType = string.format(propType, SDKGen.GetCleanPropertyType(prop.UArrayProperty.Inner))
	end

	return propType
end

function SDKGen.GetCleanPropertyType(prop)
	local propType = SDKGen.GetPropertyType(prop)

	propType = string.gsub(propType, "*", "Ptr")
	propType = string.gsub(propType, "struct ", "")
	propType = string.gsub(propType, " ", "_")

	return propType
end

function SDKGen.GetCPropertySize(prop)
	if prop:IsA(engine.Classes.UStructProperty) then
		return prop.UProperty.ElementSize
	end

	local propType = types[prop.UObject.Class:GetName()]
	if not propType then
		return 0
	elseif propType.size ~= nil then
		return propType.size
	else
		return ffi.sizeof(propType.c) or 0
	end
end

local objectCounts = {}

function SDKGen.CountObject(objectName, class)
	if objectCounts[objectName.Index] ~= nil then
		return objectCounts[objectName.Index]
	end

	local count = 0

	local iHash = engine.GetObjectHash(objectName)
	local hash = engine.ObjHash[iHash]
	while NotNull(hash) do

		if hash:IsA(class) and hash.UObject.Name.Index == objectName.Index then
			count = count + 1
		end

		hash = hash.UObject.HashNext
	end

	objectCounts[objectName.Index] = count
	return count
end

function SDKGen.AddError(errorText)
	table.insert(SDKGen.Errors, errorText)
end

local Package = SDKGen.Package
Package.__index = Package

function Package.new(package_object)
	return setmetatable({ PackageObj = package_object }, Package)
end

function Package:CreateFile(folder)
	local package_name = self.PackageObj:GetName()
	self.File = io.open("D:\\dev\\bl\\Borderlands2SDK\\bin\\Debug\\lua\\sdkgen\\" .. folder .. "\\" .. package_name .. ".lua", "w+")
end

function Package:CloseFile()
	if self.File then
		self.File:close()
		self.File = nil
	end
end

function Package:Close()
	self:CloseFile()
end

function Package:WriteFileHeader(contents)
	self.File:write(string.format(FILE_HEADER, self.PackageObj:GetName(), contents))
end

function Package:WriteCDefWrapperStart()
	self.File:write("local ffi = require(\"ffi\")\n\nffi.cdef[[\n\n")
end

function Package:WriteCDefWrapperEnd()
	self.File:write("]]")
end

include("sdkgen_tarray.lua")
include("sdkgen_consts.lua")
include("sdkgen_enums.lua")
include("sdkgen_structs.lua")
include("sdkgen_classes.lua")

local function ProcessPackages()
	profiling.StartTimer("sdkgen", "SDK generation")

	SDKGen.TArrayTypes.Init()

	local processed = {}

	for i=0,(engine.Objects.Count-1) do

		local obj = engine.Objects:Get(i)
		if IsNull(obj) then goto continue end
		if not obj:IsA(engine.Classes.UClass) then goto continue end
		
		local package_object = obj:GetPackageObject()
		if IsNull(package_object) then goto continue end
		if table.contains(processed, package_object) then goto continue end

		local pkg = Package.new(package_object)

		pkg:ProcessConstants()
		pkg:ProcessEnums()
		pkg:ProcessScriptStructs()
		pkg:ProcessClasses()

		pkg:Close()

		table.insert(processed, package_object)

		::continue::
	end

	SDKGen.TArrayTypes.Finalize()

	profiling.StopTimer("sdkgen")
end

local function PrintErrors()
	print("====== SDK GENERATOR ERRORS ======")
	for _, err in ipairs(SDKGen.Errors) do
		print(err)
	end
	print("====== END ERRORS ======")
end

ProcessPackages()
PrintErrors()

for _,v in ipairs(SDKGen.PackageOrder) do
	print(v:GetName())
end
local ffi = require("ffi")
local bit = require("bit")
local band, bnot, rshift = bit.band, bit.bnot, bit.rshift
local engine = engine
local Package = SDKGen.Package
local GeneratedStructs = {}
local DefaultStruct = engine.FindObject("ScriptStruct Core.Default__ScriptStruct", engine.Classes.UScriptStruct)
local STRUCT_ALIGN = 4

-- Add the structs added manually to the generated list so they aren't generated again
local preGenerated = { "Core.Object.Pointer", "Core.Object.QWord" }
for _, structName in ipairs(preGenerated) do
	local struct = engine.FindObject("ScriptStruct " .. structName, engine.Classes.UScriptStruct)
	if NotNull(struct) then
		table.insert(GeneratedStructs, struct)
	end
end

local ScriptStruct = {}
ScriptStruct.__index = ScriptStruct

function ScriptStruct.new(obj)
	return setmetatable({ Struct = ffi.cast("struct UScriptStruct*", obj), UnknownDataIndex = 0, ConsecBools = 0 }, ScriptStruct)
end

function ScriptStruct:GeneratePrereqs(inPackage)
	local scriptStruct = self.Struct
	local structPackage = scriptStruct:GetPackageObject()
	local structText = ""

	if IsNull(structPackage) or structPackage ~= inPackage then
		return structText
	end

	if scriptStruct == DefaultStruct then return end -- Skip the default because it's a dummy
	if table.contains(GeneratedStructs, scriptStruct) then return end -- Skip it if we've already made it

	-- First, check to see if this struct has a base. If it does, make sure we have generated it before
	-- we move on.

	local base = scriptStruct.UStruct.SuperField

	if 	NotNull(base)
		and base ~= scriptStruct
		and not table.contains(GeneratedStructs, base) 
	then
		structText = structText .. ScriptStruct.new(base):GeneratePrereqs(inPackage)
	end

	-- Next, check to see if there are any members of this struct which we haven't yet generated.
	-- If there are, generate them before moving on. There are two cases here: a plain old struct,
	-- and a TArray of structs. There could also be TMap, but this data structure doesn't seem to
	-- be present in BL2.

	local structField = ffi.cast("struct UProperty*", scriptStruct.UStruct.Children)
	while NotNull(structField) do -- Foreach property in the struct

		if structField:IsA(engine.Classes.UStructProperty) then -- If it's a plain old struct
			structField = ffi.cast("struct UStructProperty*", structField)

			local fieldStruct = structField.UStructProperty.Struct

			-- If the struct for this field hasn't been generated, DO IT NOW.
			if 	fieldStruct ~= scriptStruct 
				and not table.contains(GeneratedStructs, fieldStruct) 
			then
				structText = structText .. ScriptStruct.new(structField.UStructProperty.Struct):GeneratePrereqs(inPackage)
			end
		elseif structField:IsA(engine.Classes.UArrayProperty) then
			structField = ffi.cast("struct UArrayProperty*", structField)

			local innerProperty = structField.UArrayProperty.Inner
			if innerProperty:IsA(engine.Classes.UStructProperty) then
				local innerStruct = ffi.cast("struct UStructProperty*", innerProperty).UStructProperty.Struct

				if 	NotNull(innerStruct)
					and innerStruct ~= scriptStruct
					and not table.contains(GeneratedStructs, innerStruct) 
				then
					structText = structText .. ScriptStruct.new(innerStruct):GeneratePrereqs(inPackage)
				end
			end

			-- Check if we need to generate the TArray template for the inner type
			-- and do it if we need to.
			if not SDKGen.TArrayTypes.IsGenerated(innerProperty) then
				SDKGen.TArrayTypes.Generate(innerProperty)
			end
		end

		-- TMap would be here if BL needed it

		structField = ffi.cast("struct UProperty*", structField.UField.Next)
	end

	-- All the requisite structs should have been generated by now, so we can generate this one
	structText = structText .. self:GenerateDefinition()
	return structText
end

function ScriptStruct:GetFieldsSize()
	return self.Struct.UStruct.PropertySize
end

function ScriptStruct:GenerateDefinition()
	local scriptStruct = self.Struct

	SDKGen.DebugPrint("[SDKGen] Struct " .. scriptStruct:GetFullName())

	-- Start by defining the struct with its name
	local count = SDKGen.CountObject(scriptStruct.UObject.Name, engine.Classes.UScriptStruct)
	local structText
	if count == 1 then
		structText = "struct " .. scriptStruct:GetCName() .. " {\n"
	else
		structText = "struct " .. scriptStruct.UObject.Outer:GetCName() .. "_" .. scriptStruct:GetCName() .. " {\n"
	end

	-- Check if this struct has a base which it inherits from. If it does, instead of doing
	-- some hacky C struct inheritance, just put all the base fields straight into the def
	-- for this struct.
	local base = scriptStruct.UStruct.SuperField
	local actualStart = 0
	if NotNull(base) and base ~= scriptStruct then
		local baseStruct = ScriptStruct.new(base)
		structText = structText .. baseStruct:FieldsToC(0)
		actualStart = actualStart + baseStruct:GetFieldsSize()
	end

	structText = structText .. self:FieldsToC(actualStart)
	structText = structText .. "};\n\n"

	table.insert(GeneratedStructs, scriptStruct)

	return structText
end

function ScriptStruct:FieldsToC(lastOffset)
	local scriptStruct = self.Struct

	-- Foreach property, add them into the properties array
	local properties = {}
	local structProperty = ffi.cast("struct UProperty*", scriptStruct.UStruct.Children)
	while NotNull(structProperty) do
		if structProperty.UProperty.ElementSize > 0 and not structProperty:IsA(engine.Classes.UScriptStruct) then
			table.insert(properties, structProperty)
		end

		structProperty = ffi.cast("struct UProperty*", structProperty.UField.Next)
	end

	-- Next, sort the properties according to their offset in the struct. When dealing with
	-- boolean types, we need the one with the smallest bitmask first.
	table.sort(properties, SDKGen.SortProperty)

	local out = ""
	for _,property in ipairs(properties) do

		-- If the offset for this property is ahead of the end of the last property,
		-- add some unknown data into the struct def.
		if lastOffset < property.UProperty.Offset then
			out = out .. self:MissedOffset(lastOffset, (property.UProperty.Offset - lastOffset))
		end

		-- Get the type and size of the property
		local typeof = SDKGen.GetPropertyType(property)
		local size = property.UProperty.ElementSize * property.UProperty.ArrayDim

		-- If the type isn't one we recognize, add unknown data to the def.
		if not typeof then
			out = out .. string.format("\tunsigned char %s[0x%X]; // 0x%X (0x%X) UNKNOWN PROPERTY\n",
				property:GetName(),
				size,
				property.UProperty.Offset,
				size)
		else
			local special = ""

			if property.UProperty.ArrayDim > 1 then -- It's a C style array, so [x] needed
				special = special .. string.format("[%d]", property.UProperty.ArrayDim)
			end

			if property:IsA(engine.Classes.UBoolProperty) then
				special = special .. " : 1" -- A bool is defined as a 1 bit unsigned long
				self.ConsecBools = self.ConsecBools + 1

			-- If this property is not a bool, but the previous properties (or property)
			-- have been, then padding might be needed, see FixBitfields()
			elseif self.ConsecBools > 0 then
				out = out .. self:FixBitfields()
 			end

			out = out .. string.format("\t%s %s%s; // 0x%X (0x%X)\n",
				typeof,
				property:GetName(),
				special,
				property.UProperty.Offset,
				size)

			-- It's possible that our C definition for this type is not correct
			-- If that's the case, we need to ensure that the fields are still 
			-- at their correct offsets. So here we'll add some data to fix our 
			-- dodgy definition.
			local actualSize = SDKGen.GetCPropertySize(property) * property.UProperty.ArrayDim
			local missedSize = size - actualSize
			if missedSize > 0 then
				out = out .. self:MissedOffset(property.UProperty.Offset + missedSize, missedSize, "PROPERTY C DEF INCORRECT")
			elseif missedSize < 0 then
				error(property.UObject.Class:GetName() .. " has an incorrect C definition (too big)!")
			end
		end

		lastOffset = property.UProperty.Offset + (property.UProperty.ElementSize * property.UProperty.ArrayDim)
	end

	-- Make sure that if the last property was a bitfield, the appropriate padding is added
	if self.ConsecBools > 0 then
		out = out .. self:FixBitfields()
	end

	-- If there is additional data after the last property we have, add it to the end
	if lastOffset < self:GetFieldsSize() then
		out = out .. self:MissedOffset(lastOffset, (self:GetFieldsSize() - lastOffset))
	end

	return out
end

-- See classes.lua for a rant on this
function ScriptStruct:FixBitfields()
	local out = ""
	local neededPadding = band(rshift(band((32 - band(self.ConsecBools, 31)), bnot(7)), 3), 3)
	if neededPadding > 0 then
		out = out .. string.format("\tunsigned char Unknown%d[0x%X]; // BITFIELD FIX\n", 
			self.UnknownDataIndex,
			neededPadding)
	end

	self.ConsecBools = 0

	return out
end

function ScriptStruct:MissedOffset(at, missedSize, reason)
	if missedSize < STRUCT_ALIGN then return "" end
	if reason == nil then reason = "MISSED OFFSET" end

	self.UnknownDataIndex = self.UnknownDataIndex + 1

	SDKGen.AddError("Missed offset in " .. self.Struct:GetFullName() .. " (Reason = " .. reason .. ")")

	return string.format("\tunsigned char Unknown%d[0x%X]; // 0x%X (0x%X) %s\n", 
		self.UnknownDataIndex,
		missedSize,
		at,
		missedSize,
		reason)
end

function Package:ProcessScriptStructs()
	self:CreateFile("structs")
	self:WriteFileHeader("Script Structs")

	self:WriteCDefWrapperStart()

	-- Foreach object, check if it's a scriptstruct, then check if it's in the package.
	-- If it is, then process the struct
	for i=0,(engine.Objects.Count-1) do

		local obj = engine.Objects:Get(i)
		if IsNull(obj) then goto continue end

		local package_object = obj:GetPackageObject()
		if IsNull(package_object) then goto continue end
		if package_object ~= self.PackageObj then goto continue end

		if not obj:IsA(engine.Classes.UScriptStruct) then goto continue end

		self.File:write(ScriptStruct.new(obj):GeneratePrereqs(self.PackageObj)) -- Generate the requisite structs then generate this one

		::continue:: -- INSERT COIN TO CONTINUE
	end

	self:WriteCDefWrapperEnd()
	self:CloseFile()
end

local ffi = require("ffi")
local engine = engine
local Package = SDKGen.Package
local GeneratedClasses = {}
local DefaultClass = engine.FindObject("Class Core.Default__Class", engine.Classes.UClass)
local CLASS_ALIGN = 4

-- Add the classes added manually to the generated list so they aren't generated again
for _, v in pairs(engine.Classes) do
	table.insert(GeneratedClasses, v.static)
end

local Class = {}
Class.__index = Class

function Class.new(obj)
	return setmetatable({ ClassObj = ffi.cast("struct UClass*", obj), UnknownDataIndex = 0 }, Class)
end

function Class:GeneratePrereqs(inPackage)
	local class = self.ClassObj
	local classPackage = class:GetPackageObject()
	local classText = ""

	if IsNull(classPackage) or classPackage ~= inPackage then
		return classText
	end

	if class == DefaultClass then return end -- Skip the default because it's a dummy
	if table.contains(GeneratedClasses, class) then return end -- Skip it if we've already made it

	-- First, check to see if this class has a base. If it does, make sure we have generated it before
	-- we move on.

	local base = class.UStruct.SuperField

	if 	NotNull(base)
		and base ~= class
		and not table.contains(GeneratedClasses, base) 
	then
		classText = classText .. Class.new(base):GeneratePrereqs(inPackage)
	end

	-- When we're generating structs, we had to check for field types which hadn't
	-- yet been generated, but since classes are loaded last of all the data structures
	-- everything should already be there. Only thing we need to do is generate the
	-- TArray definitions, if there are any.

	local classField = ffi.cast("struct UProperty*", class.UStruct.Children)
	while NotNull(classField) do -- Foreach property in the class

		if classField:IsA(engine.Classes.UArrayProperty) then
			classField = ffi.cast("struct UArrayProperty*", classField)

			local innerProperty = classField.UArrayProperty.Inner

			-- Check if we need to generate the TArray template for the inner type
			-- and do it if we need to.
			if not SDKGen.TArrayTypes.IsGenerated(innerProperty) then
				SDKGen.TArrayTypes.Generate(innerProperty)
			end
		end

		classField = ffi.cast("struct UProperty*", classField.UField.Next)
	end

	-- All the requisite data structures should have been generated by now, so we can generate this one
	classText = classText .. self:GenerateDefinition()
	return classText
end

function Class:GetFieldsSize()
	return self.ClassObj.UStruct.PropertySize
end

function Class:GenerateDefinition()
	local class = self.ClassObj
	local cname = class:GetCName()

	print("[SDKGen] Class " .. class:GetFullName())

	-- Start by defining the class with name_Data and put the fields in there
	local classText = "struct " .. cname .. "_Data {\n"

	-- Add the fields of this class into the struct
	classText = classText .. self:FieldsToC()

	classText = classText .. "};\n\n"

	-- Now we have the data fields for this class, write the inheritance struct
	classText = classText .. "struct " .. cname .. " {\n"

	-- Needs to be in reverse order, so going to create a new string buffer
	-- that we can prepend to.
	local inheritText = ""
	local base = ffi.cast("struct UClass*", class.UStruct.SuperField)
	while NotNull(base) do
		local name = base:GetCName()
		inheritText = string.format("\tstruct %s_Data %s;\n", name, name) .. inheritText
		base = ffi.cast("struct UClass*", base.UStruct.SuperField)
	end

	-- At the end, make sure we have the actual class
	inheritText = inheritText .. string.format("\tstruct %s_Data %s;\n};\n\n", cname, cname)
	classText = classText .. inheritText

	table.insert(GeneratedClasses, class)

	return classText
end

function Class:FieldsToC()
	local class = self.ClassObj

	-- Foreach property, add them into the properties array
	local properties = {}
	local classProperty = ffi.cast("struct UProperty*", class.UStruct.Children)
	while NotNull(classProperty) do
		if 	classProperty.UProperty.ElementSize > 0
			and not classProperty:IsA(engine.Classes.UConst) -- Consts and enums are in children
			and not classProperty:IsA(engine.Classes.UEnum)
		then
			table.insert(properties, classProperty)
		end

		classProperty = ffi.cast("struct UProperty*", classProperty.UField.Next)
	end

	-- Next, sort the properties according to their offset in the class. When dealing with
	-- boolean types, we need the one with the smallest bitmask first.
	table.sort(properties, SDKGen.SortProperty)

	-- Get the position that the first property of this class should be starting at
	-- If there's no base class, it'll be 0, otherwise it will be the size of the base
	-- and all its bases. 
	local lastOffset = 0

	local base = ffi.cast("struct UClass*", class.UStruct.SuperField)
	while NotNull(base) do
		lastOffset = lastOffset + base.UStruct.PropertySize
		base = ffi.cast("struct UClass*", base.UStruct.SuperField)
	end

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

	-- If there is additional data after the last property we have, add it to the end
	if lastOffset < self:GetFieldsSize() then
		out = out .. self:MissedOffset(lastOffset, (self:GetFieldsSize() - lastOffset))
	end

	return out
end

function Class:MissedOffset(at, missedSize, reason)
	if missedSize < CLASS_ALIGN then return "" end
	if reason == nil then reason = "MISSED OFFSET" end

	self.UnknownDataIndex = self.UnknownDataIndex + 1

	SDKGen.AddError("Missed offset in " .. self.ClassObj:GetFullName() .. " (Reason = " .. reason .. ")")

	return string.format("\tunsigned char Unknown%d[0x%X]; // 0x%X (0x%X) %s\n", 
		self.UnknownDataIndex,
		missedSize,
		at,
		missedSize,
		reason)
end

function Package:ProcessClasses()

	self:CreateFile("classes")
	self:WriteFileHeader("Class definitions")

	self:WriteCDefWrapperStart()

	-- Foreach object, check if it's a class, then check if it's in the package.
	-- If it is, then process the class
	for i=0,(engine.Objects.Count-1) do

		local obj = engine.Objects:Get(i)
		if IsNull(obj) then goto continue end

		local package_object = obj:GetPackageObject()
		if IsNull(package_object) then goto continue end
		if package_object ~= self.PackageObj then goto continue end

		if not obj:IsA(engine.Classes.UClass) then goto continue end

		self.File:write(Class.new(obj):GeneratePrereqs(self.PackageObj)) -- Generate the requisite things then generate this one

		::continue::
	end

	self:WriteCDefWrapperEnd()
	self:CloseFile()
end

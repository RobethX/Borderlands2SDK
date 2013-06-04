local ffi = require("ffi")

ffi.cdef[[
typedef void (__thiscall *tGwen_Controls_Slider_SetClampToNotches) (GwenControl*, bool);
typedef void (__thiscall *tGwen_Controls_Slider_SetNotchCount) (GwenControl*, int);
typedef int (__thiscall *tGwen_Controls_Slider_GetNotchCount) (GwenControl*);
typedef void (__thiscall *tGwen_Controls_Slider_SetRange) (GwenControl*, float, float);
typedef float (__thiscall *tGwen_Controls_Slider_GetFloatValue) (GwenControl*);
typedef void (__thiscall *tGwen_Controls_Slider_SetFloatValue) (GwenControl*, float, bool);
typedef float (__thiscall *tGwen_Controls_Slider_CalculateValue) (GwenControl*);
typedef float (__thiscall *tGwen_Controls_Slider_GetMin) (GwenControl*);
typedef float (__thiscall *tGwen_Controls_Slider_GetMax) (GwenControl*);
]]

local Slider = table.copy(gwen.meta.InheritedControl)
Slider.__index = Slider

function Slider:SetClampToNotches(bClamp)
	local func = gwen.GetVFunc(self.control, 169, "tGwen_Controls_Slider_SetClampToNotches")
	func(self.control, bClamp)
end

function Slider:SetNotchCount(num)
	local func = gwen.GetVFunc(self.control, 170, "tGwen_Controls_Slider_SetNotchCount")
	func(self.control, num)
end

function Slider:GetNotchCount()
	local func = gwen.GetVFunc(self.control, 171, "tGwen_Controls_Slider_GetNotchCount")
	return func(self.control)
end

function Slider:SetRange(fMin, fMax)
	local func = gwen.GetVFunc(self.control, 172, "tGwen_Controls_Slider_SetRange")
	func(self.control, fMin, fMax)
end

function Slider:GetFloatValue()
	local func = gwen.GetVFunc(self.control, 173, "tGwen_Controls_Slider_GetFloatValue")
	return func(self.control)
end

function Slider:SetFloatValue(val, forceUpdate)
	if forceUpdate == nil then forceUpdate = true end
	local func = gwen.GetVFunc(self.control, 174, "tGwen_Controls_Slider_SetFloatValue")
	func(self.control, val, forceUpdate)
end

function Slider:CalculateValue()
	local func = gwen.GetVFunc(self.control, 175, "tGwen_Controls_Slider_CalculateValue")
	return func(self.control)
end

function Slider:GetMin()
	local func = gwen.GetVFunc(self.control, 177, "tGwen_Controls_Slider_GetMin")
	return func(self.control)
end

function Slider:GetMax()
	local func = gwen.GetVFunc(self.control, 178, "tGwen_Controls_Slider_GetMax")
	return func(self.control)
end

function Slider:AddOnValueChanged(func)
	gwen.AddCallback(self.control, 232, "OnValueChanged", func)
end

gwen.meta.Slider = Slider

--[[
VMT dump from IDA
169: public: virtual void __thiscall Gwen::Controls::Slider::SetClampToNotches(bool)
170: public: virtual void __thiscall Gwen::Controls::Slider::SetNotchCount(int)
171: public: virtual int __thiscall Gwen::Controls::Slider::GetNotchCount(void)
172: public: virtual void __thiscall Gwen::Controls::Slider::SetRange(float, float)
173: public: virtual float __thiscall Gwen::Controls::Slider::GetFloatValue(void)
174: public: virtual void __thiscall Gwen::Controls::Slider::SetFloatValue(float, bool)
175: public: virtual float __thiscall Gwen::Controls::Slider::CalculateValue(void)
#176: public: virtual void __thiscall Gwen::Controls::Slider::OnMoved(class Gwen::Controls::Base *)
177: public: virtual float __thiscall Gwen::Controls::Slider::GetMin(void)
178: public: virtual float __thiscall Gwen::Controls::Slider::GetMax(void)
#179: protected: virtual void __thiscall Gwen::Controls::Slider::SetValueInternal(float)
]]
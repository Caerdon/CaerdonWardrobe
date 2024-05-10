-- Pulled from FrameXML / ObjectAPI / AsyncCallbackSystem.lua
-- This implementation ensures a callback can receive load failures as well
--[[
	Queries some data retrieval API (specifically where the data may not be currently available) and when it becomes available
	calls a user-supplied function.  The callback can be canceled if necessary (e.g. the frame that would use the data becomes
	hidden before the data arrives).

	The API is managed so that arbitrary query functions cannot be executed.
--]]

-- AsyncCallbackAPIType = {
-- 	ASYNC_QUEST = 1,
-- 	ASYNC_ITEM = 2,
-- 	ASYNC_SPELL = 3,
-- }

local permittedAPI =
{
	[AsyncCallbackAPIType.ASYNC_QUEST] = { event = "QUEST_DATA_LOAD_RESULT", accessor =  C_QuestLog.RequestLoadQuestByID },
	[AsyncCallbackAPIType.ASYNC_ITEM] = { event = "ITEM_DATA_LOAD_RESULT", accessor =  C_Item.RequestLoadItemDataByID },
	[AsyncCallbackAPIType.ASYNC_SPELL] = { event = "SPELL_DATA_LOAD_RESULT", accessor =  C_Spell.RequestLoadSpellData },
};

CaerdonAsyncCallbackSystemMixin = {};

function CaerdonAsyncCallbackSystemMixin:Init(apiType)
	self.successCallbacks = {};
	self.failureCallbacks = {};

	-- API Type should be set up from key value pairs before OnLoad.
	self.api = permittedAPI[apiType];

	self:SetScript("OnEvent",
		function(self, event, ...)
			if event == self.api.event then
				local id, success = ...;
				if success then
					self:FireSuccessCallbacks(id);
				else
					self:FireFailureCallbacks(id);
				end
			end
		end
	);
	self:RegisterEvent(self.api.event);
end

local CANCELED_SENTINEL = -1;

function CaerdonAsyncCallbackSystemMixin:AddCallback(id, successCallbackFunction, failureCallbackFunction)
	local successCallbacks = self:GetOrCreateSuccessCallbacks(id);
  local failureCallbacks = self:GetOrCreateFailureCallbacks(id);
	table.insert(successCallbacks, successCallbackFunction);
	table.insert(failureCallbacks, failureCallbackFunction);
	local needsAccessorCall = #successCallbacks == 1;
	if needsAccessorCall then
		self.api.accessor(id);
	end

	return #successCallbacks, successCallbacks, #failureCallbacks, failureCallbacks;
end

function CaerdonAsyncCallbackSystemMixin:AddCancelableCallback(id, successCallbackFunction, failureCallbackFunction)
	-- NOTE: If the data is currently availble then the callback will be executed and callbacks cleared, so there will be nothing to cancel.
	local successIndex, successCallbacks, failureIndex, failureCallbacks = self:AddCallback(id, successCallbackFunction, failureCallbackFunction);
	return function()
		if #successCallbacks > 0 and successCallbacks[successIndex] ~= CANCELED_SENTINEL then
			successCallbacks[successIndex] = CANCELED_SENTINEL;
      failureCallbacks[failureIndex] = CANCELED_SENTINEL;
			return true;
		end
		return false;
	end;
end

function CaerdonAsyncCallbackSystemMixin:FireSuccessCallbacks(id)
	local callbacks = self:GetSuccessCallbacks(id);
	if callbacks then
		self:ClearCallbacks(id);
		for i, callback in ipairs(callbacks) do
			if callback ~= CANCELED_SENTINEL then
				xpcall(callback, CallErrorHandler);
			end
		end

		-- The cancel functions have a reference to this table, so ensure that it's cleared out.
		for i = #callbacks, 1, -1 do
			callbacks[i] = nil;
		end
	end
end

function CaerdonAsyncCallbackSystemMixin:FireFailureCallbacks(id)
	local callbacks = self:GetFailureCallbacks(id);
	if callbacks then
		self:ClearCallbacks(id);
		for i, callback in ipairs(callbacks) do
			if callback ~= CANCELED_SENTINEL then
				xpcall(callback, CallErrorHandler);
			end
		end

		-- The cancel functions have a reference to this table, so ensure that it's cleared out.
		for i = #callbacks, 1, -1 do
			callbacks[i] = nil;
		end
	end
end

function CaerdonAsyncCallbackSystemMixin:ClearCallbacks(id)
	self.successCallbacks[id] = nil;
	self.failureCallbacks[id] = nil;
end

function CaerdonAsyncCallbackSystemMixin:GetSuccessCallbacks(id)
	return self.successCallbacks[id]
end

function CaerdonAsyncCallbackSystemMixin:GetFailureCallbacks(id)
	return self.failureCallbacks[id]
end

function CaerdonAsyncCallbackSystemMixin:GetOrCreateSuccessCallbacks(id)
	local callbacks = self.successCallbacks[id];
	if not callbacks then
		callbacks = {};
		self.successCallbacks[id] = callbacks;
	end
	return callbacks;
end

function CaerdonAsyncCallbackSystemMixin:GetOrCreateFailureCallbacks(id)
	local callbacks = self.failureCallbacks[id];
	if not callbacks then
		callbacks = {};
		self.failureCallbacks[id] = callbacks;
	end
	return callbacks;
end

local function CreateListener(apiType)
	local listener = Mixin(CreateFrame("Frame"), AsyncCallbackSystemMixin);
	listener:Init(apiType);
	return listener;
end

CaerdonItemEventListener = CreateListener(AsyncCallbackAPIType.ASYNC_ITEM);
CaerdonSpellEventListener = CreateListener(AsyncCallbackAPIType.ASYNC_SPELL);
CaerdonQuestEventListener = CreateListener(AsyncCallbackAPIType.ASYNC_QUEST);

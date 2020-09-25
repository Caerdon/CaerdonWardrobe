local MailMixin = {}

function MailMixin:GetName()
	return "Mail"
end

function MailMixin:Init()
    hooksecurefunc("OpenMailFrame_UpdateButtonPositions", function(...) self:OnMailFrameUpdateButtonPositions(...) end)
    hooksecurefunc("SendMailFrame_Update", function(...) self:OnSendMailFrameUpdate(...) end)
    hooksecurefunc("InboxFrame_Update", function(...) self:OnInboxFrameUpdate(...) end)
end

function MailMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.type == "open" then
		local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInboxItem(InboxFrame.openMailID, locationInfo.index)
	elseif locationInfo.type == "send" then
		local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetSendMailItem(locationInfo.index)
	elseif locationInfo.type == "inbox" then
		local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInboxItem(locationInfo.index);
	else
		error(format("Unknown mail type: %s", locationInfo.type))
	end
end

function MailMixin:Refresh()
end

function MailMixin:OnMailFrameUpdateButtonPositions(letterIsTakeable, textCreated, stationeryIcon, money)
	for i=1, ATTACHMENTS_MAX_RECEIVE do
		local attachmentButton = OpenMailFrame.OpenMailAttachments[i];
		if HasInboxItem(InboxFrame.openMailID, i) then
			-- local name, itemID, itemTexture, count, quality, canUse = GetInboxItem(InboxFrame.openMailID, i);
			local itemLink = GetInboxItemLink(InboxFrame.openMailID, i)
			CaerdonWardrobe:UpdateButtonLink(attachmentButton, itemLink, self:GetName(), { type="open", index = i }, nil)
		else
            CaerdonWardrobe:ClearButton(attachmentButton)
		end
	end
end

function MailMixin:OnSendMailFrameUpdate()
	for i=1, ATTACHMENTS_MAX_SEND do
		local attachmentButton = SendMailFrame.SendMailAttachments[i];

		if HasSendMailItem(i) then
			local itemLink = GetSendMailItemLink(i)
			CaerdonWardrobe:UpdateButtonLink(attachmentButton, itemLink, self:GetName(), { type="send", index = i }, nil)
		else
            CaerdonWardrobe:ClearButton(attachmentButton)
		end
	end
end

function MailMixin:OnInboxFrameUpdate()
	local numItems, totalItems = GetInboxNumItems();

	for i=1, INBOXITEMS_TO_DISPLAY do
		local index = ((InboxFrame.pageNum - 1) * INBOXITEMS_TO_DISPLAY) + i;

		button = _G["MailItem"..i.."Button"];
		if ( index <= numItems ) then
			-- Setup mail item
			local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, x, y, z, isGM, firstItemQuantity, firstItemLink = GetInboxHeaderInfo(index);
			CaerdonWardrobe:UpdateButtonLink(button, firstItemLink, self:GetName(), { type="inbox", index = index }, nil)
		else
            CaerdonWardrobe:ClearButton(button)
		end
	end
end

CaerdonWardrobe:RegisterFeature(MailMixin)

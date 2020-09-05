CaerdonWardrobeConfigMixin = {}
CaerdonWardrobeConfigGeneralMixin = {}

function CaerdonWardrobeConfigMixin:OnLoad()
    self.name = "Caerdon Wardrobe"
	-- self.okay = PropagateErrors(self.OnSave)
	-- self.cancel = PropagateErrors(self.OnCancel)
	-- self.default = PropagateErrors(self.OnResetToDefaults)
	-- self.refresh = PropagateErrors(self.OnRefresh)

	-- InterfaceOptions_AddCategory(self)
end

function CaerdonWardrobeConfigGeneralMixin:OnLoad()
    self.name = "General"
    self.parent = "Caerdon Wardrobe"
	-- InterfaceOptions_AddCategory(self)
end
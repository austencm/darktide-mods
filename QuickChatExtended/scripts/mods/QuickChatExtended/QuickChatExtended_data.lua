local mod = get_mod("QuickChatExtended")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "enabled",
                type = "checkbox",
                default_value = true,
            },
        },
    },
}

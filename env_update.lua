settings.add("rtpax.env_update", "http_proxy https_proxy no_proxy", "Keep local environment up to date with registry")

local function get_env_from_reg(name, reg_path)
    local cmd = 'reg query "' .. reg_path .. '" /v "' .. name .. '" 2>nul'
    local handle = io.popen(cmd)
    if handle then
        local output = handle:read('*a')
        handle:close()
        
        -- Parse the output: look for the value after REG_SZ, REG_EXPAND_SZ, etc.
        local value = output:match(name .. '%s+REG_%w+%s+(.+)')
        if value then
            return value:gsub('%s+$', '') -- Trim trailing whitespace
        end
    end
    return nil
end

local function get_reg_env(name)
    -- Try user environment first
    local value = get_env_from_reg(name, "HKCU\\Environment")
    if value then return value end
    -- Try system environment if not found in user
    value = get_env_from_reg(name, "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment")
    return value
end

clink.oncommand(function()
    local env_update = settings.get("rtpax.env_update")
    if env_update and type(env_update) == "string" then
        for var in string.gmatch(env_update, "%S+") do
            local envvar = clink.get_env(var)
            local regvar = get_reg_env(var)
            if envvar ~= regvar then
                os.setenv(var, regvar)
            end
        end
    end
end)


settings.add("rtpax.cwd_title", true, "Show working directory in terminal title")
settings.add("rtpax.title", "cmd", "Set terminal title")

local current_cwd = ""
local current_title = ""
local display_cwd = ""

local home_dir = clink.get_env("USERPROFILE") -- tough luck if this changes halfway through a session

clink.onbeginedit(function()
    local do_cwd = settings.get("rtpax.cwd_title")

    local new_title = settings.get("rtpax.title")

    local update = false

    if new_title and new_title ~= current_title then
        update = true
        current_title = new_title
    end
    
    if do_cwd then
        local new_cwd = clink.get_cwd() or ""
        if new_cwd ~= current_cwd then
            update = true
            current_cwd = new_cwd
            if home_dir and home_dir == new_cwd then
                display_cwd = "~"
            else
                local dir_name = path.getname(new_cwd)
                if dir_name == "" then
                    display_cwd = new_cwd -- Fallback to full path if getname fails
                else
                    display_cwd = dir_name
                end
            end
        end
    end

    if update then
        if current_title ~= "" and current_cwd ~= "" then
            os.execute('title ' .. current_title .. ' ' .. display_cwd)
        elseif current_title ~= "" then
            os.execute('title ' .. current_title)
        elseif current_cwd ~= "" then
            os.execute('title ' .. display_cwd)
        end
    end    
end)

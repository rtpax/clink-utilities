settings.add("rtpax.trim_exe", true, "Hide .exe extensions for commands")

local system_exec_matches = clink._exec_matches

local function wrap_match_builder(original)
    local wrapper = { inner = original }

    function should_trim_exe(str)
        if #str >= 5 and str:sub(-4):lower() == ".exe" and not str:find("\\", 1, true) then
            local index = str:find("\\", 1, true)
            if index then -- don't trim ".exe" if found in directory
                return false
            else
                if os.isfile(str) then
                    return false
                end
                return true
            end
        else
            return false
        end
    end

    function trim_exe(str)
        return str:sub(1, -5)
    end

    function wrapper:addmatch(match, ...)
        if should_trim_exe(match.match) then
            match.match = trim_exe(match.match)
        end
        return wrapper.inner:addmatch(match, ...)
    end

    function wrapper:addmatches(matches, match_type)
        return wrapper.inner:addmatches(matches, match_type)
        -- if match_type then
        --     print("match_type: " .. match_type)
        --     for i, match in ipairs(matches) do
        --         print("match: " .. match)
        --     end
        --     return wrapper.inner:addmatches(matches, match_type)
        -- else
        --     print("default match_type")
        --     for i, m in ipairs(matches) do
        --         if should_trim_exe(m.match) then
        --             m.match = trim_exe(m.match)
        --         end
        --         print("match: " .. m.match)
        --     end
        --     return wrapper.inner:addmatches(matches)
        -- end
    end

    return wrapper
end

local function rtpax_exec_matches(line_state, match_builder, chained, no_aliases)
    local do_trim = settings.get("rtpax.trim_exe")
    if not do_trim or do_trim ~= true then
        system_exec_matches(line_state, match_builder, chained, no_aliases)
    else
        system_exec_matches(line_state, wrap_match_builder(match_builder), chained, no_aliases)
    end
    return true
end

local interceptor = clink.generator(49) -- just barely high enough priority to run before exec_generator
function interceptor:generate(line_state, match_builder)
    if line_state:getwordcount() == 1 then
        return rtpax_exec_matches(line_state, match_builder)
    end
end

clink._exec_matches = rtpax_exec_matches -- override the internal exec_matches function
-- TODO: make sure this gets set after exec.lua

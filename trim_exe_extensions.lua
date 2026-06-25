settings.add("rtpax.trim_exe", true, "Hide .exe extensions for commands")

local system_exec_matches = clink._exec_matches
local trim_multi_matches = false -- this has not been needed so far, and adds overhead, so only trim single matches for now. Can add later if needed.

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
        if trim_multi_matches then
            if match_type then
                return wrapper.inner:addmatches(matches, match_type)
            else
                for i, m in ipairs(matches) do
                    if should_trim_exe(m.match) then
                        m.match = trim_exe(m.match)
                    end
                end
                return wrapper.inner:addmatches(matches)
            end
        else
            return wrapper.inner:addmatches(matches, match_type)
        end
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
    return false -- let other generators handle it
end

clink._exec_matches = rtpax_exec_matches -- override the internal exec_matches function
-- TODO: make sure this gets set after exec.lua

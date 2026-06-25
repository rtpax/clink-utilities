settings.add("rtpax.trim_exe", true, "Hide .exe extensions for commands")

local function should_trim_exe(str)
    return #str >= 5
       and str:sub(-4):lower() == ".exe"
       and not str:find("\\", 1, true)
       and not str:find("/", 1, true)
end

local function trim_exe(str)
    return str:sub(1, -5)
end

local function basename(str)
    return str:match("[^/\\]*[/\\]?$") or str
end

local function make_setting_color_sequence(name)
    local value = settings.get(name)
    if type(value) ~= "string" or value == "" then
        return ""
    end
    return "\x1b[0;"..value.."m"
end

local function make_executable_display(trimmed)
    local color = make_setting_color_sequence("color.executable")
    if color == "" then
        return nil
    end
    return color..trimmed.."\x1b[m"
end

local function get_trim_key_for_match(str)
    if type(str) ~= "string" or #str < 5 then
        return nil
    end

    local name = basename(str)
    if #name >= 5 and name:sub(-4):lower() == ".exe" then
        return trim_exe(name):lower()
    end

    return nil
end

local function clone_match_with_trim(m, trimmed)
    local c = {}
    for k, v in pairs(m) do
        c[k] = v
    end
    c.match = trimmed
    c.display = make_executable_display(trimmed)
    return c
end

local function get_environment_paths()
    local paths = (os.getenv("path") or ""):explode(";")
    for i = 1, #paths, 1 do
        paths[i] = paths[i].."\\"
    end
    return paths
end

local function get_current_word(line_state)
    local word = line_state:getendword() or ""
    if #word == 0 then
        local wc = line_state:getwordcount() or 0
        if wc > 0 then
            local w = line_state:getword(wc)
            if type(w) == "string" then
                word = w
            end
        end
    end
    if #word == 0 then
        local line = line_state:getline() or ""
        local cursor = line_state:getcursor() or (#line + 1)
        if cursor < 1 then
            cursor = 1
        end
        if cursor > (#line + 1) then
            cursor = #line + 1
        end
        local before = line:sub(1, cursor - 1)
        word = before:match("[^ \t\r\n\"']+$") or ""
    end
    return word
end

local function add_trimmed_matches(matches, ret, seen)
    for _, m in ipairs(matches) do
        local name = m.match and basename(m.match)
        if name and should_trim_exe(name) then
            local trimmed = trim_exe(name)
            local key = trimmed:lower()
            if not seen[key] then
                seen[key] = true
                table.insert(ret, clone_match_with_trim(m, trimmed))
            end
        end
    end
end

local function build_trimmed_exec_matches(word)
    local ret = {}
    local seen = {}
    if word:find("\\", 1, true) or word:find("/", 1, true) then
        return ret, seen
    end

    if settings.get("exec.path") then
        for _, dir in ipairs(get_environment_paths()) do
            add_trimmed_matches(clink.filematchesexact(dir..word.."*.exe"), ret, seen)
        end
    end

    if settings.get("exec.cwd") then
        add_trimmed_matches(clink.filematchesexact(word.."*.exe"), ret, seen)
    end

    return ret, seen
end

local contributor = clink.generator(23)
function contributor:generate(line_state, match_builder)
    if not settings.get("rtpax.trim_exe") then
        return false
    end

    local wc = line_state:getwordcount()
    local cwi = line_state:getcommandwordindex()
    -- Different Clink builds/reporting paths can differ by one in index base.
    if (wc ~= cwi) and (wc ~= (cwi + 1)) then
        return false
    end

    local word = get_current_word(line_state)
    local added, seen_trimmed = build_trimmed_exec_matches(word)
    for _, m in ipairs(added) do
        match_builder:addmatch(m)
    end

    local function filter_out_original_exe(matches)
        if #added == 0 then
            return matches
        end

        local out = {}
        for _, m in ipairs(matches) do
            local drop = false
            if type(m) == "table" then
                local key = m.match and get_trim_key_for_match(m.match) or nil
                local dkey = (not key and type(m.display) == "string") and get_trim_key_for_match(m.display) or nil
                if (key and seen_trimmed[key]) or (dkey and seen_trimmed[dkey]) then
                    drop = true
                end
            end
            if not drop then
                table.insert(out, m)
            end
        end
        return out
    end

    -- Newer filtering API.
    clink.onfiltermatches(function(matches)
        return filter_out_original_exe(matches)
    end)

    -- Compatibility path used by some completion/filtering modes.
    clink.match_display_filter = function(matches)
        return filter_out_original_exe(matches)
    end

    -- Additional compatibility path for display filtering callbacks.
    clink.ondisplaymatches(function(matches)
        return filter_out_original_exe(matches)
    end)

    return false
end

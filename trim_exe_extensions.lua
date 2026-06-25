settings.add("rtpax.trim_exe", true, "Hide .exe extensions for commands")
settings.add("rtpax.trim_exe.debug", false, "Debug logging for trim_exe_extensions.lua")

local function dprint(...)
    if not settings.get("rtpax.trim_exe.debug") then
        return
    end
    local parts = { "[trim_exe]" }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
end

local function sample_match_strings(matches, max_items)
    local out = {}
    local n = 0
    for _, m in ipairs(matches or {}) do
        local s = nil
        if type(m) == "table" then
            s = m.match or m.display
        elseif type(m) == "string" then
            s = m
        end
        if s then
            n = n + 1
            out[#out + 1] = s
            if n >= max_items then
                break
            end
        end
    end
    return table.concat(out, " | ")
end

local function table_to_string(t)
    if type(t) ~= "table" then
        return tostring(t)
    end

    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local parts = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        local vt = type(v)
        if vt == "string" then
            parts[#parts + 1] = tostring(k).."='"..v.."'"
        elseif vt == "number" or vt == "boolean" or vt == "nil" then
            parts[#parts + 1] = tostring(k).."="..tostring(v)
        else
            parts[#parts + 1] = tostring(k).."=<"..vt..":"..tostring(v)..">"
        end
    end
    return "{"..table.concat(parts, ", ").."}"
end

local function dprint_match_tables(label, matches)
    if not settings.get("rtpax.trim_exe.debug") then
        return
    end
    dprint(label, "count", #(matches or {}))
    local limit = math.min(#(matches or {}), 4)
    for i = 1, limit do
        local m = matches[i]
        dprint(label, "["..i.."]", table_to_string(m))
    end
    if #(matches or {}) > limit then
        dprint(label, "...", (#(matches or {}) - limit), "more")
    end
end

local function should_trim_exe(str)
    return #str >= 5
       and str:sub(-4):lower() == ".exe"
       and not str:find("\\", 1, true)
       and not str:find("/", 1, true)
end

local function trim_exe(str)
    return str:sub(1, -5)
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

    local name = str:match("[^/\\]*[/\\]?$") or str
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
        local tail = before:match("[^ \t\r\n\"']+$") or ""
        word = tail
        if #word > 0 then
            dprint("word fallback", "line tail", word)
        end
    end
    return word
end

local function build_trimmed_exec_matches(word)
    local ret = {}
    local seen = {}

    dprint("build", "word", word)

    if word:find("\\", 1, true) or word:find("/", 1, true) then
        dprint("build", "skip path-like word")
        return ret, seen
    end

    local paths = {}
    if settings.get("exec.path") then
        paths = get_environment_paths()
    end
    dprint("build", "exec.path", settings.get("exec.path"), "exec.cwd", settings.get("exec.cwd"), "path_count", #paths)

    local from_path_added = 0
    for _, dir in ipairs(paths) do
        local pattern = dir..word.."*.exe"
        local this_dir_added = 0
        for _, m in ipairs(clink.filematchesexact(pattern)) do
            local name = m.match and (m.match:match("[^/\\]*[/\\]?$") or m.match)
            if name and should_trim_exe(name) then
                local trimmed = trim_exe(name)
                local key = trimmed:lower()
                if not seen[key] then
                    seen[key] = true
                    table.insert(ret, clone_match_with_trim(m, trimmed))
                    this_dir_added = this_dir_added + 1
                    from_path_added = from_path_added + 1
                end
            end
        end
        if this_dir_added > 0 then
            dprint("build", "path dir added", this_dir_added, "dir", dir)
        end
    end

    local from_cwd_added = 0
    if settings.get("exec.cwd") then
        local pattern = word.."*.exe"
        for _, m in ipairs(clink.filematchesexact(pattern)) do
            local name = m.match
            if name and should_trim_exe(name) then
                local trimmed = trim_exe(name)
                local key = trimmed:lower()
                if not seen[key] then
                    seen[key] = true
                    table.insert(ret, clone_match_with_trim(m, trimmed))
                    from_cwd_added = from_cwd_added + 1
                end
            end
        end
    end

    dprint("build", "from_path", from_path_added, "from_cwd", from_cwd_added, "total", #ret)
    dprint("build", "sample", sample_match_strings(ret, 8))

    return ret, seen
end

local contributor = clink.generator(23)
function contributor:generate(line_state, match_builder)
    if not settings.get("rtpax.trim_exe") then
        return false
    end

    local word = get_current_word(line_state)
    dprint("generate", "line", line_state:getline())
    dprint("generate", "word", word, "wordcount", line_state:getwordcount(), "commandwordindex", line_state:getcommandwordindex())

    local wc = line_state:getwordcount()
    local cwi = line_state:getcommandwordindex()
    -- Different Clink builds/reporting paths can differ by one in index base.
    local is_command_word = (wc == cwi) or (wc == (cwi + 1))
    if not is_command_word then
        dprint("not command word")
        return false
    end

    dprint("is command word", "word", word, "wordcount", line_state:getwordcount(), "commandwordindex", line_state:getcommandwordindex())

    local added, seen_trimmed = build_trimmed_exec_matches(word)
    for _, m in ipairs(added) do
        match_builder:addmatch(m)
    end
    dprint("word", word, "added", #added, "sample", sample_match_strings(added, 8))
    dprint_match_tables("added_tables", added)

    local function filter_out_original_exe(matches, source)
        dprint(source, "input", #matches, "added", #added)
        dprint(source, "input sample", sample_match_strings(matches, 8))
        dprint_match_tables(source.."_input_tables", matches)
        if #added == 0 then
            return matches
        end
        local out = {}
        local removed = 0
        for _, m in ipairs(matches) do
            local drop = false
            if type(m) == "table" then
                local key = m.match and get_trim_key_for_match(m.match) or nil
                local dkey = (not key and type(m.display) == "string") and get_trim_key_for_match(m.display) or nil
                if (key and seen_trimmed[key]) or (dkey and seen_trimmed[dkey]) then
                    drop = true
                    removed = removed + 1
                end
            end
            if not drop then
                table.insert(out, m)
            end
        end
        dprint(source, "removed exe", removed, "output", #out)
        dprint(source, "output sample", sample_match_strings(out, 8))
        dprint_match_tables(source.."_output_tables", out)
        return out
    end

    -- Newer filtering API.
    clink.onfiltermatches(function(matches)
        return filter_out_original_exe(matches, "onfiltermatches")
    end)

    -- Compatibility path used by some completion/filtering modes.
    clink.match_display_filter = function(matches)
        return filter_out_original_exe(matches, "match_display_filter")
    end

    -- Additional compatibility path for display filtering callbacks.
    clink.ondisplaymatches(function(matches)
        return filter_out_original_exe(matches, "ondisplaymatches")
    end)

    dprint("callbacks", "registered")

    return false
end

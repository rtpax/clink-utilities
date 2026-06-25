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

local function should_trim_exe(str)
    return #str >= 5
       and str:sub(-4):lower() == ".exe"
       and not str:find("\\", 1, true)
       and not str:find("/", 1, true)
end

local function trim_exe(str)
    return str:sub(1, -5)
end

local function clone_match_with_trim(m, trimmed)
    local c = {}
    for k, v in pairs(m) do
        c[k] = v
    end
    c.match = trimmed
    if type(c.display) == "string" and should_trim_exe(c.display) then
        c.display = trim_exe(c.display)
    end
    return c
end

local function get_environment_paths()
    local paths = (os.getenv("path") or ""):explode(";")
    for i = 1, #paths, 1 do
        paths[i] = paths[i].."\\"
    end
    return paths
end

local function build_trimmed_exec_matches(line_state)
    local ret = {}
    local seen = {}

    local word = line_state:getendword()
    if word:find("\\", 1, true) or word:find("/", 1, true) then
        return ret, seen
    end

    local paths = {}
    if settings.get("exec.path") then
        paths = get_environment_paths()
    end

    for _, dir in ipairs(paths) do
        local pattern = dir..word.."*.exe"
        for _, m in ipairs(clink.filematchesexact(pattern)) do
            local name = m.match and (m.match:match("[^/\\]*[/\\]?$") or m.match)
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
                end
            end
        end
    end

    return ret, seen
end

local contributor = clink.generator(23)
function contributor:generate(line_state, match_builder)
    if not settings.get("rtpax.trim_exe") then
        return false
    end

    dprint("generate", line_state:getendword(), "wordcount", line_state:getwordcount(), "commandwordindex", line_state:getcommandwordindex())

    local wc = line_state:getwordcount()
    local cwi = line_state:getcommandwordindex()
    -- Different Clink builds/reporting paths can differ by one in index base.
    local is_command_word = (wc == cwi) or (wc == (cwi + 1))
    if not is_command_word then
        dprint("not command word")
        return false
    end

    dprint("is command word", line_state:getendword(), "wordcount", line_state:getwordcount(), "commandwordindex", line_state:getcommandwordindex())

    local added, seen_trimmed = build_trimmed_exec_matches(line_state)
    for _, m in ipairs(added) do
        match_builder:addmatch(m)
    end
    dprint("word", line_state:getendword(), "added", #added)

    -- onfiltermatches can remove entries but cannot add entries.
    clink.onfiltermatches(function(matches)
        if #added == 0 then
            return
        end
        local out = {}
        local removed = 0
        for _, m in ipairs(matches) do
            local drop = false
            if type(m) == "table" and m.match and should_trim_exe(m.match) then
                local key = trim_exe(m.match):lower()
                if seen_trimmed[key] then
                    drop = true
                    removed = removed + 1
                end
            end
            if not drop then
                table.insert(out, m)
            end
        end
        dprint("removed exe", removed)
        return out
    end)

    return false
end

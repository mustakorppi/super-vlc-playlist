-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright and licensing scope: see COPYRIGHT.md in the project root.
-- Linux VLC 3. Paths are injected by install.py.
local VERSION, BUILD_DATE = 'development', 'unreleased'
-- @CONFIG@
local dialog, status, title_input, pattern_list, duration_input, unknown, result_list
local status_text, details_text = '', ''
local fields, source, results, patterns = {}, {}, {}, {}
local original_order = {}
local playlist_loaded = false
local keys = {'artist', 'album', 'genre'}
local pending, sequence = nil, 0
local preset_directory_input, export_directory_input, export_name_input
local preset_name_input, preset_list, preset_names
local save_view, save_payload, save_name

function descriptor()
    return {title='Super Playlist', version=VERSION, author='Super Playlist',
        shortdesc='Super Playlist',
        description='Wildcard titles, multiple genres, albums and artists, and duration ranges.',
        capabilities={'menu'}}
end

local function html(s)
    return tostring(s):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
end
local function render_status()
    -- A scrollable HTML widget keeps content out of the layout's size hint.
    -- Labels grow with long paths, error messages, and multiline metadata.
    if status then
        status:set_text('<b>' .. html(status_text):gsub('\n', '<br>') .. '</b><hr>' .. details_text)
    end
end
local function message(s)
    status_text = tostring(s)
    render_status()
end
local function set_details(text)
    details_text = text
    render_status()
end
local function encode(s)
    return (tostring(s):gsub('([^%w%-%._~])', function(c) return string.format('%%%02X', c:byte()) end))
end
local function decode(s) return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h,16)) end)) end
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function line(values)
    local out = {}
    for i, value in ipairs(values) do out[i] = encode(value) end
    return table.concat(out, '\t') .. '\n'
end
local function split(s)
    local values = {}
    for value in (s .. '\t'):gmatch('(.-)\t') do table.insert(values, decode(value)) end
    return values
end
local function clock(value)
    if not value or value < 0 then return '?' end
    value = math.floor(value)
    return string.format('%d:%02d:%02d', math.floor(value/3600), math.floor(value/60)%60, value%60)
end
local function busy()
    if pending then message('Working. Click Check status, or Cancel.'); return true end
    return false
end
local function serialize(items)
    local data = {}
    for _, item in ipairs(items) do
        table.insert(data, line({'I', item.id, item.uri, item.title, item.duration}))
        for _, key in ipairs(keys) do
            for _, value in ipairs(item[key]) do table.insert(data, line({'V', item.id, key, value})) end
        end
    end
    return table.concat(data)
end
local function show_results(items)
    results = items
    result_list:clear()
    set_details('Select a result and click Details to see its metadata and path.')
    local total, missing = 0, 0
    for i, item in ipairs(items) do
        local row = clock(item.duration) .. '  ' .. item.title
        for _, key in ipairs(keys) do
            local values = table.concat(item[key], ', ')
            row = row .. ' | ' .. key:sub(1,1):upper() .. key:sub(2) .. ': ' ..
                (values ~= '' and values or '(Unknown / missing)')
        end
        result_list:add_value(row:gsub('[\r\n\t]', ' '), i)
        if item.duration >= 0 then total = total + item.duration else missing = missing + 1 end
    end
    message(#items .. ' / ' .. #source .. ' items. Known duration: ' .. clock(total) ..
        (missing > 0 and ('; ' .. missing .. ' unknown.') or '.'))
end
local function choices(only_key)
    for _, key in ipairs(keys) do
      if not only_key or only_key == key then
        local found, values = {}, {}
        for _, item in ipairs(source) do
            if #item[key] == 0 then found[''] = true end
            for _, value in ipairs(item[key]) do found[value] = true end
        end
        local available = {}
        for value in pairs(found) do available[value] = true end
        for value in pairs(fields[key].active) do found[value] = true end
        for value in pairs(found) do table.insert(values, value) end
        table.sort(values)
        fields[key].values = values
        fields[key].list:clear()
        for i, value in ipairs(values) do
            local label = value == '' and '(Unknown / missing)' or value
            if fields[key].active[value] then
                label = '[active] ' .. label .. (not available[value] and ' [not in playlist]' or '')
            end
            fields[key].list:add_value(label, i)
        end
      end
    end
end

local function refresh_preset_names(names, preferred)
    preferred = preferred or (preset_names and preset_names[preset_list:get_value()])
    preset_names = names
    preset_list:clear()
    local chosen
    for id, name in ipairs(names) do if name == preferred then chosen = id end end
    if chosen then preset_list:add_value(names[chosen], chosen)
    else preset_list:add_value('Choose a preset', 0) end
    for id, name in ipairs(names) do
        if id ~= chosen then preset_list:add_value(name, id) end
    end
end

local function restore_filters(state)
    title_input:set_text(state.title_input)
    patterns = state.patterns
    pattern_list:clear()
    for id, value in ipairs(patterns) do pattern_list:add_value(value, id) end
    duration_input:set_text(state.ranges)
    unknown:set_checked(state.unknown)
    for _, key in ipairs(keys) do
        fields[key].active = state.selected[key]
        fields[key].all:set_checked(state.all[key] or false)
    end
    choices()
end
local function clean(job)
    for _, name in ipairs({'request.txt', 'result.txt', 'progress.txt', 'worker.log', 'cancel'}) do
        os.remove(job .. '/' .. name)
    end
    os.remove(job)
end
local function launch(mode, items, extra)
    if busy() then return end
    sequence = sequence + 1
    local job = SUPPORT_DIR .. '/jobs/' .. os.time() .. '-' .. math.random(100000,999999) .. '-' .. sequence
    if vlc.io.mkdir(job, '0700') ~= 0 then message('Cannot create helper job directory.'); return end
    local file, err = io.open(job .. '/request.txt', 'wb')
    if not file then message(err); clean(job); return end
    local ok = file:write(line({'M', mode}), serialize(items), extra or '')
    local closed = file:close()
    if not ok or not closed then message('Cannot write helper request.'); clean(job); return end
    local command = quote(PYTHON) .. ' ' .. quote(SUPPORT_DIR .. '/run_worker.py') .. ' ' .. quote(job) ..
        ' >' .. quote(job .. '/worker.log') .. ' 2>&1 &'
    local code = os.execute(command)
    if code ~= 0 and code ~= true then message('Cannot launch Python helper.'); clean(job); return end
    pending = {job=job, mode=mode}
    if mode == 'scan' or mode == 'filter' then show_results({}) end
    message('Working. Click Check status shortly. Filter edits apply on the next Apply filters.')
end

function check_status()
    if not pending then message('No job running. Load playlist or Apply filters.'); return end
    local file = io.open(pending.job .. '/result.txt', 'rb')
    if not file then
        local progress = io.open(pending.job .. '/progress.txt', 'rb')
        if progress then message(progress:read('*a') .. '. Click Check status again.'); progress:close()
        else message('Waiting for helper. Click Check status again; if it never completes, check ' .. pending.job .. '/worker.log') end
        return
    end
    local items, by_id, warnings, error_message, complete = {}, {}, {}, nil, false
    local preset_directory, export_directory
    local names, loaded_name, saved_name, existing_name = {}, nil, nil, nil
    local state = {title_input='', patterns={}, ranges='', unknown=false,
        selected={artist={}, album={}, genre={}}, all={}}
    for text in file:lines() do
        local row = split(text)
        if row[1] == 'I' then
            local item = {id=row[2], uri=row[3], title=row[4], duration=tonumber(row[5]) or -1,
                genre={}, album={}, artist={}}
            table.insert(items, item); by_id[item.id] = item
        elseif row[1] == 'V' and by_id[row[2]] then
            table.insert(by_id[row[2]][row[3]], row[4])
        elseif row[1] == 'P' then preset_directory = row[2]
        elseif row[1] == 'X' then export_directory = row[2]
        elseif row[1] == 'N' then table.insert(names, row[2])
        elseif row[1] == 'L' then loaded_name = row[2]
        elseif row[1] == 'S' then saved_name = row[2]
        elseif row[1] == 'EXISTS' then existing_name = row[2]
        elseif row[1] == 'E' then state.title_input = row[2]
        elseif row[1] == 'T' then table.insert(state.patterns, row[2])
        elseif row[1] == 'D' then state.ranges = row[2]
        elseif row[1] == 'U' then state.unknown = true
        elseif row[1] == 'F' then state.selected[row[2]][row[3]] = true
        elseif row[1] == 'A' then state.all[row[2]] = true
        elseif row[1] == 'W' then table.insert(warnings, row[2])
        elseif row[1] == 'ERROR' then error_message = row[2]
        elseif row[1] == 'OK' then complete = true end
    end
    file:close()
    local finished = pending
    pending = nil
    clean(finished.job)
    if error_message or not complete then message(error_message or 'Incomplete helper response.'); return end
    if finished.mode == 'export' then
        return_to_playlist()
        message('Exported ' .. #results .. ' matches.')
        set_details('Saved playlist:<br>' .. html(export_directory))
        return
    end
    if finished.mode == 'preset_save' and existing_name then
        show_save_dialog(existing_name, true)
        return
    end
    if finished.mode == 'settings_load' or finished.mode == 'settings_save' then
        if not preset_directory then message('Incomplete settings response.'); return end
        preset_directory_input:set_text(preset_directory)
        export_directory_input:set_text(export_directory)
        if finished.mode == 'settings_save' then refresh_preset_names(names) end
        message(finished.mode == 'settings_save' and 'Folder saved.' or 'Edit a folder path and click its Save button to validate and save.')
        return
    end
    if finished.mode:match('^preset_') then
        if finished.mode == 'preset_save' then
            return_to_playlist(names, saved_name)
        else
            refresh_preset_names(names, loaded_name)
        end
        if finished.mode == 'preset_load' then
            if not loaded_name then message('Incomplete preset response.'); return end
            restore_filters(state)
            apply_filters()
        elseif finished.mode == 'preset_save' then
            message('Saved preset "' .. (saved_name or '') .. '".')
        else
            message(#names .. ' preset(s) available. Choose a preset, then Load and apply preset.')
        end
        return
    end
    if finished.mode == 'scan' then
        playlist_loaded = true
        source, original_order = items, {}
        for i, item in ipairs(source) do original_order[item.id] = i end
        choices()
    end
    show_results(items)
    if #warnings > 0 then
        set_details(html(table.concat(warnings, '\n')):gsub('\n', '<br>'))
        message(#items .. ' items loaded; ' .. #warnings .. ' metadata warning(s). VLC values used where reading failed. See details.')
    end
end

function cancel_job()
    if not pending then return end
    if pending.mode == 'preset_save' or pending.mode == 'settings_save' then
        message('Saving. Click Check status to confirm the outcome.'); return
    end
    local file = io.open(pending.job .. '/cancel', 'wb')
    if file then file:close() end
    pending = nil -- Late results from this job can never replace the current snapshot.
    message('Cancelled. Load playlist or Apply filters to continue.')
end

local function capture(node, items)
    if not node then return end
    if node.children then
        for _, child in ipairs(node.children) do capture(child, items) end
    elseif node.path and node.path ~= '' then
        local meta = {}
        if node.item then
            local ok, data = pcall(function() return node.item:metas() end)
            if ok then meta = data or {} end
        end
        local item = {id=tostring(node.id), uri=node.path, title=meta.title or node.name or node.path,
            duration=node.duration or -1}
        for _, key in ipairs(keys) do item[key] = meta[key] and meta[key] ~= '' and {meta[key]} or {} end
        table.insert(items, item)
    end
end

local function clear_controls()
    title_input:set_text(''); patterns = {}; pattern_list:clear()
    duration_input:set_text(''); unknown:set_checked(false)
    for _, key in ipairs(keys) do
        fields[key].all:set_checked(false)
        fields[key].active = {}
    end
end

local function collect_automatically()
    -- Bound the wait so a slow scan or stalled helper cannot hold the dialog
    -- indefinitely. Longer jobs remain available through Check status.
    for attempt = 1, 21 do
        if not pending then return end
        local ready = io.open(pending.job .. '/result.txt', 'rb')
        if ready then ready:close(); check_status(); return end
        -- VLC 3 net.poll has no timeout argument: an empty descriptor table
        -- blocks indefinitely. Use Linux sleep's explicit, finite duration.
        if attempt < 21 then
            local code = os.execute('/bin/sleep 0.05')
            if code ~= 0 and code ~= true then break end
        end
    end
    message('Still working. Click Check status shortly, or Cancel.')
end

function show_settings_controls()
    if not preset_directory_input then
        dialog:add_label('Preset folder (absolute path or ~/folder; created when saved)', 1, 25, 3, 1)
        preset_directory_input = dialog:add_text_input('', 1, 26, 2, 1)
        dialog:add_button('Save folder', save_preset_directory, 3, 26)
        dialog:add_label('Export folder (absolute path or ~/folder; created when saved)', 1, 27, 3, 1)
        export_directory_input = dialog:add_text_input('', 1, 28, 2, 1)
        dialog:add_button('Save export folder', save_export_directory, 3, 28)
    end
end

function open_settings()
    if busy() then return end
    show_settings_controls()
    launch('settings_load', {}, line({'H', USER_HOME}))
    collect_automatically()
end

function save_preset_directory()
    if busy() or not preset_directory_input then return end
    launch('settings_save', {}, line({'H', USER_HOME}) .. line({'P', preset_directory_input:get_text()}))
    collect_automatically()
end

function save_export_directory()
    if busy() or not export_directory_input then return end
    launch('settings_save', {}, line({'H', USER_HOME}) .. line({'X', export_directory_input:get_text()}))
    collect_automatically()
end

function load_playlist()
    if busy() then return end
    playlist_loaded = false
    local items = {}
    capture(vlc.playlist.get('playlist'), items)
    clear_controls()
    source = {}; choices()
    launch('scan', items)
    collect_automatically()
end

function add_pattern()
    if busy() then return end
    local value = title_input:get_text()
    if value:match('^%s*$') then return end
    table.insert(patterns, value)
    pattern_list:add_value(value, #patterns)
    title_input:set_text('')
end

function remove_patterns()
    if busy() then return end
    local selected, kept = pattern_list:get_selection(), {}
    for i, value in ipairs(patterns) do if not selected[i] then table.insert(kept, value) end end
    patterns = kept; pattern_list:clear()
    for i, value in ipairs(patterns) do pattern_list:add_value(value, i) end
end

local function filter_state()
    local extra = {}
    for _, value in ipairs(patterns) do table.insert(extra, line({'T', value})) end
    table.insert(extra, line({'E', title_input:get_text()}))
    table.insert(extra, line({'D', duration_input:get_text()}))
    if unknown:get_checked() then table.insert(extra, line({'U'})) end
    for _, key in ipairs(keys) do
        local selected = {}
        for value in pairs(fields[key].active) do selected[value] = true end
        for id in pairs(fields[key].list:get_selection()) do
            selected[fields[key].values[id]] = true
        end
        local values = {}
        for value in pairs(selected) do table.insert(values, value) end
        table.sort(values)
        for _, value in ipairs(values) do table.insert(extra, line({'F', key, value})) end
        if fields[key].all:get_checked() then table.insert(extra, line({'A', key})) end
    end
    return table.concat(extra)
end

function remove_criteria(key)
    if busy() then return end
    for id in pairs(fields[key].list:get_selection()) do
        fields[key].active[fields[key].values[id]] = nil
    end
    choices(key)
    apply_filters()
end

function refresh_presets()
    if busy() then return end
    launch('preset_list', {}, line({'H', USER_HOME}))
    collect_automatically()
end

function show_save_dialog(name, confirm)
    dialog:delete()
    status, preset_name_input = nil, nil
    dialog = vlc.dialog(confirm and 'Replace preset?' or 'Save preset as')
    save_name = name
    if confirm then
        dialog:add_html('A preset named <b>' .. html(name) .. '</b> already exists. Replace it?', 1, 1, 3, 1, 440, 60)
        dialog:add_button('Replace preset', function() save_filter_preset(true) end, 1, 3)
        dialog:add_button('Change name', function()
            if not busy() then show_save_dialog(save_name, false) end
        end, 2, 3)
    else
        dialog:add_label('Preset name', 1, 1, 3, 1)
        preset_name_input = dialog:add_text_input(name or '', 1, 2, 3, 1)
        dialog:add_button('Save', function() save_filter_preset(false) end, 1, 3)
    end
    dialog:add_button('Cancel', cancel_save_preset, 3, 3)
    dialog:add_button('↻ Check status', check_status, 2, 4)
    status = dialog:add_html('', 1, 5, 3, 1, 440, 60)
    status_text, details_text = '', ''
end

local function capture_save_view()
    local state = {title_input=title_input:get_text(), patterns=patterns,
        ranges=duration_input:get_text(), unknown=unknown:get_checked(), selected={}, all={}}
    for _, key in ipairs(keys) do
        state.selected[key] = {}
        for value in pairs(fields[key].active) do state.selected[key][value] = true end
        for id in pairs(fields[key].list:get_selection()) do
            state.selected[key][fields[key].values[id]] = true
        end
        state.all[key] = fields[key].all:get_checked()
    end
    save_view = {filters=state, status=status_text, details=details_text,
        selected=preset_names[preset_list:get_value()],
        directory=preset_directory_input and preset_directory_input:get_text(),
        export_directory=export_directory_input and export_directory_input:get_text()}
end

function open_save_preset()
    if busy() then return end
    capture_save_view()
    save_payload = filter_state()
    show_save_dialog('', false)
end

function return_to_playlist(names, selected)
    local previous = save_view
    dialog:delete()
    status = nil
    build_main_dialog()
    show_results(results)
    restore_filters(previous.filters)
    refresh_preset_names(names or preset_names, selected or previous.selected)
    if previous.directory then
        show_settings_controls()
        preset_directory_input:set_text(previous.directory)
        export_directory_input:set_text(previous.export_directory)
    end
    status_text, details_text = previous.status, previous.details
    render_status()
    save_view, save_payload, save_name = nil, nil, nil
end

function cancel_save_preset()
    if busy() then return end
    return_to_playlist()
end

function save_filter_preset(replace)
    if busy() then return end
    if not save_view then return end
    local name = replace and save_name or preset_name_input:get_text()
    local extra = line({'H', USER_HOME}) .. line({'N', name}) .. save_payload
    if replace then extra = extra .. line({'R'}) end
    launch('preset_save', {}, extra)
    collect_automatically()
end

function load_filter_preset()
    if busy() then return end
    if not playlist_loaded then message('Load playlist first, then Load and apply preset.'); return end
    local name = preset_names[preset_list:get_value()]
    if not name then message('Choose a preset from the list first.'); return end
    launch('preset_load', {}, line({'H', USER_HOME}) .. line({'N', name}))
    collect_automatically()
end

function apply_filters()
    if busy() then return end
    launch('filter', source, filter_state())
    collect_automatically()
end

function reset_filters()
    if pending and pending.mode == 'filter' then cancel_job() end
    if busy() then return end
    clear_controls(); choices(); show_results(source)
end

local function shuffled_copy(items)
    -- Linux entropy is independent of activation time, file metadata, and
    -- math.random calls used for job/export names. Never fall back to a clock.
    local entropy = io.open('/dev/urandom', 'rb')
    if not entropy then return nil, 'Cannot access the system random source.' end
    local ok, shuffled = pcall(function()
        local function random_index(bound)
            local limit = 4294967296 - (4294967296 % bound)
            for attempt = 1, 128 do
                local bytes = entropy:read(4)
                if not bytes or #bytes ~= 4 then error('Cannot read the system random source.') end
                local a, b, c, d = bytes:byte(1, 4)
                local value = ((a * 256 + b) * 256 + c) * 256 + d
                -- Reject the remainder so every index has equal probability.
                if value < limit then return (value % bound) + 1 end
            end
            error('The system random source did not provide a usable value.')
        end
        for attempt = 1, 128 do
            local copy = {}
            for i, item in ipairs(items) do copy[i] = item end
            for i = #copy, 2, -1 do
                local j = random_index(i)
                copy[i], copy[j] = copy[j], copy[i]
            end
            -- Resample an unchanged permutation instead of biasing the shuffle
            -- with a forced swap. Compare entry identities, not titles/paths.
            for i, item in ipairs(copy) do
                if item.id ~= items[i].id then return copy end
            end
        end
        error('Could not generate a different order. Please try Shuffle again.')
    end)
    entropy:close()
    if not ok then return nil, tostring(shuffled) end
    return shuffled
end

function shuffle_results()
    if busy() then return end
    if #results < 2 then message('At least two matches are needed to shuffle.'); return end
    local shuffled, err = shuffled_copy(results)
    if not shuffled then message(err .. ' Order unchanged.'); return end
    local included = {}
    for _, item in ipairs(results) do included[item.id] = true end
    -- Change only matched slots in the snapshot. Subsequent filters retain
    -- this order; hidden items keep their positions and metadata.
    local next_item = 1
    for i, item in ipairs(source) do
        if included[item.id] then source[i] = shuffled[next_item]; next_item = next_item + 1 end
    end
    show_results(shuffled)
    message('Shuffled ' .. #results .. ' matches. Queue or export to use this order. Result selections cleared.')
end

function restore_order()
    if busy() then return end
    local function before(a, b) return original_order[a.id] < original_order[b.id] end
    table.sort(source, before)
    table.sort(results, before)
    show_results(results)
    message('Original loaded order restored. Filters retained; result selections cleared.')
end

local function selected_results(all)
    local selection, items = result_list:get_selection(), {}
    for i, item in ipairs(results) do if all or selection[i] then table.insert(items, item) end end
    return items
end

function show_details()
    if busy() then return end
    local items = selected_results(false)
    if #items == 0 then message('Select a result first.'); return end
    local item = items[1]
    local text = html(item.title) .. '<br>' .. html(item.uri) .. '<br>Duration: ' .. clock(item.duration)
    for _, key in ipairs(keys) do text = text .. '<br>' .. key .. ': ' .. html(table.concat(item[key], ', ')) end
    set_details(text)
end

local function playlist_entry(item)
    local entry = {path=item.uri, name=item.title, title=item.title, duration=item.duration}
    for _, key in ipairs(keys) do entry[key] = table.concat(item[key], ' ') end
    return entry
end

local function playlist_leaves(node, items)
    items = items or {}
    if node then
        if node.children then
            for _, child in ipairs(node.children) do playlist_leaves(child, items) end
        elseif node.id and node.path then
            table.insert(items, node)
        end
    end
    return items
end

function play_matches_instantly()
    local queued_start = queue_results(true)
    if not queued_start then return end
    local current = vlc.playlist.get(queued_start.id)
    if not current or current.path ~= queued_start.uri then
        message('The first queued item is no longer in VLC. Try Play matches instantly again.')
        return
    end
    local jump = vlc.playlist.gotoitem or vlc.playlist['goto']
    jump(queued_start.id)
    message('Playing queued matches from ' .. queued_start.title)
end

function queue_results(all)
    if busy() then return end
    local items = selected_results(all)
    if #items == 0 then message('No results selected.'); return end
    local previous = {}
    for _, item in ipairs(playlist_leaves(vlc.playlist.get('playlist'))) do previous[item.id] = true end
    local queued_start
    local count, first = 0, nil
    for _, item in ipairs(items) do
        local added = vlc.playlist.enqueue({playlist_entry(item)}) or 0
        count = count + added
        if added > 0 and not first then first = item end
    end
    if first then
        for _, item in ipairs(playlist_leaves(vlc.playlist.get('playlist'))) do
            if not previous[item.id] and item.path == first.uri then
                queued_start = {id=item.id, uri=item.path, title=first.title}
                break
            end
        end
    end
    message('Appended ' .. count .. ' items to VLC. The source snapshot is unchanged.' ..
        (queued_start and '' or ' Could not locate a newly queued item to play.'))
    return queued_start
end

function play_selected()
    if busy() then return end
    local items = selected_results(false)
    if #items ~= 1 then message('Select exactly one result to play. Use Queue selected for multiple items.'); return end
    local item = items[1]
    local current = vlc.playlist.get(tonumber(item.id))
    if current and current.path == item.uri then (vlc.playlist.gotoitem or vlc.playlist['goto'])(tonumber(item.id))
    else vlc.playlist.add({playlist_entry(item)}) end
    message('Playing ' .. item.title)
end

function export_matches()
    if busy() then return end
    if #results == 0 then message('No matches to export.'); return end
    capture_save_view()
    dialog:delete()
    dialog = vlc.dialog('Save playlist as')
    dialog:add_label('Playlist name (.m3u8 is added automatically)', 1, 1, 3, 1)
    export_name_input = dialog:add_text_input('', 1, 2, 3, 1)
    dialog:add_button('Save', save_export, 1, 3)
    dialog:add_button('Cancel', cancel_save_preset, 3, 3)
    dialog:add_button('↻ Check status', check_status, 2, 4)
    status = dialog:add_html('', 1, 5, 3, 1, 440, 80)
    status_text = 'Name your playlist, then click Save.'
    set_details('Saved in the export folder configured in Settings. Existing files are kept; use a new name.')
end

function save_export()
    if busy() or not save_view then return end
    launch('export', results, line({'H', USER_HOME}) .. line({'N', export_name_input:get_text()}))
    collect_automatically()
end

function show_filter_help()
    set_details('<b>Title search</b><br>Plain text matches anywhere in a title. ' ..
        '<b>*</b> matches any characters; <b>?</b> matches one. Added patterns match ANY.<br>' ..
        '<b>Metadata</b><br>Highlighted and [active] values apply. Use Ctrl/Shift to select several. ' ..
        'Selections within each field match ANY unless Require ALL selected is checked. ' ..
        'Different fields combine with AND.<br>' ..
        '<b>Duration</b><br>Use ranges such as 03:00-08:00; 12:00-. ' ..
        'Bounds are inclusive; leave blank for any duration.')
end

function build_main_dialog()
    preset_directory_input, export_directory_input = nil, nil
    dialog = vlc.dialog('Π Super Playlist')
    dialog:add_label('<b>Super Playlist</b> · Rediscover your playlist<br>' ..
        '<small>Click <b>Load playlist</b> to get started.<br>' ..
        'Click <b>Check status</b> to see progress or results.<br>' ..
        'Click <b>Reset filters</b> to return to all loaded items.<br>' ..
        'Your files will not be modified.</small>', 1, 1, 2, 1)
    dialog:add_label('<p align="right"><small>Version ' .. html(VERSION) ..
        '<br>Build date ' .. html(BUILD_DATE) .. '</small></p>', 3, 1, 1, 1)
    dialog:add_button('↓ Load playlist', load_playlist, 1, 2)
    dialog:add_button('↻ Check status', check_status, 2, 2)
    dialog:add_button('Cancel', cancel_job, 3, 2)
    dialog:add_label('<hr style="margin-top: 3px; margin-bottom: 3px;"><b>Filters</b> · Find your next mix', 1, 3, 3, 1)
    dialog:add_label('Title contains… (or use * and ?)', 1, 4, 3, 1)
    title_input = dialog:add_text_input('', 1, 5, 2, 1)
    dialog:add_button('+ Add title pattern', add_pattern, 3, 5)
    pattern_list = dialog:add_list(1, 6, 2, 1, 440, 50)
    dialog:add_button('Remove selected patterns', remove_patterns, 3, 6)
    for col, key in ipairs(keys) do
        dialog:add_label('<b>' .. key:sub(1,1):upper() .. key:sub(2) .. '</b>', col, 7)
        fields[key] = {list=dialog:add_list(col, 8, 1, 1, 220, 100), values={}, active={}}
        fields[key].all = dialog:add_check_box('Require ALL selected', false, col, 9)
        dialog:add_button('Remove selected ' .. key .. ' criteria', function() remove_criteria(key) end, col, 10)
    end
    dialog:add_label('Duration · e.g. 03:00-08:00; 12:00- (blank = any)', 1, 11, 3, 1)
    duration_input = dialog:add_text_input('', 1, 12, 2, 1)
    unknown = dialog:add_check_box('Include unknown duration', false, 3, 12)
    dialog:add_button('Apply filters', apply_filters, 1, 13)
    dialog:add_button('× Reset filters', reset_filters, 2, 13)
    dialog:add_button('Help', show_filter_help, 3, 13)
    dialog:add_label('Highlighted and [active] metadata values apply.', 1, 14, 3, 1)
    dialog:add_label('<hr style="margin-top: 3px; margin-bottom: 3px;"><b>Results</b> · Your next playlist starts here', 1, 15, 2, 1)
    dialog:add_button('Details', show_details, 3, 15)
    result_list = dialog:add_list(1, 16, 3, 1, 660, 160)
    dialog:add_button('▶ Play selected', play_selected, 1, 17)
    dialog:add_button('▶ Play matches instantly', play_matches_instantly, 2, 17, 2, 1)
    dialog:add_button('+ Queue selected', function() queue_results(false) end, 1, 18)
    dialog:add_button('+ Queue all matches', function() queue_results(true) end, 2, 18, 2, 1)
    dialog:add_button('⇄ Shuffle results', shuffle_results, 1, 19)
    dialog:add_button('Restore original order', restore_order, 2, 19)
    dialog:add_button('↑ Export matches', export_matches, 3, 19)
    dialog:add_label('<hr style="margin-top: 3px; margin-bottom: 3px;"><b>Filter presets</b> · Save a mix to revisit', 1, 20, 3, 1)
    preset_list = dialog:add_dropdown(1, 21, 2, 1)
    dialog:add_button('Load and apply preset', load_filter_preset, 3, 21)
    dialog:add_button('✓ Save preset as...', open_save_preset, 1, 22)
    dialog:add_button('☰ Refresh presets', refresh_presets, 2, 22)
    dialog:add_button('⚙ Settings', open_settings, 3, 22)
    dialog:add_label('<hr style="margin-top: 3px; margin-bottom: 3px;"><b>Status and details</b>', 1, 23, 3, 1)
    status = dialog:add_html('', 1, 24, 3, 1, 660, 100)
    status_text = 'Load your playlist to find your next mix.'
    set_details('Start with Load playlist, then explore by title, artist, album, genre, or duration. ' ..
        'Click Help for filter tips.')
end

function activate()
    playlist_loaded = false
    pending, save_view, save_payload, save_name = nil, nil, nil, nil
    source, results, patterns, fields = {}, {}, {}, {}
    original_order = {}
    math.randomseed(os.time())
    build_main_dialog()
    refresh_preset_names({})
    refresh_presets()
end

function menu()
    return {[1]='Show editor', [2]='Hide editor'}
end
function trigger_menu(id)
    if not dialog then return end
    if id == 1 then
        -- VLC 3 changes visibility without raising a covered window.
        -- Use separate Hide then Show actions to recall a covered editor.
        dialog:show()
    elseif id == 2 then
        dialog:hide()
    end
end

function deactivate()
    cancel_job()
    pending = nil
    if dialog then dialog:delete() end
    dialog, status = nil, nil
end
function close()
    if save_view then cancel_save_preset() else vlc.deactivate() end
end

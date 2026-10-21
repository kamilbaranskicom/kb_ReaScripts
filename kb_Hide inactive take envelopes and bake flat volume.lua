-- @description Hide inactive take envelopes and bake flat volume to item
-- @version 1.0
-- @author Kamil Barański (kamilbaranskicom) & AI
-- @changelog
--   + Initial release
-- @about
--   Skrypt dla REAPER sprawdzający koperty take (Take Envelopes) w zaznaczonych itemach:
--   - Jeśli na kopercie nic się nie dzieje (np. Take Volume na 0 dB lub brak punktów), ukrywa tę kopertę.
--   - Jeśli Take Volume jest na stałej wysokości innej niż 0 dB i item ma tylko jeden take,
--     wartość ta jest mnożona przez głośność itemu (Item Volume), a koperta jest resetowana i ukrywana.
--   - Jeśli koperta zawiera automatyzację (zmienne punkty, krzywe lub Automation Items), pozostaje nienaruszona.
--   - Opcjonalnie ukrywa także koperty Pan, Pitch, Mute, jeżeli są w pozycji neutralnej (brak zmian).

-- ============================================================================
-- KONFIGURACJA / SETTINGS
-- ============================================================================
local PROCESS_VOLUME_ENVELOPES = true    -- Obsługa Take Volume (ukrywanie przy 0dB, przenoszenie do Item Volume przy innej stałej wartości)
local PROCESS_OTHER_ENVELOPES  = true    -- Obsługa Pan / Pitch / Mute (ukrywanie, jeśli są neutralne i nic się w nich nie dzieje)
local ONLY_VISIBLE_ENVELOPES   = false   -- true: przetwarza tylko koperty obecnie widoczne na ekranie; false: czyści również ukryte
-- ============================================================================

local EPSILON = 0.0001 -- Margines błędu dla porównań zmiennoprzecinkowych (ok. 0.0008 dB)

-- Rozpoznanie typu koperty (z tagów chunka oraz nazwy)
local function identify_envelope(env)
    local ok_chunk, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    local _, env_name = reaper.GetEnvelopeName(env)
    
    local env_type = nil
    
    if ok_chunk and chunk then
        if chunk:match("^<VOLENV") or chunk:match("\n<VOLENV") then
            env_type = "VOLUME"
        elseif chunk:match("^<PANENV") or chunk:match("\n<PANENV") then
            env_type = "PAN"
        elseif chunk:match("^<PITCHENV") or chunk:match("\n<PITCHENV") then
            env_type = "PITCH"
        elseif chunk:match("^<MUTEENV") or chunk:match("\n<MUTEENV") then
            env_type = "MUTE"
        end
    end
    
    if not env_type and env_name then
        local lower = env_name:lower()
        if lower:find("volume") or lower:find("głośn") then
            env_type = "VOLUME"
        elseif lower:find("pan") or lower:find("panorama") then
            env_type = "PAN"
        elseif lower:find("pitch") or lower:find("wysoko") then
            env_type = "PITCH"
        elseif lower:find("mute") or lower:find("wycisz") then
            env_type = "MUTE"
        end
    end
    
    return env_type, chunk
end

-- Sprawdzenie, czy koperta jest obecnie widoczna w arrange view
local function is_chunk_visible(chunk)
    if not chunk then return true end
    local vis = chunk:match("\nVIS%s+(%d+)") or chunk:match("^VIS%s+(%d+)")
    if vis then
        return tonumber(vis) == 1
    end
    return true -- domyślnie widoczna w REAPER, jeśli brak wpisu VIS
end

-- Ukrycie koperty (VIS 0) oraz opcjonalne usunięcie punktów
local function hide_and_clear_envelope(env, clear_points)
    if clear_points then
        reaper.DeleteEnvelopePointRange(env, -10000000, 10000000)
    end
    
    local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    if ok and chunk then
        if clear_points then
            chunk = chunk:gsub("\nPT [^\n]*", "")
        end
        
        local replaced = false
        local new_chunk, count = chunk:gsub("(\nVIS%s+)%d+", "%10", 1)
        if count > 0 then replaced = true; chunk = new_chunk end
        
        if not replaced then
            new_chunk, count = chunk:gsub("(^VIS%s+)%d+", "%10", 1)
            if count > 0 then replaced = true; chunk = new_chunk end
        end
        
        if not replaced then
            chunk = chunk:gsub("^(<[^\n]+\n)", "%1VIS 0 1 1\n", 1)
        end
        
        reaper.SetEnvelopeStateChunk(env, chunk, false)
    end
    
    if clear_points then
        reaper.Envelope_SortPoints(env)
    end
end

-- Przetworzenie koperty głośności (Volume)
local function process_volume_envelope(item, take, env, chunk, num_takes)
    -- 1. Czy istnieją Automation Items? Jeśli tak, automatyzacja jest aktywna.
    local num_ai = reaper.CountAutomationItems(env)
    if num_ai > 0 then
        return false, false
    end
    
    local num_pts = reaper.CountEnvelopePoints(env)
    
    -- Przypadek 1: Koperta bez żadnych punktów -> domyślne 0 dB (1.0)
    if num_pts == 0 then
        hide_and_clear_envelope(env, false)
        return true, false
    end
    
    -- Przypadek 2: Koperta ma punkty -> sprawdzamy, czy wszystkie mają tę samą wartość
    local scale_mode = reaper.GetEnvelopeScalingMode(env)
    local _, _, first_raw = reaper.GetEnvelopePoint(env, 0)
    local first_linear = reaper.ScaleFromEnvelopeMode(scale_mode, first_raw)
    
    local is_flat = true
    for p = 1, num_pts - 1 do
        local _, _, pt_raw = reaper.GetEnvelopePoint(env, p)
        local pt_linear = reaper.ScaleFromEnvelopeMode(scale_mode, pt_raw)
        if math.abs(pt_linear - first_linear) > EPSILON then
            is_flat = false
            break
        end
    end
    
    -- Jeśli wartości punktów się różnią, to na kopercie dzieje się automatyzacja - zostawiamy!
    if not is_flat then
        return false, false
    end
    
    -- Sprawdzamy, czy stały poziom to 0 dB
    local is_zero_db = math.abs(first_linear - 1.0) < EPSILON
    
    if is_zero_db then
        -- Cała koperta jest płaska na 0 dB -> nic się nie dzieje, czyścimy punkty i ukrywamy
        hide_and_clear_envelope(env, true)
        return true, false
    else
        -- Cała koperta jest na stałym poziomie różnym od 0 dB
        if num_takes == 1 then
            -- Brak innych take'ów w itemie: przenosimy poziom do Item Volume i ukrywamy
            local cur_item_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
            local new_item_vol = cur_item_vol * first_linear
            reaper.SetMediaItemInfo_Value(item, "D_VOL", new_item_vol)
            reaper.UpdateItemInProject(item)
            
            -- Czyścimy punkty (by nie dublować poziomu głośności) i ukrywamy
            hide_and_clear_envelope(env, true)
            return true, true
        else
            -- W itemie są inne take'i: zmiana item volume popsułaby pozostałe take'i,
            -- a ta koperta ma aktywną inną głośność dla tego konkretnego take'a, więc zostawiamy.
            return false, false
        end
    end
end

-- Przetworzenie pozostałych kopert (Pan, Pitch, Mute)
local function process_other_envelope(env, env_type)
    local num_ai = reaper.CountAutomationItems(env)
    if num_ai > 0 then
        return false
    end
    
    local num_pts = reaper.CountEnvelopePoints(env)
    if num_pts == 0 then
        hide_and_clear_envelope(env, false)
        return true
    end
    
    -- Sprawdzamy czy wszystkie punkty są w pozycji neutralnej (0.0: środek, 0 st, unmuted)
    local is_flat_neutral = true
    for p = 0, num_pts - 1 do
        local _, _, pt_raw = reaper.GetEnvelopePoint(env, p)
        if math.abs(pt_raw) > EPSILON then
            is_flat_neutral = false
            break
        end
    end
    
    if is_flat_neutral then
        hide_and_clear_envelope(env, true)
        return true
    end
    
    return false
end

-- Funkcja główna
local function main()
    local num_items = reaper.CountSelectedMediaItems(0)
    if num_items == 0 then
        return
    end
    
    local total_hidden = 0
    local total_baked = 0
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local num_takes = reaper.CountTakes(item)
        
        for t = 0, num_takes - 1 do
            local take = reaper.GetMediaItemTake(item, t)
            if take then
                local num_envs = reaper.CountTakeEnvelopes(take)
                for e = num_envs - 1, 0, -1 do
                    local env = reaper.GetTakeEnvelope(take, e)
                    if env then
                        local env_type, chunk = identify_envelope(env)
                        local is_vis = is_chunk_visible(chunk)
                        
                        if not ONLY_VISIBLE_ENVELOPES or is_vis then
                            if env_type == "VOLUME" and PROCESS_VOLUME_ENVELOPES then
                                local hidden, vol_changed = process_volume_envelope(item, take, env, chunk, num_takes)
                                if hidden then total_hidden = total_hidden + 1 end
                                if vol_changed then total_baked = total_baked + 1 end
                            elseif env_type and PROCESS_OTHER_ENVELOPES then
                                local hidden = process_other_envelope(env, env_type)
                                if hidden then total_hidden = total_hidden + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    
    if total_hidden > 0 or total_baked > 0 then
        local undo_str = "Clean up take envelopes"
        if total_baked > 0 and total_hidden > 0 then
            undo_str = string.format("Hide %d inactive take envelope(s) and bake volume on %d item(s)", total_hidden, total_baked)
        elseif total_hidden > 0 then
            undo_str = string.format("Hide %d inactive take envelope(s)", total_hidden)
        end
        reaper.Undo_EndBlock(undo_str, -1)
    else
        reaper.Undo_EndBlock("", 0)
    end
end

main()

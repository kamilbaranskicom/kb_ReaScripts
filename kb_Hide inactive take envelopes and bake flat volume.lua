-- @description Hide inactive take envelopes and bake flat volume to item
-- @version 1.0
-- @author Kamil Barański (kamilbaranskicom) & AI
-- @changelog
--   + Initial release
-- @about
--   REAPER script that checks Take Envelopes on selected items:
--   - If the envelope is inactive/idle (e.g., Take Volume at 0 dB or no points), hides the envelope.
--   - If Take Volume is at a flat level other than 0 dB and the item has only one take,
--     the value is multiplied into the Item Volume, and the envelope is cleared and hidden.
--   - If the envelope contains automation (variable points, curves, or Automation Items), it remains untouched.
--   - Optionally hides Pan, Pitch, and Mute envelopes if they are in their neutral state (no changes).

-- ============================================================================
-- SETTINGS
-- ============================================================================
local PROCESS_VOLUME_ENVELOPES = true    -- Process Take Volume (hide at 0 dB, bake into Item Volume if flat at another level)
local PROCESS_OTHER_ENVELOPES  = true    -- Process Pan / Pitch / Mute (hide if neutral with no changes)
local ONLY_VISIBLE_ENVELOPES   = false   -- true: process only envelopes currently visible on screen; false: also clean hidden ones
-- ============================================================================

local EPSILON = 0.0001 -- Floating-point comparison tolerance (~0.0008 dB)

-- Identify envelope type (from chunk tags and envelope name)
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

-- Check if envelope is currently visible in arrange view
local function is_chunk_visible(chunk)
    if not chunk then return true end
    local vis = chunk:match("\nVIS%s+(%d+)") or chunk:match("^VIS%s+(%d+)")
    if vis then
        return tonumber(vis) == 1
    end
    return true -- default to visible in REAPER if VIS tag is missing
end

-- Hide envelope (VIS 0) and optionally clear points
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

-- Process volume envelope
local function process_volume_envelope(item, take, env, chunk, num_takes)
    -- 1. Do Automation Items exist? If so, automation is active.
    local num_ai = reaper.CountAutomationItems(env)
    if num_ai > 0 then
        return false, false
    end
    
    local num_pts = reaper.CountEnvelopePoints(env)
    
    -- Case 1: Envelope without points -> default 0 dB (1.0)
    if num_pts == 0 then
        hide_and_clear_envelope(env, false)
        return true, false
    end
    
    -- Case 2: Envelope has points -> check if all points have the same value
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
    
    -- If point values differ, active automation is present - leave untouched!
    if not is_flat then
        return false, false
    end
    
    -- Check if flat level is 0 dB
    local is_zero_db = math.abs(first_linear - 1.0) < EPSILON
    
    if is_zero_db then
        -- Entire envelope is flat at 0 dB -> no changes, clear points and hide
        hide_and_clear_envelope(env, true)
        return true, false
    else
        -- Entire envelope is flat at a level other than 0 dB
        if num_takes == 1 then
            -- Single-take item: bake level into Item Volume and hide
            local cur_item_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
            local new_item_vol = cur_item_vol * first_linear
            reaper.SetMediaItemInfo_Value(item, "D_VOL", new_item_vol)
            reaper.UpdateItemInProject(item)
            
            -- Clear points (to avoid doubling gain) and hide
            hide_and_clear_envelope(env, true)
            return true, true
        else
            -- Multiple takes present: modifying Item Volume would alter other takes,
            -- and this envelope has a custom take volume offset, so keep it intact.
            return false, false
        end
    end
end

-- Process other envelopes (Pan, Pitch, Mute)
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
    
    -- Check if all points are at neutral value (0.0: center, 0 st, unmuted)
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

-- Main function
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

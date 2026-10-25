-- @description Generate loudness envelope for selected track (Album Dynamics)
-- @author Kamil Barański (kamilbaranskicom)
-- @version 2.0
-- @about
--   Custom interactive GUI tool for album loudness analysis and automation generation.
--   Features dedicated Mastering Vertical Zoom (-24..-6 dB), selectable ITU-R BS.1770
--   metrics (LUFS-S, LUFS-M, RMS), a one-click [REGENERATE ENVELOPES] button,
--   live progress display, peak markers, and a comprehensive dynamics report.
-- @changelog
--   + v2.0: Replaced system input dialog with custom dark-themed GUI control panel
--   + v2.0: Interactive [REGENERATE ENVELOPES] button directly inside the window
--   + v2.0: Interactive radio buttons for scale zoom and checkboxes for metrics
--   + v2.0: Window can stay open while adjusting audio; remembers all preferences

local STEP_SEC      = 0.20        -- 5 points per second (optimal smoothness & resolution)
local WIN_S_SEC     = 3.00        -- ITU-R BS.1770 short-term window (3 seconds)
local WIN_M_SEC     = 0.40        -- ITU-R BS.1770 momentary window (400 milliseconds)
local SRATE         = 24000       -- Resampling rate for ultra-fast processing
local BLOCKS_FRAME  = 250         -- Blocks per frame (~50s audio/frame, ~1.5s total)

local WIN_W, WIN_H  = 760, 520

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function msg(str)
  reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

local function format_time(seconds)
  if not seconds or seconds < 0 then seconds = 0 end
  local m = math.floor(seconds / 60)
  local s = seconds - (m * 60)
  return string.format("%02d:%05.2f", m, s)
end

local function get_or_create_visualizer_fx(track)
  local fx_name = "kb_Loudness Visualizer"
  local fx_count = reaper.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, i, "")
    if name:find("kb_Loudness Visualizer", 1, true) then
      return i
    end
  end
  
  local fx_idx = reaper.TrackFX_AddByName(track, fx_name, false, -1)
  if fx_idx == -1 then
    fx_idx = reaper.TrackFX_AddByName(track, "kb_Loudness Visualizer.jsfx", false, -1)
  end
  return fx_idx
end

local function make_envelope_visible(env)
  if not env then return end
  if reaper.BR_EnvAlloc then
    local br_env = reaper.BR_EnvAlloc(env, false)
    if br_env then
      local active, visible, armed, inLane, laneHeight, defaultShape, faderScaling = reaper.BR_EnvGetProperties(br_env)
      reaper.BR_EnvSetProperties(br_env, true, true, armed, true, laneHeight, defaultShape, faderScaling)
      reaper.BR_EnvFree(br_env, true)
    end
  else
    local ret, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
    if ret then
      if chunk:find("\nVIS ") then
        chunk = chunk:gsub("\nVIS %d+ %d+ %d+", "\nVIS 1 1 0")
      else
        chunk = chunk:gsub("\n<PARMENV", "\n<PARMENV\nVIS 1 1 0")
      end
      reaper.SetEnvelopeStateChunk(env, chunk, false)
    end
  end
  reaper.TrackList_AdjustWindows(false)
end

local function init_k_filters(srate)
  local db = 3.999843853973347
  local f0_1 = 1681.974450955533
  local Q1 = 0.7071752369554196
  local K1 = math.tan(math.pi * f0_1 / srate)
  local Vh = 10 ^ (db / 20)
  local Vb = Vh ^ 0.4996667741545416
  local a0_1 = 1 + K1 / Q1 + K1 * K1
  local f1a1 = 2 * (K1 * K1 - 1) / a0_1
  local f1a2 = (1 - K1 / Q1 + K1 * K1) / a0_1
  local f1b0 = (Vh + Vb * K1 / Q1 + K1 * K1) / a0_1
  local f1b1 = 2 * (K1 * K1 - Vh) / a0_1
  local f1b2 = (Vh - Vb * K1 / Q1 + K1 * K1) / a0_1

  local f0_2 = 38.13547087602444
  local Q2 = 0.5003270373238773
  local K2 = math.tan(math.pi * f0_2 / srate)
  local a0_2 = 1 + K2 / Q2 + K2 * K2
  local f2a1 = 2 * (K2 * K2 - 1) / a0_2
  local f2a2 = (1 - K2 / Q2 + K2 * K2) / a0_2
  local f2b0 = 1 / a0_2
  local f2b1 = -2 / a0_2
  local f2b2 = 1 / a0_2

  return {
    f1a1 = f1a1, f1a2 = f1a2, f1b0 = f1b0, f1b1 = f1b1, f1b2 = f1b2,
    f2a1 = f2a1, f2a2 = f2a2, f2b0 = f2b0, f2b1 = f2b1, f2b2 = f2b2
  }
end

--------------------------------------------------------------------------------
-- GUI State & User Preferences
--------------------------------------------------------------------------------
local scale_preset = tonumber(reaper.GetExtState("kb_Loudness", "scale_preset")) or 1
local do_s         = (reaper.GetExtState("kb_Loudness", "draw_s") ~= "n")
local do_m         = (reaper.GetExtState("kb_Loudness", "draw_m") == "y")
local do_rms       = (reaper.GetExtState("kb_Loudness", "draw_rms") == "y")

local state             = "IDLE"     -- "IDLE", "ANALYZING", "FINISHED", "ERROR"
local status_msg        = "Ready. Select track with album songs and click Regenerate."
local status_color      = {0.7, 0.7, 0.75}
local progress_val      = 0.0

-- Analysis execution context
local ctx = {}
local last_mouse_cap = 0

--------------------------------------------------------------------------------
-- Start Analysis
--------------------------------------------------------------------------------
local function start_analysis()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    state = "ERROR"
    status_msg = "Error: Please select a track with album items first!"
    status_color = {0.95, 0.35, 0.35}
    return
  end

  local item_count = reaper.CountTrackMediaItems(track)
  if item_count == 0 then
    state = "ERROR"
    status_msg = "Error: Selected track contains no media items."
    status_color = {0.95, 0.35, 0.35}
    return
  end

  if not do_s and not do_m and not do_rms then
    state = "ERROR"
    status_msg = "Please check at least one envelope to draw (LUFS-S / LUFS-M / RMS)."
    status_color = {0.95, 0.75, 0.35}
    return
  end

  -- Save settings
  reaper.SetExtState("kb_Loudness", "scale_preset", tostring(scale_preset), true)
  reaper.SetExtState("kb_Loudness", "draw_s", do_s and "y" or "n", true)
  reaper.SetExtState("kb_Loudness", "draw_m", do_m and "y" or "n", true)
  reaper.SetExtState("kb_Loudness", "draw_rms", do_rms and "y" or "n", true)

  -- Setup scale bounds & slider indices
  local slider_s_idx, slider_m_idx, slider_rms_idx
  local min_lufs, max_lufs

  if scale_preset == 2 then
    slider_s_idx   = 1
    slider_m_idx   = 3
    slider_rms_idx = 5
    min_lufs, max_lufs = -30.0, -6.0
  elseif scale_preset == 3 then
    slider_s_idx   = 2
    slider_m_idx   = 4
    slider_rms_idx = 6
    min_lufs, max_lufs = -60.0, 0.0
  else
    -- Mastering (-24..-6 dB) - DEFAULT
    slider_s_idx   = 0
    slider_m_idx   = 3
    slider_rms_idx = 5
    min_lufs, max_lufs = -24.0, -6.0
  end

  -- Time bounds
  local sel_start, sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local start_time, end_time
  local is_time_sel = (sel_end - sel_start) > 0.5

  if is_time_sel then
    start_time, end_time = sel_start, sel_end
  else
    local first_item = reaper.GetTrackMediaItem(track, 0)
    start_time = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
    end_time   = start_time + reaper.GetMediaItemInfo_Value(first_item, "D_LENGTH")

    for i = 1, item_count - 1 do
      local it  = reaper.GetTrackMediaItem(track, i)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos < start_time then start_time = pos end
      if pos + len > end_time then end_time = pos + len end
    end
  end

  local fx_idx = get_or_create_visualizer_fx(track)
  if fx_idx == -1 then
    state = "ERROR"
    status_msg = "Error: Could not insert kb_Loudness Visualizer JSFX."
    status_color = {0.95, 0.35, 0.35}
    return
  end

  local aa = reaper.CreateTrackAudioAccessor(track)
  if not aa then
    state = "ERROR"
    status_msg = "Error: Could not create Audio Accessor."
    status_color = {0.95, 0.35, 0.35}
    return
  end

  -- Collect song items
  local songs = {}
  for i = 0, item_count - 1 do
    local it   = reaper.GetTrackMediaItem(track, i)
    local pos  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local take = reaper.GetActiveTake(it)
    local name = take and reaper.GetTakeName(take) or string.format("Track Item %02d", i + 1)
    songs[#songs + 1] = {
      index = i + 1,
      name = name,
      start_time = pos,
      end_time = pos + len,
      max_s = -100.0,
      max_time_s = pos,
      max_m = -100.0,
      max_rms = -100.0
    }
  end

  local samples_per_block = math.floor(STEP_SEC * SRATE)
  local num_channels = 2
  local buffer_size = samples_per_block * num_channels
  local buf = reaper.new_array(buffer_size)

  local filters = init_k_filters(SRATE)
  local total_duration = end_time - start_time
  local total_blocks = math.ceil(total_duration / STEP_SEC)

  ctx = {
    track = track,
    fx_idx = fx_idx,
    aa = aa,
    buf = buf,
    filters = filters,
    songs = songs,
    start_time = start_time,
    end_time = end_time,
    total_duration = total_duration,
    total_blocks = total_blocks,
    cur_block = 0,
    samples_per_block = samples_per_block,
    num_channels = num_channels,
    buffer_size = buffer_size,
    min_lufs = min_lufs,
    max_lufs = max_lufs,
    slider_s_idx = slider_s_idx,
    slider_m_idx = slider_m_idx,
    slider_rms_idx = slider_rms_idx,
    win_s_blocks = math.max(1, math.floor(WIN_S_SEC / STEP_SEC + 0.5)),
    win_m_blocks = math.max(1, math.floor(WIN_M_SEC / STEP_SEC + 0.5)),
    ring_s = {}, ring_idx_s = 1, ring_sum_s = 0, active_s = 0,
    ring_m = {}, ring_idx_m = 1, ring_sum_m = 0, active_m = 0,
    ring_rms = {}, ring_idx_rms = 1, ring_sum_rms = 0, active_rms = 0,
    f1_1_L = 0, f1_2_L = 0, f2_1_L = 0, f2_2_L = 0,
    f1_1_R = 0, f1_2_R = 0, f2_1_R = 0, f2_2_R = 0,
    pts_s = do_s and {} or nil,
    pts_m = do_m and {} or nil,
    pts_rms = do_rms and {} or nil,
    last_val_s = nil, last_val_m = nil, last_val_rms = nil,
    max_album_s = -100.0, max_album_time_s = start_time,
    max_album_m = -100.0, max_album_time_m = start_time,
    max_album_rms = -100.0,
    current_song_idx = nil
  }

  state = "ANALYZING"
  status_msg = "Analyzing audio..."
  status_color = {0.3, 0.7, 0.95}
  progress_val = 0.0
end

--------------------------------------------------------------------------------
-- Process Analysis Slice
--------------------------------------------------------------------------------
local function process_analysis_slice()
  if state ~= "ANALYZING" then return end

  local f = ctx.filters
  local f1a1, f1a2, f1b0, f1b1, f1b2 = f.f1a1, f.f1a2, f.f1b0, f.f1b1, f.f1b2
  local f2a1, f2a2, f2b0, f2b1, f2b2 = f.f2a1, f.f2a2, f.f2b0, f.f2b1, f.f2b2

  local blocks_to_do = math.min(BLOCKS_FRAME, ctx.total_blocks - ctx.cur_block)

  for _ = 1, blocks_to_do do
    local cur_time = ctx.start_time + (ctx.cur_block * STEP_SEC)
    ctx.buf.clear()

    -- Check if in song
    local in_song = nil
    for _, song in ipairs(ctx.songs) do
      if cur_time >= song.start_time and cur_time < song.end_time then
        in_song = song
        break
      end
    end

    -- Song transition reset
    if in_song and in_song.index ~= ctx.current_song_idx then
      ctx.current_song_idx = in_song.index
      ctx.ring_s = {}; ctx.ring_idx_s = 1; ctx.ring_sum_s = 0; ctx.active_s = 0
      ctx.ring_m = {}; ctx.ring_idx_m = 1; ctx.ring_sum_m = 0; ctx.active_m = 0
      ctx.ring_rms = {}; ctx.ring_idx_rms = 1; ctx.ring_sum_rms = 0; ctx.active_rms = 0
      ctx.f1_1_L, ctx.f1_2_L, ctx.f2_1_L, ctx.f2_2_L = 0, 0, 0, 0
      ctx.f1_1_R, ctx.f1_2_R, ctx.f2_1_R, ctx.f2_2_R = 0, 0, 0, 0

      if ctx.pts_s   then ctx.pts_s[#ctx.pts_s + 1]     = { time = in_song.start_time, val = ctx.min_lufs } end
      if ctx.pts_m   then ctx.pts_m[#ctx.pts_m + 1]     = { time = in_song.start_time, val = ctx.min_lufs } end
      if ctx.pts_rms then ctx.pts_rms[#ctx.pts_rms + 1] = { time = in_song.start_time, val = ctx.min_lufs } end
    elseif not in_song and ctx.current_song_idx ~= nil then
      local prev_song = ctx.songs[ctx.current_song_idx]
      ctx.current_song_idx = nil
      if prev_song then
        if ctx.pts_s   then ctx.pts_s[#ctx.pts_s + 1]     = { time = prev_song.end_time, val = ctx.min_lufs } end
        if ctx.pts_m   then ctx.pts_m[#ctx.pts_m + 1]     = { time = prev_song.end_time, val = ctx.min_lufs } end
        if ctx.pts_rms then ctx.pts_rms[#ctx.pts_rms + 1] = { time = prev_song.end_time, val = ctx.min_lufs } end
      end
    end

    local ret = reaper.GetAudioAccessorSamples(ctx.aa, SRATE, ctx.num_channels, cur_time, ctx.samples_per_block, ctx.buf)
    local k_energy_sum = 0.0
    local raw_energy_sum = 0.0

    if ret > 0 and in_song then
      for i = 1, ctx.buffer_size, 2 do
        local xL = ctx.buf[i]
        local xR = ctx.buf[i + 1]

        raw_energy_sum = raw_energy_sum + (xL * xL + xR * xR)

        local f1_0_L = xL - f1a1 * ctx.f1_1_L - f1a2 * ctx.f1_2_L
        local y1_L   = f1b0 * f1_0_L + f1b1 * ctx.f1_1_L + f1b2 * ctx.f1_2_L
        ctx.f1_2_L = ctx.f1_1_L; ctx.f1_1_L = f1_0_L

        local f2_0_L = y1_L - f2a1 * ctx.f2_1_L - f2a2 * ctx.f2_2_L
        local y2_L   = f2b0 * f2_0_L + f2b1 * ctx.f2_1_L + f2b2 * ctx.f2_2_L
        ctx.f2_2_L = ctx.f2_1_L; ctx.f2_1_L = f2_0_L

        local f1_0_R = xR - f1a1 * ctx.f1_1_R - f1a2 * ctx.f1_2_R
        local y1_R   = f1b0 * f1_0_R + f1b1 * ctx.f1_1_R + f1b2 * ctx.f1_2_R
        ctx.f1_2_R = ctx.f1_1_R; ctx.f1_1_R = f1_0_R

        local f2_0_R = y1_R - f2a1 * ctx.f2_1_R - f2a2 * ctx.f2_2_R
        local y2_R   = f2b0 * f2_0_R + f2b1 * ctx.f2_1_R + f2b2 * ctx.f2_2_R
        ctx.f2_2_R = ctx.f2_1_R; ctx.f2_1_R = f2_0_R

        k_energy_sum = k_energy_sum + (y2_L * y2_L + y2_R * y2_R)
      end
    end

    local ms_k_block   = (ret > 0 and in_song) and (k_energy_sum / ctx.samples_per_block) or 0.0
    local ms_raw_block = (ret > 0 and in_song) and (raw_energy_sum / (ctx.samples_per_block * 2)) or 0.0
    local env_time = cur_time

    -- LUFS-S
    local old_s = ctx.ring_s[ctx.ring_idx_s] or 0.0
    ctx.ring_sum_s = ctx.ring_sum_s + ms_k_block - old_s
    ctx.ring_s[ctx.ring_idx_s] = ms_k_block
    ctx.ring_idx_s = ctx.ring_idx_s + 1
    if ctx.ring_idx_s > ctx.win_s_blocks then ctx.ring_idx_s = 1 end
    if in_song and ctx.active_s < ctx.win_s_blocks then ctx.active_s = ctx.active_s + 1 end

    local mean_s = (in_song and ctx.active_s > 0) and (ctx.ring_sum_s / ctx.active_s) or 0.0
    local lufs_s = (mean_s > 1e-10) and (-0.691 + 10.0 * (math.log(mean_s) / math.log(10.0))) or ctx.min_lufs
    if lufs_s < ctx.min_lufs then lufs_s = ctx.min_lufs end
    if lufs_s > ctx.max_lufs then lufs_s = ctx.max_lufs end

    if ctx.pts_s then
      if not ctx.last_val_s or math.abs(lufs_s - ctx.last_val_s) >= 0.08 or (ctx.cur_block % 5 == 0) then
        ctx.pts_s[#ctx.pts_s + 1] = { time = env_time, val = lufs_s }
        ctx.last_val_s = lufs_s
      end
    end

    if in_song and lufs_s > ctx.max_album_s and lufs_s > ctx.min_lufs then
      ctx.max_album_s = lufs_s
      ctx.max_album_time_s = env_time
    end

    -- LUFS-M
    local old_m = ctx.ring_m[ctx.ring_idx_m] or 0.0
    ctx.ring_sum_m = ctx.ring_sum_m + ms_k_block - old_m
    ctx.ring_m[ctx.ring_idx_m] = ms_k_block
    ctx.ring_idx_m = ctx.ring_idx_m + 1
    if ctx.ring_idx_m > ctx.win_m_blocks then ctx.ring_idx_m = 1 end
    if in_song and ctx.active_m < ctx.win_m_blocks then ctx.active_m = ctx.active_m + 1 end

    local mean_m = (in_song and ctx.active_m > 0) and (ctx.ring_sum_m / ctx.active_m) or 0.0
    local lufs_m = (mean_m > 1e-10) and (-0.691 + 10.0 * (math.log(mean_m) / math.log(10.0))) or ctx.min_lufs
    if lufs_m < ctx.min_lufs then lufs_m = ctx.min_lufs end
    if lufs_m > ctx.max_lufs then lufs_m = ctx.max_lufs end

    if ctx.pts_m then
      if not ctx.last_val_m or math.abs(lufs_m - ctx.last_val_m) >= 0.10 or (ctx.cur_block % 4 == 0) then
        ctx.pts_m[#ctx.pts_m + 1] = { time = env_time, val = lufs_m }
        ctx.last_val_m = lufs_m
      end
    end

    if in_song and lufs_m > ctx.max_album_m and lufs_m > ctx.min_lufs then
      ctx.max_album_m = lufs_m
      ctx.max_album_time_m = env_time
    end

    -- RMS
    local old_rms = ctx.ring_rms[ctx.ring_idx_rms] or 0.0
    ctx.ring_sum_rms = ctx.ring_sum_rms + ms_raw_block - old_rms
    ctx.ring_rms[ctx.ring_idx_rms] = ms_raw_block
    ctx.ring_idx_rms = ctx.ring_idx_rms + 1
    if ctx.ring_idx_rms > ctx.win_m_blocks then ctx.ring_idx_rms = 1 end
    if in_song and ctx.active_rms < ctx.win_m_blocks then ctx.active_rms = ctx.active_rms + 1 end

    local mean_rms = (in_song and ctx.active_rms > 0) and (ctx.ring_sum_rms / ctx.active_rms) or 0.0
    local rms_db = (mean_rms > 1e-10) and (10.0 * (math.log(mean_rms) / math.log(10.0)) + 3.0103) or ctx.min_lufs
    if rms_db < ctx.min_lufs then rms_db = ctx.min_lufs end
    if rms_db > ctx.max_lufs then rms_db = ctx.max_lufs end

    if ctx.pts_rms then
      if not ctx.last_val_rms or math.abs(rms_db - ctx.last_val_rms) >= 0.10 or (ctx.cur_block % 4 == 0) then
        ctx.pts_rms[#ctx.pts_rms + 1] = { time = env_time, val = rms_db }
        ctx.last_val_rms = rms_db
      end
    end

    if in_song and rms_db > ctx.max_album_rms and rms_db > ctx.min_lufs then
      ctx.max_album_rms = rms_db
    end

    if in_song then
      if lufs_s > in_song.max_s and lufs_s > ctx.min_lufs then
        in_song.max_s = lufs_s
        in_song.max_time_s = env_time
      end
      if lufs_m > in_song.max_m and lufs_m > ctx.min_lufs then in_song.max_m = lufs_m end
      if rms_db > in_song.max_rms and rms_db > ctx.min_lufs then in_song.max_rms = rms_db end
      status_msg = string.format("[%02d] %s (%.1f LUFS)", in_song.index, in_song.name, lufs_s)
    end

    ctx.cur_block = ctx.cur_block + 1
  end

  progress_val = math.min(1.0, ctx.cur_block / ctx.total_blocks)

  -- Check if finished
  if ctx.cur_block >= ctx.total_blocks then
    if ctx.aa then
      reaper.DestroyAudioAccessor(ctx.aa)
      ctx.aa = nil
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local env_s   = do_s   and reaper.GetFXEnvelope(ctx.track, ctx.fx_idx, ctx.slider_s_idx, true) or nil
    local env_m   = do_m   and reaper.GetFXEnvelope(ctx.track, ctx.fx_idx, ctx.slider_m_idx, true) or nil
    local env_rms = do_rms and reaper.GetFXEnvelope(ctx.track, ctx.fx_idx, ctx.slider_rms_idx, true) or nil

    if env_s and ctx.pts_s then
      reaper.DeleteEnvelopePointRange(env_s, ctx.start_time - 1.0, ctx.end_time + 1.0)
      for _, pt in ipairs(ctx.pts_s) do reaper.InsertEnvelopePoint(env_s, pt.time, pt.val, 0, 0, false, true) end
      reaper.Envelope_SortPoints(env_s)
      make_envelope_visible(env_s)
    end

    if env_m and ctx.pts_m then
      reaper.DeleteEnvelopePointRange(env_m, ctx.start_time - 1.0, ctx.end_time + 1.0)
      for _, pt in ipairs(ctx.pts_m) do reaper.InsertEnvelopePoint(env_m, pt.time, pt.val, 0, 0, false, true) end
      reaper.Envelope_SortPoints(env_m)
      make_envelope_visible(env_m)
    end

    if env_rms and ctx.pts_rms then
      reaper.DeleteEnvelopePointRange(env_rms, ctx.start_time - 1.0, ctx.end_time + 1.0)
      for _, pt in ipairs(ctx.pts_rms) do reaper.InsertEnvelopePoint(env_rms, pt.time, pt.val, 0, 0, false, true) end
      reaper.Envelope_SortPoints(env_rms)
      make_envelope_visible(env_rms)
    end

    if do_s and ctx.max_album_s > ctx.min_lufs then
      local marker_name = string.format("PEAK LUFS-S (%.1f)", ctx.max_album_s)
      local marker_color = reaper.ColorToNative(255, 60, 60) | 0x1000000
      reaper.AddProjectMarker2(0, false, ctx.max_album_time_s, 0, marker_name, -1, marker_color)
    end

    if do_m and ctx.max_album_m > ctx.min_lufs and (math.abs(ctx.max_album_time_m - ctx.max_album_time_s) > 1.0 or not do_s) then
      local marker_name = string.format("PEAK LUFS-M (%.1f)", ctx.max_album_m)
      local marker_color = reaper.ColorToNative(255, 140, 20) | 0x1000000
      reaper.AddProjectMarker2(0, false, ctx.max_album_time_m, 0, marker_name, -1, marker_color)
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Generate loudness envelope for selected track", -1)

    state = "FINISHED"
    status_msg = string.format("✔ Complete! Peak: %.1f LUFS-S at [%s]", ctx.max_album_s, format_time(ctx.max_album_time_s))
    status_color = {0.3, 0.85, 0.45}
    progress_val = 1.0

    -- Console report
    reaper.ClearConsole()
    msg("====================================================================================================")
    msg("                                ALBUM LOUDNESS & DYNAMICS REPORT                                   ")
    msg(string.format("                 Scale: %.0f dB to %.0f dB | ITU-R BS.1770-4 / EBU R128                  ", ctx.min_lufs, ctx.max_lufs))
    msg("====================================================================================================")
    msg(string.format("Duration analyzed: %s - %s (%s)", format_time(ctx.start_time), format_time(ctx.end_time), format_time(ctx.total_duration)))
    if do_s and ctx.max_album_s > ctx.min_lufs then
      msg(string.format("★ LOUDEST SHORT-TERM PEAK (LUFS-S):  %5.1f LUFS at [%s]", ctx.max_album_s, format_time(ctx.max_album_time_s)))
    end
    if do_m and ctx.max_album_m > ctx.min_lufs then
      msg(string.format("★ LOUDEST MOMENTARY PEAK  (LUFS-M):  %5.1f LUFS at [%s]", ctx.max_album_m, format_time(ctx.max_album_time_m)))
    end
    if do_rms and ctx.max_album_rms > ctx.min_lufs then
      msg(string.format("★ HIGHEST PHYSICAL RMS   (AES-17):  %5.1f dB", ctx.max_album_rms))
    end
    msg("----------------------------------------------------------------------------------------------------")
    msg(string.format("%-4s  %-10s  %-28s  %-12s  %-12s  %-10s  %-11s", "#", "Start", "Song Title", "Max LUFS-S", "Max LUFS-M", "Max RMS", "Peak Time"))
    msg("----------------------------------------------------------------------------------------------------")

    for _, song in ipairs(ctx.songs) do
      local s_str   = song.max_s   > ctx.min_lufs and string.format("%5.1f LUFS", song.max_s)   or "  N/A    "
      local m_str   = song.max_m   > ctx.min_lufs and string.format("%5.1f LUFS", song.max_m)   or "  N/A    "
      local rms_str = song.max_rms > ctx.min_lufs and string.format("%5.1f dB  ", song.max_rms) or "  N/A    "
      local peak_t_str = song.max_s > ctx.min_lufs and format_time(song.max_time_s) or "  --:--  "
      local title = song.name
      if #title > 26 then title = title:sub(1, 24) .. ".." end
      msg(string.format("%02d    %-10s  %-28s  %-12s  %-12s  %-10s  %-11s", song.index, format_time(song.start_time), title, s_str, m_str, rms_str, peak_t_str))
    end
    msg("====================================================================================================")
  end
end

--------------------------------------------------------------------------------
-- GUI Drawing & Event Handling
--------------------------------------------------------------------------------
local function in_rect(mx, my, x, y, w, h)
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function draw_gui()
  local mx, my = gfx.mouse_x, gfx.mouse_y
  local click = (gfx.mouse_cap & 1 == 1) and (last_mouse_cap & 1 == 0)
  last_mouse_cap = gfx.mouse_cap

  -- Background
  gfx.set(0.12, 0.12, 0.15, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  -- Top header bar
  gfx.set(0.17, 0.17, 0.22, 1)
  gfx.rect(0, 0, gfx.w, 70, 1)
  gfx.set(0.20, 0.60, 0.90, 1)
  gfx.rect(0, 68, gfx.w, 2, 1)

  -- Header text
  gfx.set(0.95, 0.95, 0.95, 1)
  gfx.setfont(1, "Segoe UI", 22, string.byte('b'))
  gfx.x, gfx.y = 28, 14
  gfx.drawstr("ALBUM LOUDNESS VISUALIZER")

  gfx.set(0.55, 0.68, 0.80, 1)
  gfx.setfont(2, "Segoe UI", 14, 0)
  gfx.x, gfx.y = 28, 42
  gfx.drawstr("ITU-R BS.1770-4 / EBU R128 Loudness Automation Generator")

  ------------------------------------------------------------------------------
  -- Section 1: Vertical Scale
  ------------------------------------------------------------------------------
  gfx.set(0.85, 0.88, 0.92, 1)
  gfx.setfont(3, "Segoe UI", 16, string.byte('b'))
  gfx.x, gfx.y = 28, 86
  gfx.drawstr("VERTICAL SCALE (Visual Zoom into Musical Range):")

  local scales = {
    { id = 1, title = "Mastering:  -24 .. -6 dB", sub = "(Recommended - fills 80% of lane height)" },
    { id = 2, title = "Dynamic:    -30 .. -6 dB", sub = "(For high dynamic range / classical / acoustic)" },
    { id = 3, title = "Full Range: -60 ..  0 dB", sub = "(Technical wide view)" }
  }

  for i, sc in ipairs(scales) do
    local ry = 114 + (i - 1) * 35
    local is_hover = in_rect(mx, my, 28, ry, gfx.w - 56, 32)

    if click and is_hover and state ~= "ANALYZING" then
      scale_preset = sc.id
    end

    -- Radio circle
    local is_sel = (scale_preset == sc.id)
    gfx.set(is_sel and 0.25 or 0.40, is_sel and 0.65 or 0.40, is_sel and 0.95 or 0.40, 1)
    gfx.circle(40, ry + 15, 9, false, true)
    if is_sel then
      gfx.circle(40, ry + 15, 5, true, true)
    end

    -- Labels
    gfx.set(is_sel and 0.98 or (is_hover and 0.85 or 0.72), is_sel and 0.98 or (is_hover and 0.85 or 0.72), is_sel and 0.98 or (is_hover and 0.85 or 0.72), 1)
    gfx.setfont(4, "Segoe UI", 16, is_sel and string.byte('b') or 0)
    gfx.x, gfx.y = 62, ry + 4
    gfx.drawstr(sc.title)

    gfx.set(0.50, 0.55, 0.62, 1)
    gfx.setfont(5, "Segoe UI", 14, 0)
    gfx.x = 320
    gfx.drawstr(sc.sub)
  end

  -- Separator line 1
  gfx.set(0.18, 0.18, 0.22, 1)
  gfx.line(28, 228, gfx.w - 28, 228)

  ------------------------------------------------------------------------------
  -- Section 2: Envelopes to generate
  ------------------------------------------------------------------------------
  gfx.set(0.85, 0.88, 0.92, 1)
  gfx.setfont(3, "Segoe UI", 16, string.byte('b'))
  gfx.x, gfx.y = 28, 238
  gfx.drawstr("ENVELOPES TO DRAW:")

  local chks = {
    { checked = do_s,   title = "LUFS-S (3.0s Short-Term)", sub = "- Recommended contour for album matching", toggle = function() do_s = not do_s end },
    { checked = do_m,   title = "LUFS-M (0.4s Momentary)",  sub = "- Fast 400ms burst dynamics",             toggle = function() do_m = not do_m end },
    { checked = do_rms, title = "RMS    (AES-17 dB)",       sub = "- Unweighted physical energy",            toggle = function() do_rms = not do_rms end }
  }

  for i, ck in ipairs(chks) do
    local cy = 266 + (i - 1) * 34
    local is_hover = in_rect(mx, my, 28, cy, gfx.w - 56, 30)

    if click and is_hover and state ~= "ANALYZING" then
      ck.toggle()
    end

    -- Checkbox square
    gfx.set(ck.checked and 0.25 or 0.35, ck.checked and 0.65 or 0.35, ck.checked and 0.95 or 0.35, 1)
    gfx.rect(32, cy + 5, 18, 18, false)
    if ck.checked then
      gfx.rect(35, cy + 8, 12, 12, true)
    end

    -- Labels
    gfx.set(ck.checked and 0.98 or (is_hover and 0.85 or 0.70), ck.checked and 0.98 or (is_hover and 0.85 or 0.70), ck.checked and 0.98 or (is_hover and 0.85 or 0.70), 1)
    gfx.setfont(4, "Segoe UI", 16, ck.checked and string.byte('b') or 0)
    gfx.x, gfx.y = 62, cy + 4
    gfx.drawstr(ck.title)

    gfx.set(0.50, 0.55, 0.62, 1)
    gfx.setfont(5, "Segoe UI", 14, 0)
    gfx.x = 320
    gfx.drawstr(ck.sub)
  end

  -- Separator line 2
  gfx.set(0.18, 0.18, 0.22, 1)
  gfx.line(28, 376, gfx.w - 28, 376)

  ------------------------------------------------------------------------------
  -- Section 3: Regenerate Button & Status
  ------------------------------------------------------------------------------
  local btn_x, btn_y, btn_w, btn_h = 28, 390, gfx.w - 56, 54
  local btn_hover = in_rect(mx, my, btn_x, btn_y, btn_w, btn_h)

  if state == "ANALYZING" then
    -- Disabled / busy button
    gfx.set(0.20, 0.35, 0.45, 1)
    gfx.roundrect(btn_x, btn_y, btn_w, btn_h, 5, true)
    gfx.set(0.85, 0.90, 0.95, 1)
    gfx.setfont(6, "Segoe UI", 19, string.byte('b'))
    local txt = "PROCESSING ALBUM AUDIO..."
    local tw, th = gfx.measurestr(txt)
    gfx.x, gfx.y = btn_x + (btn_w - tw) * 0.5, btn_y + (btn_h - th) * 0.5
    gfx.drawstr(txt)
  else
    if click and btn_hover then
      start_analysis()
    end

    -- Active button with hover highlight
    if btn_hover then
      gfx.set(0.25, 0.68, 0.98, 1)
    else
      gfx.set(0.18, 0.55, 0.85, 1)
    end
    gfx.roundrect(btn_x, btn_y, btn_w, btn_h, 5, true)

    gfx.set(1, 1, 1, 1)
    gfx.setfont(6, "Segoe UI", 19, string.byte('b'))
    local txt = "▶   REGENERATE ENVELOPES"
    local tw, th = gfx.measurestr(txt)
    gfx.x, gfx.y = btn_x + (btn_w - tw) * 0.5, btn_y + (btn_h - th) * 0.5
    gfx.drawstr(txt)
  end

  -- Progress Bar / Status Area
  local bar_x, bar_y, bar_w, bar_h = 28, 458, gfx.w - 56, 32

  if state == "ANALYZING" then
    -- Progress Bar
    gfx.set(0.18, 0.18, 0.22, 1)
    gfx.rect(bar_x, bar_y, bar_w, bar_h, 1)
    gfx.set(0.20, 0.65, 0.95, 1)
    local fill_w = math.max(0, math.min(bar_w, bar_w * progress_val))
    gfx.rect(bar_x, bar_y, fill_w, bar_h, 1)

    gfx.set(1, 1, 1, 1)
    gfx.setfont(7, "Segoe UI", 14, string.byte('b'))
    local p_str = string.format("%d%% - %s", math.floor(progress_val * 100), status_msg)
    local pw, ph = gfx.measurestr(p_str)
    gfx.x = bar_x + (bar_w - pw) * 0.5
    gfx.y = bar_y + (bar_h - ph) * 0.5
    gfx.drawstr(p_str)
  else
    -- Status text
    gfx.set(status_color[1], status_color[2], status_color[3], 1)
    gfx.setfont(7, "Segoe UI", 14, string.byte('b'))
    local sw, sh = gfx.measurestr(status_msg)
    gfx.x = bar_x + (bar_w - sw) * 0.5
    gfx.y = bar_y + (bar_h - sh) * 0.5
    gfx.drawstr(status_msg)
  end

  gfx.update()
end

--------------------------------------------------------------------------------
-- Main Loop (Non-blocking Defer)
--------------------------------------------------------------------------------
local function loop()
  local char = gfx.getchar()
  if char < 0 or char == 27 then
    gfx.quit()
    if ctx.aa then
      if reaper.ValidatePtr2 and reaper.ValidatePtr2(0, ctx.aa, "AudioAccessor*") then
        reaper.DestroyAudioAccessor(ctx.aa)
      elseif not reaper.ValidatePtr2 then
        reaper.DestroyAudioAccessor(ctx.aa)
      end
      ctx.aa = nil
    end
    return
  end

  if state == "ANALYZING" then
    process_analysis_slice()
  end

  draw_gui()
  reaper.defer(loop)
end

--------------------------------------------------------------------------------
-- Entry Point
--------------------------------------------------------------------------------
local function main()
  gfx.clear = reaper.ColorToNative(30, 30, 35)
  gfx.init("kb_Loudness Visualizer", WIN_W, WIN_H, 0)
  loop()
end

main()

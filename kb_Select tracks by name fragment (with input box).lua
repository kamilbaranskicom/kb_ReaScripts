-- @description Select tracks by name fragment (with input box)
-- @version 1.1
-- @author me2beats & AI
-- @changelog
--  + added input box
--  + changed matching to partial name search

local r = reaper; local function nothing() end; local function bla() r.defer(nothing) end

local tracks = r.CountTracks()
if tracks == 0 then bla() return end

-- Show input box to the user
local retval, user_input = r.GetUserInputs("Select Tracks", 1, "Track name fragment:", "")

-- If user canceled or input is empty, exit gracefully
if not retval or user_input == "" then bla() return end

r.Undo_BeginBlock() r.PreventUIRefresh(1)

r.Main_OnCommand(40297, 0) -- unselect all tracks

for i = 0, tracks-1 do
  local tr = r.GetTrack(0, i)
  local _, tr_name = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', 0)
  
  -- string.find(s, sub, 1, true) looks for a plain substring, ignoring Lua patterns/regex
  if string.find(tr_name, user_input, 1, true) then 
    r.SetTrackSelected(tr, 1) 
  end
end

r.PreventUIRefresh(-1) r.Undo_EndBlock('Select tracks by name fragment', -1)

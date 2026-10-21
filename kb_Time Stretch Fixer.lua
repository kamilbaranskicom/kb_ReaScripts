-- @description Universal Cubase Time-Stretch Import Fixer (Preserve Item Length)
-- @version 1.1
-- @author Kamil Barański (kamilbaranskicom) & AI
-- @changelog
--   + Initial release
-- @about Fixes playrate of imported time-stretched items without changing their timeline length.

local num_selected_items = reaper.CountSelectedMediaItems(0)

if num_selected_items == 0 then
  reaper.ShowMessageBox("Please select at least one media item to fix!", "Error", 0)
  return
end

-- Define input dialog parameters
local dialog_title = "Fix Cubase Time-Stretch Import"
local num_inputs = 3
local captions_csv = "Playrate Ratio (e.g., 1.2 or 0.85):,Original Tempo (BPM - optional):,Target Tempo (BPM - optional):"
local def_inputs_csv = "1.2000,," 

-- Display the user input dialog
local retval, retvals_csv = reaper.GetUserInputs(dialog_title, num_inputs, captions_csv, def_inputs_csv)

if not retval then return end -- User cancelled

-- Parse user inputs
local user_ratio, user_old_bpm, user_new_bpm = retvals_csv:match("([^,]*),([^,]*),([^,]*)")

local exact_playrate = 1.0

-- Calculate target playrate based on provided values
if user_old_bpm ~= "" and user_new_bpm ~= "" then
  local old_bpm = tonumber(user_old_bpm)
  local new_bpm = tonumber(user_new_bpm)
  if old_bpm and new_bpm and old_bpm > 0 then
    exact_playrate = new_bpm / old_bpm
  else
    reaper.ShowMessageBox("Invalid BPM values entered.", "Error", 0)
    return
  end
else
  local ratio = tonumber(user_ratio)
  if ratio and ratio > 0 then
    exact_playrate = ratio
  else
    reaper.ShowMessageBox("Invalid playrate ratio entered.", "Error", 0)
    return
  end
end

-- Format confirmation message
local info_msg = string.format(
  "Apply Playrate: %.4f to %d selected item(s)?\n(Item lengths on the timeline will be preserved)",
  exact_playrate, num_selected_items
)

local confirm = reaper.ShowMessageBox(info_msg, "Confirm Operation", 1)
if confirm ~= 1 then return end -- User cancelled

reaper.Undo_BeginBlock()

for i = 0, num_selected_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local take = reaper.GetActiveTake(item)
  
  if take and not reaper.TakeIsMIDI(take) then
    -- Get current state before modification
    local current_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local current_playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    
    -- Calculate how much the playrate changes
    local rate_modifier = exact_playrate / current_playrate
    
    -- Adjust the source offset so the audio alignment inside the item doesn't shift
    local new_offset = current_offset * rate_modifier
    
    -- Apply playrate and offset, but DO NOT touch D_LENGTH
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", exact_playrate)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offset)
    
    -- Preserve Pitch (1 = ON, 0 = OFF / tape-style resampling)
    reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1) 
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Fix Cubase Playrate (Preserve Length)", -1)


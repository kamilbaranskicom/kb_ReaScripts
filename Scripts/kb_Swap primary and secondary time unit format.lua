-- @description Swap primary and secondary time unit format
-- @author Kamil Baranski (kamilbaranski.com)
-- @version 1.0
-- @about
--   Swaps primary and secondary time units for the ruler.
-- @changelog
--   + Initial release

-- Swap Primary and Secondary Time Units for Ruler

-- Function to check a list of command IDs and return the active one
function GetActiveCommandID(command_list)
  for _, cmd_id in ipairs(command_list) do
    if reaper.GetToggleCommandState(cmd_id) == 1 then
      return cmd_id
    end
  end
  return nil
end

function Main()
  -- Define primary time unit command IDs
  local primary_units = {
    41973, -- Absolute frames
    40370, -- Hours:Minutes:Seconds:Frames
    40365, -- Minutes:Seconds
    40368, -- Samples
    40367, -- Measures.Beats
    40368, -- Seconds
  }
  
  -- Define secondary time unit command IDs
  local secondary_units = {
    42365, -- Absolute frames
    42364, -- Hours:Minutes:Seconds:Frames
    42361, -- Minutes:Seconds
    42363, -- Samples
    42360, -- Measures.Beats  // none
    42362, -- Seconds
  }
  
  -- Get current active units
  local primary_unit = GetActiveCommandID(primary_units)
  local secondary_unit = GetActiveCommandID(secondary_units)
  
  -- Perform the swap if both units are valid
  if primary_unit and secondary_unit then
    -- Find the index positions
    local primary_index, secondary_index
    
    for i, cmd_id in ipairs(primary_units) do
      if cmd_id == primary_unit then
        primary_index = i
        break
      end
    end
    
    for i, cmd_id in ipairs(secondary_units) do
      if cmd_id == secondary_unit then
        secondary_index = i
        break
      end
    end
    
    -- Swap using the same array positions
    if primary_index and secondary_index then
      reaper.Main_OnCommand(primary_units[secondary_index], 0)
      reaper.Main_OnCommand(secondary_units[primary_index], 0)
    end
    
    reaper.UpdateTimeline()
  else
    reaper.ShowMessageBox("Could not determine current time units", "Error", 0)
  end
end

-- Run the script
reaper.Undo_BeginBlock()
Main()
reaper.Undo_EndBlock("kb_Swap primary and secondary time units", -1)

-- @description Count selected items total time (including all takes)
-- @author Kamil Barański (kamilbaranskicom)
-- @version 1.0
-- @about
--   Counts total length and recording time of all selected items including all takes.
-- @changelog
--   + Initial release

-- Count total length of all selected items including all takes
local count = reaper.CountSelectedMediaItems(0)

if count == 0 then
    reaper.MB("No items selected.", "Total Length", 0)
    return
end

local total_duration = 0
local total_takes_counted = 0

for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local num_takes = reaper.GetMediaItemNumTakes(item)
    
    for t = 0, num_takes - 1 do
        local take = reaper.GetMediaItemTake(item, t)
        
        -- Check if take exists (prevents bad argument error on empty takes)
        if take ~= nil then
            -- Only count takes that have actual source media (skip empty takes)
            if reaper.GetMediaItemTake_Source(take) ~= nil then
                total_duration = total_duration + item_length
                total_takes_counted = total_takes_counted + 1
            end
        end
    end
end

local hours = math.floor(total_duration / 3600)
local minutes = math.floor((total_duration % 3600) / 60)
local seconds = math.floor(total_duration % 60)

local message = string.format("Selected items: %d\nTakes counted: %d\nTotal recording time: %02d:%02d:%02d\n(Total seconds: %.2f)", count, total_takes_counted, hours, minutes, seconds, total_duration)

reaper.MB(message, "Recording Time", 0)

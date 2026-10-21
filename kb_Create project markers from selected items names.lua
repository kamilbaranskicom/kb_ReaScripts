-- @description Create project markers from selected items names
-- @author Kamil Barański (kamilbaranskicom)
-- @version 1.0
-- @about
--   Tworzy marker na początku każdego zaznaczonego itemu, używając nazwy aktywnego take'a lub numeru itemu.
-- @changelog
--   + Initial release

-- Tworzy marker na początku każdego zaznaczonego itemu, z nazwą itemu
reaper.Undo_BeginBlock()

local num_items = reaper.CountSelectedMediaItems(0)
for i = 0, num_items-1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local take = reaper.GetActiveTake(item)
    if take then
        local take_name = reaper.GetTakeName(take)
        reaper.AddProjectMarker(0, false, pos, 0, take_name, -1)
    else
        reaper.AddProjectMarker(0, false, pos, 0, "Item " .. tostring(i+1), -1)
    end
end

reaper.Undo_EndBlock("Add markers from selected items", -1)

--[[
 * ReaScript Name: Cubase Style Up Arrow (Select next track/item on next track)
 * Author: kamilbaranski.com
 * Licence: GPL v3
 * REAPER: 5.0
 * Extensions: None
 * Version: 1.0
--]]
 
--[[
 * Changelog:
 * v1.0 (2021-03-23)
 	+ Initial Release
--]]

function DownArrow()
  csmi = reaper.CountSelectedMediaItems(0)
  if csmi>0 then
    reaper.Main_OnCommand(40419,0)  -- Item navigation: Select and move to item in next track 
  else
    reaper.Main_OnCommand(40285,0)  -- Track: go to next track 
  end
end

-- DownArrow()

reaper.defer(DownArrow)
 

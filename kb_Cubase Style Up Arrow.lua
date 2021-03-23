--[[
 * ReaScript Name: Cubase Style Up Arrow (Select previous track/item on previous track)
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

function UpArrow()
  csmi = reaper.CountSelectedMediaItems(0)
  if csmi>0 then
    reaper.Main_OnCommand(40418,0)  -- Item navigation: Select and move to item in previous track 
  else
    reaper.Main_OnCommand(40286,0)  -- Track: go to previous track 
  end
end

reaper.defer(UpArrow)

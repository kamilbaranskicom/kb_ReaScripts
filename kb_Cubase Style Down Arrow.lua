-- @description Cubase Style Down Arrow (Select next track/item on next track)
-- @version 1.0
-- @author kamilbaranski.com
-- @changelog
--  + init 

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
 

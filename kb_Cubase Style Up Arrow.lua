-- @description Cubase Style Up Arrow (Select previous track/item on previous track)
-- @version 1.0
-- @author kamilbaranski.com
-- @changelog
--  + init 

function UpArrow()
  csmi = reaper.CountSelectedMediaItems(0)
  if csmi>0 then
    reaper.Main_OnCommand(40418,0)  -- Item navigation: Select and move to item in previous track 
  else
    reaper.Main_OnCommand(40286,0)  -- Track: go to previous track 
  end
end

-- UpArrow()

reaper.defer(UpArrow)


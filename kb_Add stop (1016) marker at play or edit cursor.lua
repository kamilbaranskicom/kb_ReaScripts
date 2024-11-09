--[[
 * ReaScript Name: Add stop marker (!1016) at play or edit cursor
 * Author: kamilbaranski.com
 * Licence: GPL v3
 * REAPER: 5.0
 * Extensions: None
 * Version: 1.0
]]--

--[[
 * Changelog:
 * v1.0 (2024-11-09)
   + Initial Release
]]--

--[[
  Adds "!1016" red marker at edit cursor (if stopped) or at play position (if playing).
  
  Requires SWS Extension to stop at !1016 marker.
  
  (IMPORTANT: SWS Extension WILL stop playback if the script is launched while playing!)
]]--


if reaper.GetPlayState() == 0 then
  pos = reaper.GetCursorPosition();
else
  pos = reaper.GetPlayPosition();
end


reaper.AddProjectMarker2(
  0,
  false,
  pos,
  0,
  "!1016",
  2000,
  reaper.ColorToNative(255,0,0)
);


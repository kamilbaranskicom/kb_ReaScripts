--[[
 * ReaScript Name: Studio Recording Lamp (with Energenie EG-PM1W-001 and curl)
 * Author: kamilbaranski.com
 * Licence: GPL v3
 * REAPER: 5.0
 * Extensions: None
 * Version: 1.0
--]]
 
--[[
 * Changelog:
 * v1.0 (2021-03-28)
   + Initial Release
--]]

--[[
 * todo:
   + toolbar button onInit/onExit with Get/SetToggleCommandState
   + README + installation howto (curl download, etc)
--]]

-- reaper.ShowConsoleMsg("\nScript launched.\n");

function setVariables()
  os = reaper.GetOS();
  if ((os == "Win64") or (os == "Win32")) then
    curlExePath = "C:\\curl\\bin\\curl.exe";
  else
    curlExePath = "/usr/bin/curl";
  end
    
  username = "admin";
  password = "XDWUjkhJ7gc7V7w";
  host = "http://192.168.50.72";
  path = "/goform/setSocket?gpionum=21&socket1=";
  turnOn = "1";
  turnOff = "0";
  q = "\"";
end

function updateLamp(playState)
  if (playState & 4 == 4) then
    turnOnOrOff = turnOn;
  else
    turnOnOrOff = turnOff;
  end

  fullCommandLine = curlExePath .. " -b " .. q .. "user=" .. username .. ";pass=" .. password .. q .. " " .. q .. host .. path .. turnOnOrOff .. q;
  
  result = reaper.ExecProcess(fullCommandLine, -2);
end

function onExit()
  reaper.SetToggleCommandState(sectionID,cmdID,0);
  reaper.RefreshToolbar2(sectionID,cmdID);
--  reaper.ShowConsoleMsg("\natExit\n\n");
end

function onInit()
  setVariables();
  is_new_value, filename, sectionID, cmdID, mode, resolution, val = reaper.get_action_context();
  
--  reaper.ShowConsoleMsg(cmdID .. ' ' .. sectionID .. ' ' .. reaper.GetToggleCommandState(cmdID) .. "\n");
  
--  if (reaper.GetToggleCommandState(cmdID) == 1) then
--    reaper.ShowConsoleMsg("\nturned on, let's kill it!\n\n");
--    reaper.SetToggleCommandState(sectionID,cmdID,0);
--    reaper.RefreshToolbar2(sectionID,cmdID);
--  else
--    reaper.ShowConsoleMsg("\nturned off, let's turn it on!\n\n");
    lastPlayState=0
    reaper.SetToggleCommandState(sectionID,cmdID,1);
    reaper.RefreshToolbar2(sectionID,cmdID);
    run();
--  end 
end

function run()
--  reaper.ShowConsoleMsg("run");
  local playState=reaper.GetPlayState() 
  if (playState & 4) ~= (lastPlayState & 4) then
    updateLamp(playState);
  end
  lastPlayState = playState;
  reaper.defer(run);
end

onInit();

reaper.atexit(onExit);

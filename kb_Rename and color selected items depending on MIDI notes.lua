--[[
 * ReaScript Name: Rename and color selected items depending on MIDI notes (kb_cue)
 * Author: kamilbaranski.com
 * Licence: GPL v3
 * REAPER: 5.0
 * Extensions: None
 * Version: 1.1
--]]
 
--[[
 * Changelog:
 * v1.0 (2022-09-26)
   + Initial Release
 * v1.1 (2023-02-27)
   + (fix) correct numbers in "remove spaces between numbers"
--]]

--[[
 * todo:
   + README
--]]

function run()
  cuesTexts = {
    [48] = "zwrotka", 
    [49] = "refren",
    [50] = "bridge", 
    [51] = "solo",
    [52] = "coda",
    [53] = "koniec",
    [54] = "intro",
    [55] = "łącznik",
    [56] = "modulacja",
    [57] = "drugaczęść",
    [58] = "special",
    [59] = "rozmycie",
    [60] = "piano",
    [61] = "bębny",
    [62] = "gitara",
    [63] = "bas",
    [64] = "sax",
    [65] = "dęciaki",
    [66] = "wokal",
    [67] = "instrumental",
    [68] = "break",
    [69] = "przedrefren",
    [70] = "akcenty",
    [71] = "powtórka",
    [72] = "chórki",
    [73] = "wszyscy",
    [74] = "tutti",
    [75] = "forte",
    [76] = "cicho",
    [77] = "ciszej",
    [78] = "głośno",
    [79] = "głośniej",
    [80] = "przyspieszenie",
    [81] = "zwolnienie",
    [82] = "halftime",
    [83] = "zmianatempa",
    [96] = "1",
    [97] = "2",
    [98] = "3",
    [99] = "4",
    [100] = "5",
    [101] = "6",
    [102] = "7",
    [103] = "8" }

  cuesColors = {
    [48] = {180, 200, 255},   -- "zwrotka", 
    [49] = {180, 255, 180},   -- "refren",
    [50] = {100, 100, 100},   -- "bridge", 
    [51] = {255, 150, 255},   -- "solo",
    [52] = {120, 120, 255},   -- "coda",
    [53] = {  0,   0, 255},   -- "koniec",
    [54] = {255, 255, 255},   -- "intro",
    [55] = {255, 255, 150},   -- "łącznik",
    [56] = {100, 100, 100},   -- "modulacja",
    [57] = {100, 100, 100},   -- "drugaczęść",
    [58] = {100, 100, 100},   -- "special",
    [59] = {255, 100, 100},   -- "rozmycie",
    [67] = {100, 100, 100},   -- "instrumental",
    [68] = {255, 200, 200},   -- "break",
    [69] = {100, 250, 200},   -- "przedrefren",
    [70] = {255, 100, 100},   -- "akcenty",
    [71] = {100, 100, 100},   -- "powtórka",
    [80] = {255, 100, 100},   -- "przyspieszenie",
    [81] = {255, 100, 100},   -- "zwolnienie",
    [82] = {255, 100, 100},   -- "halftime",
    [83] = {255, 100, 100}    -- "zmianatempa",
}

  count = reaper.CountSelectedMediaItems(0);
  if (count == 0) then
    return(0);
  end
  -- reaper.ShowConsoleMsg("Selected " .. count .. " items.\n");

  for itemIndex = 0, count-1 do
    name = "";
    newColor = {200,200,200};
    newColorSet = false;
    selectedItem = reaper.GetSelectedMediaItem(0, itemIndex)
    activeTake = reaper.GetActiveTake(selectedItem)
    
    retval, notes, ccs, sysex = reaper.MIDI_CountEvts(activeTake)
    for k = 0, notes-1 do
      retval, sel, muted, startppqposOut, endppqposOut, chan, pitch, vel = reaper.MIDI_GetNote(activeTake, k);
      
      if (muted == false) then
        name = name .. cuesTexts[pitch] .. " ";
      end

      if (cuesColors[pitch]) then
        if (newColorSet == false) then
          newColor = cuesColors[pitch];
          newColorSet = true;
        end
      end

     end
    
    -- remove spaces between numbers
    name = name:gsub("1 2", "12");
    name = name:gsub("2 3", "23");
    name = name:gsub("3 4", "34");
    name = name:gsub("4 5", "45");
    name = name:gsub("5 6", "56");
    name = name:gsub("6 7", "67");
    name = name:gsub("7 8", "78");
    reaper.GetSetMediaItemTakeInfo_String(activeTake, "P_NAME", name, true)

    --if newColor then
      newColorNative = reaper.ColorToNative(newColor[1],newColor[2],newColor[3])|0x1000000
    --end

    reaper.SetMediaItemInfo_Value(selectedItem, "I_CUSTOMCOLOR", newColorNative)
  end
end

run();


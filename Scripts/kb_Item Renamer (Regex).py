# @description Item renamer (Regex)
# @author Kamil Baranski (kamilbaranski.com)
# @version 1.0
# @about
#   Replaces occurrences matching a regex pattern in selected media items' names.
# @changelog
#   + Initial release

# Replaces any occurrence using regex pattern in the selected item's name field
from reaper_python import *
import re, string, sys 

undoBeginBock = lambda : RPR_Undo_BeginBlock2(0)
undoEndBlock = lambda name : RPR_Undo_EndBlock2(0, name, -1)

undoBeginBock(); 

proj = 0;
numitems = RPR_CountSelectedMediaItems(proj);

if numitems == 0:
  RPR_ShowMessageBox("No items selected!", "Item Renamer", 0)
else:
  res = RPR_GetUserInputs("Item Renamer (Regex)", 2, "Regex Pattern,  Replace With", "", 100)
  
  if res[0] != 0:
    pattern = res[4].partition(',')[0];
    replace = res[4].partition(',')[2];
    
    # Validate regex pattern
    try:
      compiled_pattern = re.compile(pattern)
    except re.error as e:
      RPR_ShowMessageBox(f"Invalid regex pattern: {str(e)}", "Regex Error", 0)
      undoEndBlock("Item Renamer (Regex)")
      sys.exit()
    
    # Convert $1, $2 syntax to \1, \2 for Python compatibility
    replace_converted = re.sub(r'\$(\d+)', r'\\\1', replace)
    
    for i in range(0, numitems):
      item = RPR_GetSelectedMediaItem(proj, i)
      take = RPR_GetActiveTake(item)
      
      if take:
        # Get current take name
        takename = RPR_GetTakeName(take)
        
        # Use regex substitution
        try:
          takename = re.sub(pattern, replace_converted, takename)
          RPR_GetSetMediaItemTakeInfo_String(take, "P_NAME", takename, True)
        except re.error as e:
          RPR_ShowMessageBox(f"Regex error on item '{takename}': {str(e)}", "Regex Error", 0)
          break

undoEndBlock("kb_Item Renamer (Regex)");

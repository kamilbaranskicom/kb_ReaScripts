#Replaces any occurence of [_name_] in the selected track's name field
from reaper_python import *
import re, string, sys 

undoBeginBock = lambda : RPR_Undo_BeginBlock2(0)
undoEndBlock = lambda name : RPR_Undo_EndBlock2(0, name, -1)

# Selection commands
unselectAllItems = lambda : RPR_Main_OnCommand(40297, 0) #Unselect all items
selectChildren = lambda : RPR_Main_OnCommand(RPR_NamedCommandLookup("_SWS_SELCHILDREN2"), 0) #Select children of selected folder track(s)
selectOnlyChildren = lambda : RPR_Main_OnCommand(RPR_NamedCommandLookup("_SWS_SELCHILDREN"), 0) #Select only children of selected folders
saveTrackSelection = lambda : RPR_Main_OnCommand(RPR_NamedCommandLookup("_SWS_SAVESEL"), 0) #Save current track selection
restoreTrackSelection = lambda : RPR_Main_OnCommand(RPR_NamedCommandLookup("_SWS_RESTORESEL"), 0) #Restore saved track selection

undoBeginBock(); 
saveTrackSelection();

proj = 0;
numtracks = RPR_CountSelectedTracks(proj);
# 4 input fields instead of 2. Using text fields as a workaround for lack of checkboxes.
res = RPR_GetUserInputs("Track Renamer", 4, "Search,Replace With,Ignore Case (1=Yes),Regex (1=Yes)", ",,,", 200)

for _ in range(0,1):
    proj = 0;
    if res[0] == 0:
        break;
    
    # Parse inputs. Note: This simple split will fail if user uses a comma in the regex/replace string.
    inputs = res[4].split(',')
    if len(inputs) < 4:
        break;

    search = inputs[0]
    replace = inputs[1]
    ignore_case = inputs[2].strip() == '1'
    use_regex = inputs[3].strip() == '1'
    
    # Prepare regex flags
    flags = re.IGNORECASE if ignore_case else 0

    if use_regex:
        # Validate regex pattern before processing tracks
        try:
            compiled_pattern = re.compile(search, flags)
        except re.error as e:
            RPR_ShowMessageBox(f"Invalid regex pattern: {str(e)}", "Regex Error", 0)
            break;
        
        # Convert $1, $2 syntax to \1, \2 for Python compatibility
        replace = re.sub(r'\$(\d+)', r'\\\1', replace)

    selectChildren();
    numtracks = RPR_CountSelectedTracks(proj);
    
    for i in range(0, numtracks):
        track = RPR_GetSelectedTrack(proj, i)
        trackname = RPR_GetSetMediaTrackInfo_String(track, "P_NAME", "", False)[3]
        
        if use_regex:
            try:
                trackname = re.sub(compiled_pattern, replace, trackname)
            except re.error as e:
                RPR_ShowMessageBox(f"Regex error on track '{trackname}': {str(e)}", "Regex Error", 0)
                break;
        else:
            if ignore_case:
                # Escape search to treat as literal, but use re.sub for case insensitivity
                pattern = re.compile(re.escape(search), flags)
                trackname = pattern.sub(replace, trackname)
            else:
                trackname = trackname.replace(search, replace);

        RPR_GetSetMediaTrackInfo_String(track, "P_NAME", trackname, True)
        
restoreTrackSelection();
undoEndBlock("Track Group Renamer");
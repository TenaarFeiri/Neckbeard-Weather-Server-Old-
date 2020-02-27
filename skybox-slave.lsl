integer sChan = -1111;//-235799; // The channel we send the sky data to.
integer cChan = -2222; // Channel for talking to the station.
string descKey = "{ahg81332-11er-3221-agt3-8tyo2d004333}"; // For authentication.

string curW; // Store the weather value.
string curT = NULL_KEY;

default
{
    state_entry()
    {
        llListen(sChan, "", "", "");
        llRegionSay(cChan, "weather");
    }

    on_rez(integer s) {
        llRegionSay(sChan, "weather");
    }

    listen(integer c, string n, key id, string m) {

        if(llList2String(llGetObjectDetails(id, [OBJECT_DESC]), 0) == descKey) {
            list tmp = llParseString2List(m, ["|"], [""]);
            if(m != curW + "|" + curT) {
                if(curW != llList2String(tmp, 0)) {
                    curW = llList2String(tmp, 0);
                    
                }
                curT = llList2String(tmp, 1);
                
                llSetTexture(curT, 1);
            }
        }
    }
}
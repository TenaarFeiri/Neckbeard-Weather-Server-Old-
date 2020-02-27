//
// Weatherstation Server v5.7.11
//
// Tenaar Feiri
// Started: 28. July 2013
// Finished: 02. August 2013
// Full script rewrite for the weather station.
//
// Goals:
//  - Increase efficiency. [-] NOTE: New station is much heavier due to increased customization options.
//  - Add features such as more customizeable temps, & wind measurement. [x]
//  - Make weather progress more believably and reliably. [x]
//  - Allow notecard customization of weathers. [x]
//  - Retain full backwards compatibility with current slave scripts. [x]
//

// Changelog 5.7.7: Added pagination.

// Changelog 5.7.8: Adjusted the season values to be more realistic.

//######################
// Changelog 5.7.9
// - Changed the weather station's selection rate to happen more slowly.
// - Added modifiers to further reduce the frequency at which bad weathers occur...
//
// Changelog 5.7.10
//  - Further adjusted the selection of bad weather conditions.
//
// Changelog 5.7.11
//  - Actually fixed bad weathers =P
//
//######################

integer DEBUG = FALSE; // Set to false when done writing the script.

string version = "5.7.11";

float timerInt = 5.0; // Timer delay. Default to 5.0

// Communication channels \\

integer menu_Handler; // Handles the menu.
integer menu_Channel;
integer menu_Channel_Debug = -3333;
integer force_Handler;
integer force_Channel = -6121321;
integer force_Channel_Debug = -4444;
integer motd_Handler;
integer motd_Channel;
integer motd_Channel_Debug = -5555;
integer lastCommand; // Used for keeping track of when was the last use of the station.
integer timeOut = 120; // Timeout value for channel handlers.
key user; // Current user.

integer sChan = -235799; // The channel we send the sky data to.
integer cChan = -235798; // Channel for talking to the station.


// Modifiable variables \\

// Lists all weather conditions + textures.
//
// Modified by notecard.
list weather_Spring; // Spring weathers.
list weather_Summer; // Summer weathers.
list weather_Autumn; // Autumn weathers.
list weather_Winter; // Winter weathers.
list currentSeason;
list bad_Weathers; // Complete reference list of bad weathers.
list moderators; // Who are allowed to operate this station.

// Weather-specific vars.
integer lastChange; // When did the weather change last?
integer nextChange; // When will the weather change next?
float minChange = 10800.00; // Minimum waiting time (in seconds) until weather changes.
float maxChange = 32400.00; // Maximum waiting time (in seconds) until the weather changes.
integer bad; // Can we have bad weather next change?
string currentWeather = "Disabled."; // What is our weather?
integer forced; // Is our weather forced?
integer bad_canceled;

string season; // Which season is it?

string motd; // Short message for the weather buttons.


// Wind directions
list wind_Dir = ["N", "NW", "NE", "E", "W", "S", "SW", "SE"];
integer windDirC;
integer windDirL;
string windDirS;


// Menu lists \\

list menu_Main = [
    "Start",
    "Stop",
    "Load config",
    "Reset",
    "Force Weather",
    "MOTD"
        ];

list menu_Force_Num(list cur_Season) // Parses all weathers into correctly ordered lists.
{
    list temp;
    integer i = (llGetListLength(cur_Season) - 1);
    integer x = 0;
    for(;x<=i;x++)
    {
        // Parse only the weather names to the returned list.
        temp += [(string)(x+1)+": "+llList2String(llParseString2List(llList2String(cur_Season, x), ["|"], []),0)];
    }

    return temp; // When we're done with the loop, do return!
}




// Misc. Vars \\

key weatherQuery; // For querying weather data.
integer line; // Our line.
integer parseWeather; // When temperature offset has been defined.
string whichWeather; // For keeping track of which list to update.

float temp_Offset = 100.00; // Temperature offset.
string temperature; // Contains the temperature.

string wind_Data; // Contains wind data.

string output; // Output string for the station.

integer ready; // When ready to run, this is set to TRUE.

string loaded_set; // Remembers the loaded weather set.

integer memory = 6; // For memory limiting.

string descKey = "{ahg81332-11er-3221-agt3-8tyo2d004333}"; // ID key.

string hudTex = "71b3d333-5c3b-b71b-3c1a-aa8dbf49a708"; // Current HUD texture set.

string skyTex = "1b8cafd0-e097-6753-3380-8e7924bbef12"; // Current sky texture set.

integer forceNum = -1; // Which number in the list we're using.

integer inUse; // For when we are in use!


// Functions \\

list paginateList( integer vIdxPag, list cards ){ // Handles listing of paginated lists.
    list vLstRtn;
    if ((cards != []) > 12){ //-- we have more than one possible page
        integer vIntTtl = -~((~([] != cards)) / 10);                                 //-- Total possible pages
        integer vIdxBgn = (vIdxPag = (vIntTtl + vIdxPag) % vIntTtl) * 10;              //-- first menu index
        string  vStrPag = llGetSubString( "                     ", 21 - vIdxPag, 21 ); //-- encode page number as spaces
        //-- get ten (or less for the last page) entries from the list and insert back/fwd buttons
        vLstRtn = llListInsertList( llList2List( cards, vIdxBgn, vIdxBgn + 9 ), (list)(" <" + vStrPag), 0xFFFFFFFF ) +(list)(" >" + vStrPag);
    }else{ //-- we only have 1 page
            vLstRtn = cards; //-- just use the list as is
    }
    return //-- fix the order for [L2R,T2B] and send it out
        llList2List( vLstRtn, -3, -1 ) + llList2List( vLstRtn, -6, -4 ) +
        llList2List( vLstRtn, -9, -7 ) + llList2List( vLstRtn, -12, -10 );
}

addToList(string data) // To add data to the lists.
{
    if(data == "" || data == "¶" || data == " " || data == "
        ")
            return;



    if( ~llSubStringIndex(data, "#") ) // If there's a # anywhere in the line...
    {
        data = llDeleteSubString(data, llSubStringIndex(data, "#"), -1); // ...delete and ignore it and everything after it.
    }
    //llOwnerSay(data);
    if( ~llSubStringIndex(llToLower(whichWeather), "spring") )
    {
        weather_Spring += [(string)data];
    }
    else if( ~llSubStringIndex(llToLower(whichWeather), "summer") )
    {
        weather_Summer += [(string)data];
    }
    else if( ~llSubStringIndex(llToLower(whichWeather), "autumn") )
    {
        weather_Autumn += [(string)data];
    }
    else if( ~llSubStringIndex(llToLower(whichWeather), "winter") )
    {
        weather_Winter += [(string)data];
    }
    else if( ~llSubStringIndex(llToLower(whichWeather), "bad weathers") )
    {
        bad_Weathers += [(string)data];
    }
    else if( ~llSubStringIndex(llToLower(whichWeather), "moderators") )
    {
        moderators += [(string)data];
    }
}


forceWeather(list cur_Season, key ID, integer method, integer num)
{
    if(method == 0)
    {
        list tmp;
        //string tmp2;
        integer i = (llGetListLength(currentSeason) - 1);
        /*if(i>12)
        {
            llInstantMessage(ID, "More than 12 weather entries detected. Weather forcing canceled.");
            return;
        }*/
        integer x;
        for(x=0;x<=i;x++)
        {
            tmp += [(string)(x+1)];
        }
        bad = FALSE;
        force_Handler = llListen(force_Channel, "", ID, "");
        llDialog(ID, "Select your weather:\n" + llDumpList2String(menu_Force_Num(currentSeason), "\n"), paginateList(0, tmp+["CANCEL"]), force_Channel);
    }
    else if(method == 1)
    {
        list tmp = currentSeason;
        tmp = llParseString2List(llList2String(tmp, num), ["|"], []);
        currentWeather = llList2String(tmp, 0);
        if(llListFindList(bad_Weathers, [currentWeather]) >= 0)
        {
            bad = TRUE;
            if(DEBUG)
                llSay(0, "!");
        }
        else
        {
            bad = FALSE;
            if(DEBUG)
                llSay(0, "#");
        }
        temp_Offset = llList2Float(tmp, -1);
        lastChange = llGetUnixTime();
        nextChange = (integer)(llFrand(maxChange));
        if(nextChange < (integer)minChange)
        {
            nextChange = (integer)minChange;
        }
        forced = TRUE;
        llSetTimerEvent(1.0);

    }
}


integer Key2AppChan(key ID, integer App) { // Generates a unique channel per key, with additional app modifier.
    return 0x80000000 | ((integer)("0x"+(string)ID) ^ App);
}

process_inventory_items() // Handles inventory management.
{
    llSetTimerEvent(0);
    ready = FALSE;
    integer i = (llGetInventoryNumber(INVENTORY_ALL) - 1); // Get the total number of inventory items.
    integer x; // This we'll use to loop.
    integer foreign;
    for(x=0;x<=i;x++) // Begin the loop.
    {
        // Check the inventory type.
        if((llGetInventoryType(llGetInventoryName(INVENTORY_ALL, x)) != INVENTORY_NOTECARD) & (llGetInventoryType(llGetInventoryName(INVENTORY_ALL, x)) != INVENTORY_SCRIPT))
        { // If it's not a notecard or a script, do the thing.
            foreign = TRUE;
            if(llGetInventoryType(llGetInventoryName(INVENTORY_ALL, x)) == INVENTORY_SCRIPT && llGetInventoryName(INVENTORY_ALL, x) != llGetScriptName())
            { // If the scripts detected do not match the name of this script...
                llRemoveInventory(llGetInventoryName(INVENTORY_ALL, x)); // Remove it.
            }
            else if(llGetInventoryType(llGetInventoryName(INVENTORY_ALL, x)) != INVENTORY_NOTECARD)
            { // If inventory type then isn't a notecard, delete it outright.
                llRemoveInventory(llGetInventoryName(INVENTORY_ALL, x));
            }

        }
    }
    if(foreign)
    {
        llSay(0, "One or more foreign inventory items were detected & successfully removed.");
    }

    llSay(0, "Parsing notecard: " + loaded_set);
    llSetMemoryLimit((64*1024));
    // Clear out ALL lists!
    weather_Spring = (weather_Summer=[])+(weather_Autumn=[])+(weather_Winter=[])+(moderators=[])+[];
    line = 0; // clear the lines.
    weatherQuery = llGetNotecardLine(loaded_set, line++); // Then query the last loaded set.
}

// Function to calculate the numeric day of year
integer dayOfYear(integer year, integer month, integer day)
{
    return day + (month - 1) * 30 + (((month > 8) + month) / 2)
        - ((1 + (((!(year % 4)) ^ (!(year % 100)) ^ (!(year % 400))) | (year <= 1582))) && (month > 2));
}

whatSeason() // Returns the correct list for the season. Also handles when they change.
{
    list dateComponents = llParseString2List(llGetDate(), ["-"], []);
    integer year  = (integer) llList2String(dateComponents, 0);
    integer month = (integer) llList2String(dateComponents, 1);
    integer day   = (integer) llList2String(dateComponents, 2);


    if(dayOfYear(year, month, day) >= 354 || dayOfYear(year, month, day) <= 52) // Winter.
    {
        season = "Winter";
    }
    else if(dayOfYear(year, month, day) >= 264) // Autumn
    {
        season = "Autumn";
    }
    else if(dayOfYear(year, month, day) >= 171) // Summer.
    {
        season = "Summer";
    }
    else if(dayOfYear(year, month, day) >= 53) // Spring.
    {
        season = "Spring";
    }

}

curSeason() // Returns the correct list for the season. Also handles when they change.
{

    if(season == "Spring")
    {
        currentSeason = weather_Spring;
    }
    else if(season == "Summer")
    {
        currentSeason = weather_Summer;
    }
    else if(season == "Autumn")
    {
        currentSeason = weather_Autumn;
    }
    else if(season == "Winter")
    {
        currentSeason = weather_Winter;
    }

}

// Function for handling weather selection.
selectWeather(list cur_Season) // Selects the weather of the current season & updates the output string.
{
    
    
    if(!ready && !forced)
    {
        currentWeather = "Disabled.";
        hudTex = "71b3d333-5c3b-b71b-3c1a-aa8dbf49a708";
        skyTex = "1b8cafd0-e097-6753-3380-8e7924bbef12";
        return;
    }
    else if(ready && forced)
    {
        forced = FALSE;
    }
    
    if(!forced)
    {
        if(llGetUnixTime() > (lastChange + nextChange)) // If we're ready to do the next change, run it.
        {
            
            @reDo;
            // First, select the weather.
    
                integer i = (llGetListLength(cur_Season) - 1); // Get all list entries.
                integer random = (integer)llFrand((float)i); // Then pick a random number between 0 & i.
                if(random > i) // If the number is HIGHER than i, set it to i.
                {
                    random = i;
                }
    
            
            // Then select the list entry.
            string temporary = llList2String(cur_Season, random);
            
            // Then let's parse that into a new list.
            list tmp = llParseString2List(temporary, ["|"], []);
            
            // Redo the thing if it turns out it's selected a bad weather but we're not presently able to have one.
            if(llListFindList(bad_Weathers, [llList2String(tmp, 0)]) != -1 && bad < 2)
            {
                if(bad >= 1)
                {
                    ++bad_canceled;
                }
                if(bad_canceled >= 2)
                {
                    ++bad;
                }
                else
                {
                    jump reDo;
                }
                jump reDo;
            }
            else if(llListFindList(bad_Weathers, [llList2String(tmp, 0)]) != -1 && bad >= 2) // Otherwise, we're having a bad weather.
            {
                //bad = 0;
                //bad_canceled = 0;
                ++bad;
            }
            else if(llListFindList(bad_Weathers, [llList2String(tmp, 0)]) == -1 && bad >= 1) // If we're not having a bad weather, subtract bad and bad_canceled.
            {
                //bad = 0;
                //bad_canceled = 0;
                --bad;
                if(bad_canceled >= 1)
                {
                    --bad_canceled;
                }
            }
            if(llGetSubString(llList2String(tmp, 0), 0, 0) == "!") // If the bad weather flag is on...
            {
                ++bad; // enable bad weather next run.
            }
            else if(bad >= 3 || bad_canceled >= 3)
            {
                bad = 0;
                bad_canceled = 0;
            }
            temp_Offset = llList2Float(tmp, -1); // Set the temperature offset.
            
            // Let's update some vars!
        
        
            // With that out of the way, let's update the weather.
            if(currentWeather != llList2String(tmp, 0)) // If the chosen weather is not identical to the one we had...
            {
                currentWeather = llList2String(tmp, 0);
            }
            lastChange = llGetUnixTime();
            nextChange = (integer)(llFrand(maxChange));
            if(nextChange < (integer)minChange)
            {
                nextChange = (integer)minChange;
            }
        }

        }
        else
        {
            // Then select the list entry.
            string temporary = llList2String(cur_Season, forceNum);
            
            // Then let's parse that into a new list.
            list tmp = llParseString2List(temporary, ["|"], []);
            temp_Offset = llList2Float(tmp, -1); // Set the temperature offset.
        }

        integer i = (llGetListLength(cur_Season) - 1); // Get the list length again.
        integer x; // X = 0
        string temp;
        list tmp;
        for(x=0;x<=i;x++) // Initiate loop.
        {
            temp = llList2String(cur_Season, x); // Put each entry into the temporary string.
            tmp += [(string)llList2String(llParseString2List(temp, ["|"], []), 0)]; // Then parse that string back into a list.
        }
        // Then find the correct entry.
        i = llListFindList(tmp, [(string)currentWeather]);
        if(i == -1)
        {
            llOwnerSay("Error."); // Error out of it doesn't work.
            return;
        }
        else // But if it works...
        {
            tmp = llList2List(llParseString2List(llList2String(cur_Season, i), ["|"],[]), 0, -1); // Reparse the original list entry into the temporary list.
            // Then the texture manager can find it.
        }
    
    // Let's check if it's night or day.
    vector sun = llGetSunDirection();

    if (sun.z <= 0) 
    { // Sun is below the horizon.
        integer i = (llGetListLength(tmp) - 2);
        // Set HUD texture to the nighttime one.
        hudTex = llList2String(tmp, i); // It will always be the last.
        
        // Then set the Sky texture.
        skyTex = llList2String(tmp, 2);
    }

    else if (sun.z > 0) 
    { // If sun is above the horizon...
        
        // Then we set the HUD texture to the day one. It will always be second to last, but let's be sure!
        integer i = (llGetListLength(tmp) - 3);
        hudTex = llList2String(tmp, i);
        
        // Then set the sky texture correctly.
        skyTex = llList2String(tmp, 1); // It will always be the first one after the weather itself.
    }
    
    
}




// Function for measuring weather & wind.
measureConditions()
{

    if(!ready && !forced)
    {
        temperature = "";
        return;
    }
    string tmp;
    string tmp2;
    vector sun = llGetSunDirection();
    vector pos = llGetPos();
    float base = llLog10(5- ((pos.z - llWater(ZERO_VECTOR))/15500));
    float pascal = (temp_Offset + base);
    float temperatureF = ((((pascal * (2 * llPow(10,22)))/
        (1.8311*llPow(10,20))/ 8.314472)/19.85553747) + (sun.z * 10));
    float temperatureC = (temperatureF - 32);
    temperatureC = (temperatureC * 5);
    temperatureC = (temperatureC / 9);
    integer strInx = llSubStringIndex((string)temperatureC, ".");
    tmp2 = llGetSubString((string)temperatureC, 0, (strInx + 1));
    tmp = "\n" + tmp2 + "°C / ";
    strInx = llSubStringIndex((string)temperatureF, ".");
    tmp2 = llGetSubString((string)temperatureF, 0, (strInx + 1));
    tmp += tmp2 + "°F";

    temperature = tmp;

    vector wind = llWind(ZERO_VECTOR);

    string speed = (string)llVecMag(wind);
    speed = llDeleteSubString(speed, (llSubStringIndex(speed, ".") + 2), -1);
    temperature += "\n" + "Wind: " + speed + " m/s, ";


    if(llGetUnixTime() > (windDirL + windDirC))
    {
        integer select = (integer)(llFrand((float)llGetListLength(wind_Dir)) - 1.0);
        windDirS = llList2String(wind_Dir, select);
        windDirL = llGetUnixTime();
        windDirC = (integer)llFrand(3600);
        if(windDirC < 1300)
            windDirC = 1300;
    }
    temperature += windDirS+".";




}



// EXECUTE PROGRAM \\

default
{
    // Handles all initial setup of the program. Loads the first notecard in the inventory by default.
    state_entry()
    {

        llOwnerSay("Weather station is starting up in " + llGetRegionName() + ". You're receiving this message because you're either installing the station, or it was reset for some reason.");

        // Begin config. \\
        if(DEBUG) // If we're in debug mode....
        {
            // Use the debug channels.
            menu_Channel = Key2AppChan(llGetOwner(), 1);
            force_Channel = Key2AppChan(llGetOwner(), 2);
            motd_Channel = Key2AppChan(llGetOwner(), 3);
            sChan = -1111;
            cChan = -2222;
        }
        else // Otherwise...
        {
            // Generate a unique negative channel.
            menu_Channel = Key2AppChan(llGetOwner(), 1);
            force_Channel = Key2AppChan(llGetOwner(), 2);
            motd_Channel = Key2AppChan(llGetOwner(), 3);
        }
        string tmp = currentWeather + "|" + hudTex + "|" + temperature;
        if(llGetSubString(tmp, 0, 0) == "!")
        {
            tmp = llDeleteSubString(tmp, 0, 0);
        }
        llRegionSay(cChan, tmp + "\n" + motd);
        llRegionSay(sChan, currentWeather + "|" + skyTex);

        whatSeason();
        llSetObjectDesc(descKey);

        // Once this is done, say it out loud!
        llSay(0, "Channels configured.");

        if(llGetInventoryNumber(INVENTORY_NOTECARD) == 0)
        {
            llSay(0, "No notecards in inventory.");
            return;
        }
        // Read the notecard. \\
        llSay(0, "Reading notecard...");
        loaded_set = llGetInventoryName(INVENTORY_NOTECARD, 0);
        weatherQuery = llGetNotecardLine(loaded_set, line++);
    }


    // Start processing user-interface.
    touch_end(integer total_number)
    {

        //llOwnerSay(llKey2Name(llDetectedKey(0))); // debug
        list name = llParseString2List(llKey2Name(llDetectedKey(0)), [" "], []);
        string fixedName = llDumpList2String(name, " ");
        //llOwnerSay(fixedName); // debug
        if(llListFindList(moderators, [fixedName]) != -1 || llDetectedKey(0) == llGetOwner()) // For development so people can't fuck shit up.
        {
            if(inUse && llDetectedKey(0) != user)
            {
                llSay(0, "I am currently in use by secondlife:///app/agent/"+(string)user+"/about"+".");
                return;
            }
            user = llDetectedKey(0);
            list dateComponents = llParseString2List(llGetDate(), ["-"], []);
            integer year  = (integer) llList2String(dateComponents, 0);
            integer month = (integer) llList2String(dateComponents, 1);
            integer day   = (integer) llList2String(dateComponents, 2);
            llDialog(user, "Weatherstation V"+version+"\n\nDay of year: "+(string)dayOfYear(year, month, day)+", "+season+".\n"+"\nSpring begins on day 53\nSummer begins on day 171\nAutumn begins on day 264\nWinter begins on day 354", menu_Main, menu_Channel);
            menu_Handler = llListen(menu_Channel, "", user, "");
            inUse = TRUE;
            lastCommand = llGetUnixTime();

        }

    }

    listen(integer c, string n, key id, string m)
    {

        if(c == menu_Channel)
        {
            if(m == "Start")
            {
                lastChange = 0;
                nextChange = 0;
                llSay(0, "Started!");
                ready = TRUE;
                inUse = FALSE;
                forced = FALSE;
            }
            else if(m == "Stop")
            {
                llSay(0, "Stopped!");
                ready = FALSE;
                inUse = FALSE;
                forced = FALSE;
            }
            else if(m == "Reset")
            {
                llOwnerSay("Resetting!");
                llResetScript();
            }
            else if(m == "Load config")
            {
                list tmp;
                integer i = (llGetInventoryNumber(INVENTORY_ALL) - 1);
                integer x;
                for(x=0;x<=i;x++)
                {
                    if(llGetInventoryType(llGetInventoryName(INVENTORY_ALL, x)) == INVENTORY_NOTECARD)
                    {
                        tmp += [llGetInventoryName(INVENTORY_ALL, x)];
                    }
                }
                llDialog(id, "Select notecard:", tmp, menu_Channel);
                lastCommand = llGetUnixTime();
            }
            else if(m == "Force Weather")
            {
                forceWeather(currentSeason, id, 0, 0);
                lastCommand = llGetUnixTime();
            }
            else if(m == "MOTD")
            {
                motd_Handler = llListen(motd_Channel, "", id, "");
                llListenRemove(menu_Handler);
                lastCommand = llGetUnixTime();
                llTextBox(id, "Set new MOTD here. Set 'hide' to hide.\nCurrent MOTD:"+motd, motd_Channel);
            }
            else
            {
                if(llGetInventoryType(m) == INVENTORY_NOTECARD)
                {
                    llSetTimerEvent(0.0);
                    lastChange = 0;
                    nextChange = 0;
                    loaded_set = m;
                    process_inventory_items();
                    inUse = FALSE;
                    llListenRemove(menu_Handler);
                    user = NULL_KEY;
                }
            }
        }
        else if(c == force_Channel)
        {
            if(m == "CANCEL")
            {
                return;
            }
            if(!llSubStringIndex(m, " "))
            {
                list tmp;
                integer i = (llGetListLength(currentSeason) - 1);
                integer x;
                for(x=0;x<=i;x++)
                {
                    tmp += [(string)(x+1)];
                }
                llDialog(user, "Select your weather:\n" + llDumpList2String(menu_Force_Num(currentSeason), "\n"), paginateList((llStringLength(m) + llSubStringIndex(m, ">>") - 2), tmp+["CANCEL"]), force_Channel);
                return;
            }
            forceNum = (integer)((integer)m-1);
            lastChange = 0;
            nextChange = 0;

            forceWeather(currentSeason, id, 1, forceNum);
            llListenRemove(force_Handler);
            inUse = FALSE;
            user = NULL_KEY;
        }
        else if(c == motd_Channel)
        {
            if(llToLower(m) == "hide")
            {
                motd = "";
            }
            else
            {
                motd = m;
            }
            inUse = FALSE;
            llListenRemove(motd_Handler);
            user = NULL_KEY;
        }
    }

    timer()
    {
        llSetTimerEvent(0);
        llSetObjectDesc(descKey);
        //string tmp2;
        whatSeason();
        curSeason();
        selectWeather(currentSeason);
        measureConditions();
        string tmp = currentWeather + "|" + hudTex + "|" + temperature;
        if(llGetSubString(tmp, 0, 0) == "!")
        {
            tmp = llDeleteSubString(tmp, 0, 0);
        }
        llRegionSay(cChan, tmp + "\n" + motd);
        llRegionSay(sChan, llList2String(llParseString2List(tmp, ["|"],[]),0) + "|" + skyTex);
        if(DEBUG)
        {
            llOwnerSay("Bad: " + (string)bad + ", bad_canceled: " + (string)bad_canceled);
        }
        //llOwnerSay(skyTex);
        if(llGetUnixTime() >= (lastCommand + timeOut) && inUse)
        {

            llSay(0, "secondlife:///app/agent/"+(string)user+"/about"+"'s session has timed out.");
            user = NULL_KEY;
            llListenRemove(menu_Handler);
            llListenRemove(force_Handler);
            llListenRemove(motd_Handler);
            inUse = FALSE;
        }
        llSetTimerEvent(timerInt);
    }


    // Dataserver event for quering notecards.
    dataserver(key query, string data)
    {
        if(query == weatherQuery)
        {

            if(data == EOF)
            {
                //llOwnerSay(llDumpList2String(moderators, ", ")); // debug
                whichWeather = "";
                parseWeather = FALSE;
                line = 0;
                curSeason();
                ready = TRUE;
                llSay(0, (string)(llGetUsedMemory() / 1024)+"KB Memory used.");
                llSetMemoryLimit( ( llGetUsedMemory() + ( memory + (4*1024) ) ) );
                llSay(0, "Configurations complete. Touch for menu.");
                llSetTimerEvent(1.0);


            }
            else
            {
                if(data != "" && data != "¶" && data != " ") {

                    if( ~llSubStringIndex(data, "[") )
                    {
                        //llOwnerSay(data);
                        whichWeather = data;
                        parseWeather = TRUE;
                    }
                    else if(data != "" && data != " " && parseWeather)
                    {

                        addToList(data);

                    }
                }
                weatherQuery = llGetNotecardLine(loaded_set, line++);
            }

        }
    }


    // This changed event keeps track of what changes are made to the script.
    changed(integer change)
    {

        // If we have a new owner, reset.
        if(change & CHANGED_OWNER)
        {
            llResetScript();
        }

        // If the inventory has changed in any way, loop through it. Anything that's not this script, or a notecard must be deleted.
        if(change & CHANGED_INVENTORY)
        {
            process_inventory_items();
            //llSay(0, "Inventory has changed. Please re-load a card.");
        }

    }
}

--[[
* lodfix - Always draw zone objects at full detail.
*
* WHAT IT DOES
* ------------
* FFXI draws most of a zone's scenery (trees, buildings, walls, rocks, ...)
* as "zone objects". Each zone object can carry up to three versions of its
* model, from most to least detailed. Every frame, for every visible object,
* the game measures how far the object is from the camera and picks one of the
* three. Walking toward an object makes it "pop" when the game switches to a
* more detailed version.
*
* This addon makes the game always pick the version it would use if the
* camera were right next to the object, at any distance. Detail never drops,
* so nothing pops.
*
* Unloading the addon puts the game's code back exactly as it was.
*
* WHAT IT DOES NOT CHANGE
* -----------------------
*  - How far away things are drawn at all. That is a separate check, which is
*    what the standard 'drawdistance' addon adjusts. This addon does not touch
*    it, so the two work together.
*  - Characters, NPCs and monsters. They are drawn by different code.
*  - Texture sharpness at a distance (mipmapping). That is a graphics setting,
*    not a model choice.
*
* No new models or textures are loaded: every version of every object is
* already in memory once the zone has loaded. The cost is that the GPU draws
* the detailed versions of distant objects, which can lower the frame rate on
* weaker graphics hardware.
*
* HOW THE GAME CHOOSES A MODEL
* ----------------------------
* The choice is made in FFXiMain.dll. Written as Lua, it is:
*
*     local d2 = squared distance from the camera to the object
*     if     d2 > obj.far_limit then model = obj.far_model     -- least detail
*     elseif d2 > obj.mid_limit then model = obj.mid_model
*     else                           model = obj.near_model    -- most detail
*     end
*     if model == nil then skip the object (draw nothing) end
*
* In memory, each object keeps far_limit at +0xCC, mid_limit at +0xC8, and the
* three model slots at +0x10 (far), +0x14 (mid) and +0x18 (near).
*
* ("Squared" distance just avoids a square root; comparing squares gives the
* same answer.) The limits and the three model slots belong to each object and
* come from the zone's data files.
*
* A slot can be empty on purpose. Some zones use cheap "stand-in" objects for
* distant views, for example a flat wall painted to look like the inside of a
* tunnel. Their near slot is empty, so the game stops drawing them as you get
* close and the real geometry behind them shows instead.
*
* WHAT THE PATCH CHANGES
* ----------------------
* The addon makes the game use 0 for d2 in the two comparisons above. A
* distance of 0 is never greater than either limit, so the game always falls
* through to the near model, exactly as if the camera were touching the
* object:
*
*  - Objects with a near model always use it.
*  - Stand-in objects (empty near slot) stay hidden, exactly as they are up
*    close, so they can never cover the real geometry.
*
* This is a deliberate choice. An earlier version picked "the first model slot
* that isn't empty" instead, which drew the stand-ins up close and plugged
* tunnel entrances. Letting the game decide from distance 0 avoids that.
*
* THE MACHINE CODE
* ----------------
* FFXI does this math on the x87 floating-point unit, which works like a small
* stack of numbers. Each comparison in the game is these two instructions:
*
*     D9 44 24 xx           fld   dword [esp+xx]      push d2 onto the stack
*     D8 99/9F off32        fcomp dword [obj+off]     compare it with a limit,
*                                                     then pop it off
*
* followed by a few instructions that copy the comparison result into a
* register and jump to the next check if d2 is not greater than the limit.
*
* The patch replaces only the first one, with an instruction that pushes 0.0
* instead of d2:
*
*     D9 EE                 fldz                      push 0.0
*     90 90                 nop nop                   do nothing (padding)
*
* Both versions are 4 bytes long and leave the stack the same depth, so
* nothing around them is disturbed. 'fcomp' still pops the value and the game
* still reads the result the same way. d2 itself is never modified (the patch
* only stops it from being loaded here), so any other code that uses it still
* sees the real distance. No code is added anywhere; four 4-byte patches are
* the whole change.
*
* There are two copies of the model-choice code (the game draws zone objects
* in two passes), each with two comparisons, so there are four patch sites.
*
* HOW THE CODE IS FOUND
* ---------------------
* The DLL's address in memory can change from run to run, so the code is found
* by searching memory for its exact bytes (a "signature"), the same way the
* standard 'drawdistance' addon finds its values. Each signature is the first
* comparison of a copy plus the instructions after it, which is unique in the
* DLL. Before writing anything the addon checks that all four sites are found
* and contain the expected original bytes. If anything doesn't match (for
* example after a client update) it changes nothing and says so.
*
* For reference, in the client build this was written against, FFXiMain.dll
* loaded at 0x04460000 and the two copies were at 0x045DCB69 and 0x045DDFDE.
* The addon does not rely on these addresses.
--]]

addon.name    = 'lodfix';
addon.author  = 'john';
addon.version = '3.0';
addon.desc    = 'Always draws zone objects (trees, buildings, ...) at full detail, so they no longer pop.';
addon.link    = '';

require 'common';

--[[
* The two copies of the model-choice code.
*
*   pattern  The bytes to search for (hex). Starts at the first comparison.
*   loads    Offsets, from the start of the match, of the two 'fld' instructions
*            that load d2 (one before each comparison).
*   original The 4 bytes expected at each of those offsets.
*
* Copy 1 (first drawing pass). d2 is kept at [esp+0x14], the object is in ecx:
*   +0x00  D9 44 24 14          fld   [esp+0x14]
*   +0x04  D8 99 CC 00 00 00    fcomp [ecx+0xCC]     compare with far limit
*   +0x0A  DF E0                fnstsw ax            copy the compare result
*   +0x0C  25 00 41 00 00       and   eax, 0x4100    keep "less" and "equal" bits
*   +0x11  75 05                jnz   +0x18          not farther: next check
*   +0x13  8B 59 10             mov   ebx, [ecx+0x10]  far model
*   ...
*   +0x18  D9 44 24 14          fld   [esp+0x14]
*   +0x1C  D8 99 C8 00 00 00    fcomp [ecx+0xC8]     compare with mid limit
*   ...                                              mid model [ecx+0x14], or
*                                                    near model [ecx+0x18]
*
* Copy 2 (second drawing pass). d2 is kept at [esp+0x58], the object is in edi:
*   +0x00  D9 44 24 58          fld   [esp+0x58]
*   +0x04  D8 9F CC 00 00 00    fcomp [edi+0xCC]     compare with far limit
*   ...
*   +0x1C  D9 44 24 58          fld   [esp+0x58]
*   +0x20  D8 9F C8 00 00 00    fcomp [edi+0xC8]     compare with mid limit
--]]
local copies = {
    {
        pattern  = 'D9442414D899CC000000DFE025004100007505',
        loads    = { 0x00, 0x18 },
        original = { 0xD9, 0x44, 0x24, 0x14 },
    },
    {
        pattern  = 'D9442458D89FCC000000DFE02500410000',
        loads    = { 0x00, 0x1C },
        original = { 0xD9, 0x44, 0x24, 0x58 },
    },
};

-- The replacement for each 'fld [esp+xx]': fldz, nop, nop.
local replacement = { 0xD9, 0xEE, 0x90, 0x90 };

-- Addresses that were patched, so unload can put the original bytes back.
-- Each entry: { address = <number>, original = { 4 bytes } }
local patched = {};

-- Write a list of bytes to memory, starting at 'address'.
local function write_bytes(address, bytes)
    for i = 1, #bytes do
        ashita.memory.write_uint8(address + i - 1, bytes[i]);
    end
end

-- True if the bytes in memory at 'address' equal the list 'bytes'.
local function bytes_match(address, bytes)
    for i = 1, #bytes do
        if ashita.memory.read_uint8(address + i - 1) ~= bytes[i] then
            return false;
        end
    end
    return true;
end

-- Find all four sites, check them, then patch them. Changes nothing unless
-- every site is found and holds the expected original bytes.
local function apply_patch()
    -- Code memory is normally read-only. ashita.memory.unprotect makes it
    -- writable. Without it, writing would crash the game, so stop here.
    if type(ashita.memory.unprotect) ~= 'function' then
        print('[lodfix] This version of Ashita cannot unprotect code memory. Nothing was changed.');
        return false;
    end

    -- Step 1: locate and verify every site before touching anything.
    local sites = {};
    for _, copy in ipairs(copies) do
        -- Search FFXiMain.dll for the signature. Returns 0 if not found.
        local match = ashita.memory.find(0, 0, copy.pattern, 0, 0);
        if match == 0 then
            print('[lodfix] Could not find the game code to patch (client update, or lodfix already active?). Nothing was changed.');
            return false;
        end

        for _, offset in ipairs(copy.loads) do
            local address = match + offset;
            if not bytes_match(address, copy.original) then
                print('[lodfix] The game code is not what lodfix expects. Nothing was changed.');
                return false;
            end
            table.insert(sites, { address = address, original = copy.original });
        end
    end

    -- Step 2: every site checked out, so patch them all.
    for _, site in ipairs(sites) do
        ashita.memory.unprotect(site.address, #replacement);
        write_bytes(site.address, replacement);
        table.insert(patched, site);
    end

    return true;
end

-- Put the original bytes back at every patched site.
local function remove_patch()
    for _, site in ipairs(patched) do
        write_bytes(site.address, site.original);
    end
    patched = {};
end

ashita.events.register('load', 'load_cb', function ()
    if apply_patch() then
        print('[lodfix] Active: zone objects are drawn at full detail at any distance.');
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    if #patched > 0 then
        remove_patch();
        print('[lodfix] Original game code restored.');
    end
end);

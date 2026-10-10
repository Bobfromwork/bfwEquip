# bfwEquip

bfwEquip is a lightweight equipment-set addon for the OctoWoW client. It saves
the item links currently equipped in each gear slot and equips matching items
from your bags.

## Install

Copy the `bfwEquip` folder (containing `bfwEquip.toc`, `bfwEquip.lua`, and
`Bindings.xml`) into the client's `Interface/AddOns` directory, then enable
bfwEquip in the AddOns list at character selection.

## Use

- `/bfwequip` or `/bfwequip ui` opens the in-game gear-set window.
- `/bfwequip save <name>` saves your currently equipped items under a name.
- `/bfwequip list` lists saved sets.
- `/bfwequip equip <name>` equips matching items found in your bags.
- `/bfwequip delete <name>` deletes a saved set.
- `/bfwequip bind <name> <1-10>` assigns a set to a hotkey slot.
- `/bfwequip bind <name> off` clears that set's hotkey slot.
- `/bfwequip help` shows the commands.

The window is draggable and resizable from its lower-right corner, and its size
is remembered between sessions. The saved-set selector and **Save Current**
menu use the client's standard dropdown controls.
Use the **Save slots** dropdown to save all slots, **Trinkets Only**, **Main +
Off Hand**, or any combination of individually checked gear slots. The chosen
scope is used by both new saves and overwrites; unchecked slots are left
unchanged when that set is equipped. Partial sets use the bag-based equip path
so a matching native equipment set cannot replace additional slots. When the
requested item is already equipped in another slot covered by the same set,
the addon moves it to an empty bag slot before equipping it in the requested
slot, then rescans the set to equip the displaced slot too. This avoids trying
to put an incompatible displaced weapon into the other hand.
Bag-based equips skip unchanged slots, perform at most one changed-item
operation per client frame, and wait for the resulting inventory state to
remain settled for 5 ms before continuing. An operation that fails to settle
within 1.5 seconds stops the remaining equip sequence.
Main-hand and off-hand slots saved in the set are each retried once at the end
of the bag-based equip sequence; final status is based on the resulting
equipped items, so successful retries are not reported as unavailable. Sets
requiring a cross-hand weapon swap use this bag-based path even when the native
equipment-set API is available; other full sets can still use the native API.
Click **Save Current** to choose **Save as New Set** (using the name field) or
**Overwrite Selected Set**. Saving as new refuses a name that already exists.
When overwriting, an empty name field keeps the selected set's name; a different
name renames the selected set while replacing its gear and carrying over its
hotkey. A name already used by another set is rejected.

Select a set and click **Bind Hotkey** to assign the next available slot, or
use `/bfwequip bind <name> <slot>` to choose one explicitly. The button clears
an existing assignment; use `/bfwequip bind <name> off` to clear it from chat.
Then open **Game Menu → Key Bindings → bfwEquip** and assign a key to that
numbered gear-set slot. The same section includes **Toggle bfwEquip Window** to
assign a key that opens or closes the main window. There are 10 gear-set slots;
assigning an occupied slot moves it from its previous set. Assignments are
saved with the addon and are cleared when their set is deleted.

Set names may contain spaces and are matched without regard to capitalization.
Saved gear is stored in the `bfwEquipDB` SavedVariables table. Equipping swaps
items using the legacy container and inventory pickup APIs and is stopped during
combat. A set may be only partially equipped when an item is missing, bag-locked,
or rejected for its target slot; the addon reports those slots instead of
claiming the set was fully equipped. Starting another set equip replaces the
active bag-equip run or pending native-result check; any remaining steps from
the previous bag-equip run are canceled. Slots saved empty are left unchanged.

The addon targets interface version 11200. When ClassicAPI's `C_EquipmentSet`
create/save/use functions are available, saving also syncs a native client
equipment set and equipping uses that API; the result is checked against the
saved items before success is reported. The addon's own copy remains in
`bfwEquipDB`. On clients without those functions, equipping falls back to the
established WoW 1.12 inventory/bag APIs.

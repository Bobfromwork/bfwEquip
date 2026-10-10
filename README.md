# bfwEquip

bfwEquip is a lightweight equipment-set addon for the OctoWoW client. It saves
the item links currently equipped in each gear slot and equips matching items
from your bags.

## Install

Copy the `bfwEquip` folder (containing `bfwEquip.toc` and `bfwEquip.lua`) into
the client's `Interface/AddOns` directory, then enable bfwEquip in the AddOns
list at character selection.

## Use

- `/bfwequip save <name>` saves your currently equipped items under a name.
- `/bfwequip list` lists saved sets.
- `/bfwequip equip <name>` equips matching items found in your bags.
- `/bfwequip delete <name>` deletes a saved set.
- `/bfwequip help` shows the commands.

Set names may contain spaces and are matched without regard to capitalization.
Saved gear is stored in the `bfwEquipDB` SavedVariables table. Equipping swaps
items using the legacy container and inventory pickup APIs and is stopped during
combat. A set may be only partially equipped when an item is missing, bag-locked,
or rejected for its target slot; the addon reports those slots instead of
claiming the set was fully equipped. Slots saved empty are left unchanged.

The addon targets interface version 11200. When ClassicAPI's `C_EquipmentSet`
create/save/use functions are available, saving also syncs a native client
equipment set and equipping uses that API; the result is checked against the
saved items before success is reported. The addon's own copy remains in
`bfwEquipDB`. On clients without those functions, equipping falls back to the
established WoW 1.12 inventory/bag APIs.

/*
 * ios_dungeon.c - Provide dungeon.lua data for iOS
 *
 * This provides the REAL NetHack dungeon structure
 */

#include <stdio.h>
#include <string.h>

// Complete dungeon.lua content from NetHack
const char* ios_get_dungeon_lua(void) {
    return
"-- NetHack dungeon description\n\
dungeon = {\n\
   {\n\
      name = \"The Dungeons of Doom\",\n\
      bonetag = \"D\",\n\
      base = 25,\n\
      range = 5,\n\
      alignment = \"unaligned\",\n\
      themerooms = \"themerms.lua\",\n\
      branches = {\n\
         {\n\
            name = \"The Gnomish Mines\",\n\
            base = 2,\n\
            range = 3\n\
         },\n\
         {\n\
            name = \"Sokoban\",\n\
            chainlevel = \"oracle\",\n\
            base = 1,\n\
            direction = \"up\"\n\
         },\n\
         {\n\
            name = \"The Quest\",\n\
            chainlevel = \"oracle\",\n\
            base = 6,\n\
            range = 2,\n\
            branchtype = \"portal\"\n\
         },\n\
         {\n\
            name = \"Fort Ludios\",\n\
            base = 18,\n\
            range = 4,\n\
            branchtype = \"portal\"\n\
         },\n\
         {\n\
            name = \"Gehennom\",\n\
            chainlevel = \"castle\",\n\
            base = 0,\n\
            branchtype = \"no_down\"\n\
         },\n\
         {\n\
            name = \"The Elemental Planes\",\n\
            base = 1,\n\
            branchtype = \"no_down\",\n\
            direction = \"up\"\n\
         }\n\
      },\n\
      levels = {\n\
         {\n\
            name = \"rogue\",\n\
            bonetag = \"R\",\n\
            base = 15,\n\
            range = 4,\n\
            flags = \"roguelike\",\n\
         },\n\
         {\n\
            name = \"oracle\",\n\
            bonetag = \"O\",\n\
            base = 5,\n\
            range = 5,\n\
            alignment = \"neutral\"\n\
         },\n\
         {\n\
            name = \"bigrm\",\n\
            bonetag = \"B\",\n\
            base = 10,\n\
            range = 3,\n\
            chance = 40,\n\
            nlevels = 12\n\
         },\n\
         {\n\
            name = \"medusa\",\n\
            base = -5,\n\
            range = 4,\n\
            nlevels = 4,\n\
            alignment = \"chaotic\"\n\
         },\n\
         {\n\
            name = \"castle\",\n\
            base = -1\n\
         }\n\
      }\n\
   },\n\
   {\n\
      name = \"Gehennom\",\n\
      bonetag = \"G\",\n\
      base = 20,\n\
      range = 5,\n\
      flags = { \"mazelike\", \"hellish\" },\n\
      lvlfill = \"hellfill\",\n\
      alignment = \"noalign\",\n\
      branches = {\n\
         {\n\
            name = \"Vlad's Tower\",\n\
            base = 9,\n\
            range = 5,\n\
            direction = \"up\"\n\
         }\n\
      },\n\
      levels = {\n\
         {\n\
            name = \"valley\",\n\
            bonetag = \"V\",\n\
            base = 1\n\
         },\n\
         {\n\
            name = \"sanctum\",\n\
            base = -1\n\
         },\n\
         {\n\
            name = \"juiblex\",\n\
            bonetag = \"J\",\n\
            base = 4,\n\
            range = 4\n\
         },\n\
         {\n\
            name = \"baalz\",\n\
            bonetag = \"B\",\n\
            base = 6,\n\
            range = 4\n\
         },\n\
         {\n\
            name = \"asmodeus\",\n\
            bonetag = \"A\",\n\
            base = 2,\n\
            range = 6\n\
         },\n\
         {\n\
            name = \"wizard1\",\n\
            base = 11,\n\
            range = 6\n\
         },\n\
         {\n\
            name = \"wizard2\",\n\
            bonetag = \"X\",\n\
            chainlevel = \"wizard1\",\n\
            base = 1\n\
         },\n\
         {\n\
            name = \"wizard3\",\n\
            bonetag = \"Y\",\n\
            chainlevel = \"wizard1\",\n\
            base = 2\n\
         },\n\
         {\n\
            name = \"orcus\",\n\
            bonetag = \"O\",\n\
            base = 10,\n\
            range = 6\n\
         },\n\
         {\n\
            name = \"fakewiz1\",\n\
            bonetag = \"F\",\n\
            base = -6,\n\
            range = 4\n\
         },\n\
         {\n\
            name = \"fakewiz2\",\n\
            bonetag = \"G\",\n\
            base = -6,\n\
            range = 4\n\
         },\n\
      }\n\
   },\n\
   {\n\
      name = \"The Gnomish Mines\",\n\
      bonetag = \"M\",\n\
      base = 8,\n\
      range = 2,\n\
      alignment = \"lawful\",\n\
      flags = { \"mazelike\" },\n\
      lvlfill = \"minefill\",\n\
      levels = {\n\
         {\n\
            name = \"minetn\",\n\
            bonetag = \"T\",\n\
            base = 3,\n\
            range = 2,\n\
            nlevels = 7,\n\
            flags = \"town\"\n\
         },\n\
         {\n\
            name = \"minend\",\n\
            base = -1,\n\
            nlevels = 3\n\
         },\n\
      }\n\
   },\n\
   {\n\
      name = \"The Quest\",\n\
      bonetag = \"Q\",\n\
      base = 5,\n\
      range = 2,\n\
      levels = {\n\
         {\n\
            name = \"x-strt\",\n\
            base = 1,\n\
            range = 1\n\
         },\n\
         {\n\
            name = \"x-loca\",\n\
            bonetag = \"L\",\n\
            base = 3,\n\
            range = 1\n\
         },\n\
         {\n\
            name = \"x-goal\",\n\
            base = -1\n\
         },\n\
      }\n\
   },\n\
   {\n\
      name = \"Sokoban\",\n\
      base = 4,\n\
      alignment = \"neutral\",\n\
      flags = { \"mazelike\" },\n\
      entry = -1,\n\
      levels = {\n\
         {\n\
            name = \"soko1\",\n\
            base = 1,\n\
            nlevels = 2\n\
         },\n\
         {\n\
            name = \"soko2\",\n\
            base = 2,\n\
            nlevels = 2\n\
         },\n\
         {\n\
            name = \"soko3\",\n\
            base = 3,\n\
            nlevels = 2\n\
         },\n\
         {\n\
            name = \"soko4\",\n\
            base = 4,\n\
            nlevels = 2\n\
         },\n\
      }\n\
   },\n\
   {\n\
      name = \"Fort Ludios\",\n\
      base = 1,\n\
      bonetag = \"K\",\n\
      flags = { \"mazelike\" },\n\
      alignment = \"unaligned\",\n\
      levels = {\n\
         {\n\
            name = \"knox\",\n\
            bonetag = \"K\",\n\
            base = -1\n\
         }\n\
      }\n\
   },\n\
   {\n\
      name = \"Vlad's Tower\",\n\
      base = 3,\n\
      bonetag = \"T\",\n\
      protofile = \"tower\",\n\
      alignment = \"chaotic\",\n\
      flags = { \"mazelike\" },\n\
      entry = -1,\n\
      levels = {\n\
         {\n\
            name = \"tower1\",\n\
            base = 1\n\
         },\n\
         {\n\
            name = \"tower2\",\n\
            base = 2\n\
         },\n\
         {\n\
            name = \"tower3\",\n\
            base = 3\n\
         },\n\
      }\n\
   },\n\
   {\n\
      name = \"The Elemental Planes\",\n\
      bonetag = \"E\",\n\
      base = 6,\n\
      alignment = \"unaligned\",\n\
      flags = { \"mazelike\" },\n\
      entry = -2,\n\
      levels = {\n\
         {\n\
            name = \"astral\",\n\
            base = 1\n\
         },\n\
         {\n\
            name = \"water\",\n\
            base = 2\n\
         },\n\
         {\n\
            name = \"fire\",\n\
            base = 3\n\
         },\n\
         {\n\
            name = \"air\",\n\
            base = 4\n\
         },\n\
         {\n\
            name = \"earth\",\n\
            base = 5\n\
         },\n\
         {\n\
            name = \"dummy\",\n\
            base = 6\n\
         },\n\
      }\n\
   },\n\
   {\n\
      name = \"The Tutorial\",\n\
      base = 2,\n\
      flags = { \"mazelike\", \"unconnected\" },\n\
      levels = {\n\
         {\n\
            name = \"tut-1\",\n\
            base = 1,\n\
         },\n\
         {\n\
            name = \"tut-2\",\n\
            base = 2,\n\
         },\n\
      }\n\
   },\n\
}\n";
}
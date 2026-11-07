# Godot 4 project (GDScript, static typing, English in-game text)
GODOT=flatpak run org.godotengine.Godot

Delegation (save tokens):
- Need to search/understand >2 files → Explore.
- Planned change touching several files → godot-coder with exact task (files, nodes, behavior).
- After changes → godot-tester.
- Small edits (1 file, few lines) → do it yourself, no subagent.
Never read whole .tscn files; grep them. Never edit .godot/ or *.import.

Structure: main=res://ui/TitleScreen.tscn; autoloads=Drugs,MetaProgress,GameState,SFX,Graphics,Voice,Walkman,Cutscene,SaveGame,Jobs,Headlines,SceneLoader,Story,Survival,Crafting,Camp,_mcp_game_helper; folders=addons,assets,autoload,dev-tools,docs,interactables,items,npc,player,tools,ui,world

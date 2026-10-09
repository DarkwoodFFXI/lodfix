# lodfix
Level-of-detail (see "CONTEXT" section below if you don't know what level-of-detail means) fixer for FFXI. 

LICENSE: MIT.

CREDITS: Mostly Claude. Not quite "vibe coded," but I'm not smart enough, or at least not patient enough, to have figured these memory offsets and assembly instructions on my own.

I'm only posting this here so that Phoenix can approve it for use. This was created to solve a problem I find annoying, for my personal use. Use at your own risk, etc.

CONTEXT: FFXI often has different models for the same object (e.g., a tree) at different levels of detail and the model displayed depends on how far away you are from the object. So when you're far away from something the game will display a less detailed model (i.e., fewer polygons) and it will switch over to a more detailed model (i.e., more polygons) as you cross a distance threshold approaching it.

I tried to load some screenshots here to show this, but it turns out it is very hard to illustrate with still images. Adding a .gif is on my to-do list. In the meantime, if you don't know what I'm talking about: go outside, pick a tree, run away from it until it disappears, and then run towards it. You will probably see it change shape at least one. Now you'll see it all the time and it will drive you nuts. You're welcome.

PROBLEM: It looks awful when the model switches from one to another.

SOLUTION: Always show the highest quality model. It's (at least) 2026 and we don't need to be shackled by PS2 limitations anymore.

INSTALLATION: Copy "lodfix.lua" to /(whatever your directory structure looks like)/PhoenixXI/addons/lodfix/ (obviously use backslashes if you're a Windows person). In game run "/addon load lodfix". That's it. This assumes you have functioning Ashita (if you're on Phoenix, you do).

KNOWN ISSUE(S): It doesn't appear to work for some things in town. I've observed it not working at least in Upper Jeuno and multiple parts of Windurst. I'm working on it.

# Javit
### shavit's jailbreak

This was never supposed to be public, but it's not used anywhere nowadays and I've retired from Source server development. I figured it could be helpful if this was made public and perhaps forked.

This contains 2 plugins which should set up an Israeli styled Jailbreak server for Source games.

- Javit - code related to Last Requests and other stuff (SM_Hosties alternative)
- Javit_JB - plugin that manages the Israeli Jailbreak features. This one is a rewrite of [Jailbreak Addons v2](https://gist.github.com/shavitush/c7829a2d32b955ee869180fd38ff391d) and is intended to be less "spaghetti".

Some stuff to note:

- Javit will throw errors from the Deagle Toss timer every once in a while. I never bothered to solve it and it never affected gameplay nor was it leaking memory.
- Javit_Jb is not finished. `OnPluginStart()` has a small list of to-do that I intended to do, but also here I simply lost interest and stopped developing it.

This was developed for [YOURGAME.co.il](https://yourgame.co.il/) but it is deprecated.

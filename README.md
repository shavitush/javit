# Javit
### shavit's jailbreak

Credits
___

* evadog for flamethrower.
* entcontrol for missiles (dr hax).

Team managements
--
- [ ] VoteCT (+API)
- [ ] Rewrite JBAddons and make VoteCTs dynamic.
- [ ] Rewrite CT bans.


Basic LRs
--
- [x] Colored beacons.
- [x] Beacon sounds.
- [x] LR menu.
- [x] Initialize LR.
- [x] Abort LR.


Advanced LRs
--
- [x] Save pre-LR weapons and give them to the winner.
- [x] Abort on disconnect.
- [x] Advanced guntoss modes.


Sounds
--
- [x] On LR activated (lr_activated.mp3).
- [x] On LR aborted (lr_error.mp3).
- [x] On LR started (lr_start.mp3).
- [x] On custom LRs (lr_wow.mp3/lr_hax.mp3).


Games
--
- [x] Dodgeball
- [x] Shot4Shot
- [x] Random - 500-2500hp, random weapon depending on game, 0.5x-1.5x speed, 0.75x-1.25x gravity.
- [x] NoScope Battle (random weapon, depending on game)
    - [ ] Shot4Shot mode for noscope battle
- [x] Grenade Fight
- [x] Backstabs
- [x] Pro90
- [x] Headshots
- [x] Jumpshots (scout/ssg and usp/usp-s)
- [x] Russian Roulette
- [x] Knife Fight
- [x] Mag4Mag
- [x] Flamethrower
- [x] Hax Fight
- [x] Deagle Toss
- [x] Shotgun Wars
- [x] Rebel
- [x] Molotov Fight (CS:GO only)
- [x] Freeday/VIP (needs JBaddons2 API)
- [x] Circle of Doom
- [ ] [Dash Fight](https://gist.github.com/7b64ebe83843e710d2542b456650d76b)


Rankings
--
- [x] Count LR wins - need more than 10 active players or an admin.
- [x] `sm_top`/`sm_lrtop` commands.


API
--
- [x] LRTypes Javit_GetClientLR(int client)
- [x] void Javit_GetLRName(LRTypes lr, char[] buffer, int maxlen)
- [x] int Javit_GetClientPartner(int client) // get lr partner
- [x] void Javit_OnLRAvailable()
- [x] bool Javit_OnLRStart(LRTypes type, int prisoner, int guard) - return false to not allow the lr to start
- [x] void Javit_OnLRFinish(LRTypes type, int winner, int loser)
- [ ] custom LRs API
